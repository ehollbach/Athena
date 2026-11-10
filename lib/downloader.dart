/// Downloads a model on its own isolate: resumes where it stopped, hashes as it goes, and keeps
/// the file only if its SHA-256 is the one in the catalog.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import 'catalog.dart';

sealed class DownloadEvent {}

class DownloadProgress extends DownloadEvent {
  DownloadProgress(this.received, this.total);
  final int received;
  final int total;
}

/// The bytes are all here; the hash is being checked.
class DownloadVerifying extends DownloadEvent {}

class DownloadDone extends DownloadEvent {
  DownloadDone(this.path);
  final String path;
}

class DownloadFailed extends DownloadEvent {
  DownloadFailed(this.message);
  final String message;
}

/// Where a verified model lives. Only verified files get this name.
String modelPath(String dir, ModelInfo m) => '$dir/${m.file}';
String _partPath(String dir, ModelInfo m) => '$dir/${m.file}.part';

/// Bytes already downloaded (resumable), 0 if none.
int partialBytes(String dir, ModelInfo m) {
  final f = File(_partPath(dir, m));
  return f.existsSync() ? f.lengthSync() : 0;
}

/// A model counts as downloaded when its verified file is there at full size.
bool isDownloaded(String dir, ModelInfo m) {
  final f = File(modelPath(dir, m));
  return f.existsSync() && f.lengthSync() == m.bytes;
}

void deleteModel(String dir, ModelInfo m) {
  for (final p in [modelPath(dir, m), _partPath(dir, m)]) {
    final f = File(p);
    if (f.existsSync()) f.deleteSync();
  }
}

/// Starts (or resumes) the download. Cancel the subscription to stop it; the part file stays for next time.
/// [url] replaces the model's Hugging Face URL (tests).
Stream<DownloadEvent> downloadModel(String dir, ModelInfo m, {String? url}) {
  late StreamController<DownloadEvent> out;
  Isolate? isolate;
  final port = ReceivePort();
  out = StreamController<DownloadEvent>(
    onListen: () async {
      port.listen((e) {
        out.add(e as DownloadEvent);
        if (e is DownloadDone || e is DownloadFailed) {
          port.close();
          out.close();
        }
      });
      isolate = await Isolate.spawn(
        _download,
        _Job(port.sendPort, url ?? m.url, _partPath(dir, m), modelPath(dir, m), m.bytes, m.sha256),
        debugName: 'athena-download',
      );
    },
    onCancel: () {
      isolate?.kill(priority: Isolate.immediate);
      port.close();
    },
  );
  return out.stream;
}

class _Job {
  _Job(this.events, this.url, this.part, this.done, this.size, this.sha256);
  final SendPort events;
  final String url, part, done, sha256;
  final int size;
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

Future<void> _download(_Job job) async {
  final send = job.events.send;
  try {
    final file = File(job.part);
    var have = file.existsSync() ? file.lengthSync() : 0;
    if (have > job.size) {
      file.deleteSync();
      have = 0;
    }

    var digest = _DigestSink();
    var hasher = sha256.startChunkedConversion(digest);
    if (have > 0) {
      // the hash of what is already here, so the finished file never has to be read twice
      send(DownloadProgress(have, job.size));
      await for (final chunk in file.openRead()) {
        hasher.add(chunk);
      }
    }

    if (have < job.size) {
      final client = HttpClient()
        ..userAgent = 'Athena (iOS/Android decision app)'
        ..connectionTimeout = const Duration(seconds: 30);
      try {
        final response = await _get(client, Uri.parse(job.url), from: have);
        if (response.statusCode == 200 && have > 0) {
          // the server would not resume: start over
          digest = _DigestSink();
          hasher = sha256.startChunkedConversion(digest);
          have = 0;
        } else if (response.statusCode != 200 && response.statusCode != 206) {
          await response.drain<void>();
          send(DownloadFailed('The download server said ${response.statusCode}. Try again later.'));
          return;
        }
        final sink = file.openWrite(mode: have > 0 ? FileMode.append : FileMode.write);
        var reported = have;
        try {
          await for (final chunk in response.timeout(const Duration(seconds: 60))) {
            sink.add(chunk);
            hasher.add(chunk);
            have += chunk.length;
            if (have - reported >= 2 * 1024 * 1024) {
              reported = have;
              send(DownloadProgress(have, job.size));
            }
          }
        } finally {
          await sink.close();
        }
      } finally {
        client.close(force: true);
      }
    }

    send(DownloadProgress(have, job.size));
    if (have != job.size) {
      send(DownloadFailed('The download stopped early. Tap to continue.'));
      return;
    }
    send(DownloadVerifying());
    hasher.close();
    if (digest.value.toString() != job.sha256) {
      file.deleteSync();
      send(DownloadFailed('The download was damaged, so Athena deleted it. Try again.'));
      return;
    }
    file.renameSync(job.done);
    send(DownloadDone(job.done));
  } on TimeoutException {
    send(DownloadFailed('The connection went quiet. Check your internet and continue.'));
  } on SocketException {
    send(DownloadFailed('No connection. Check your internet and continue.'));
  } on HttpException {
    send(DownloadFailed('The connection dropped. Continue to pick up where it stopped.'));
  } on FileSystemException catch (e) {
    final full = e.osError?.errorCode == 28; // ENOSPC
    send(DownloadFailed(full ? 'Your phone is out of space. Free some up and continue.' : 'Could not save the model: ${e.message}'));
  }
}

/// GET with a Range header that survives redirects: Hugging Face sends downloads on to its CDN.
Future<HttpClientResponse> _get(HttpClient client, Uri uri, {required int from}) async {
  for (var hops = 0; hops < 8; hops++) {
    final request = await client.getUrl(uri);
    request.followRedirects = false;
    if (from > 0) request.headers.set(HttpHeaders.rangeHeader, 'bytes=$from-');
    final response = await request.close();
    if (!response.isRedirect) return response;
    final location = response.headers.value(HttpHeaders.locationHeader);
    await response.drain<void>();
    if (location == null) break;
    uri = uri.resolve(location);
  }
  throw const HttpException('too many redirects');
}
