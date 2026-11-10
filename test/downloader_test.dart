import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:athena/catalog.dart';
import 'package:athena/downloader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in for Hugging Face: /resolve redirects to /cdn, which serves the bytes and honours Range
/// unless told not to.
class FakeHub {
  FakeHub(this.body);

  final Uint8List body;
  late HttpServer server;
  bool honourRange = true;
  int status = 200;
  final ranges = <String?>[];

  String get url => 'http://127.0.0.1:${server.port}/resolve/model.gguf';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final res = req.response;
      if (req.uri.path.startsWith('/resolve')) {
        res.statusCode = HttpStatus.found;
        res.headers.set(HttpHeaders.locationHeader, '/cdn/model.gguf?sig=1');
        return res.close();
      }
      if (status != 200) {
        res.statusCode = status;
        return res.close();
      }
      final range = req.headers.value(HttpHeaders.rangeHeader);
      ranges.add(range);
      var from = 0;
      if (range != null && honourRange) {
        from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        res.statusCode = HttpStatus.partialContent;
      }
      res.contentLength = body.length - from;
      res.add(body.sublist(from));
      await res.close();
    });
  }
}

ModelInfo fakeModel(Uint8List body, {String? sha}) => ModelInfo(
      id: 'fake',
      name: 'Fake',
      repo: 'x/y',
      revision: 'r',
      file: 'model.gguf',
      bytes: body.length,
      sha256: sha ?? sha256.convert(body).toString(),
      minRamGiB: 0,
      contextTokens: 512,
      license: '',
      licenseUrl: '',
      blurb: '',
    );

void main() {
  final body = Uint8List.fromList(List.generate(5 * 1024 * 1024 + 123, (_) => Random(7).nextInt(256)));
  late FakeHub hub;
  late Directory dir;

  setUp(() async {
    hub = FakeHub(body);
    await hub.start();
    dir = await Directory.systemTemp.createTemp('athena-dl');
  });

  tearDown(() async {
    await hub.server.close(force: true);
    await dir.delete(recursive: true);
  });

  Future<List<DownloadEvent>> run(ModelInfo m) => downloadModel(dir.path, m, url: hub.url).toList();

  test('downloads through the redirect and keeps the file only after the hash matches', () async {
    final m = fakeModel(body);
    final events = await run(m);
    expect(events.last, isA<DownloadDone>());
    expect(events.whereType<DownloadVerifying>(), hasLength(1));
    expect(File(modelPath(dir.path, m)).readAsBytesSync(), body);
    expect(partialBytes(dir.path, m), 0);
    expect(isDownloaded(dir.path, m), isTrue);
  });

  test('resumes from the part file with a Range header that survived the redirect', () async {
    final m = fakeModel(body);
    File('${dir.path}/model.gguf.part').writeAsBytesSync(body.sublist(0, 2000000));
    final events = await run(m);
    expect(events.last, isA<DownloadDone>());
    expect(hub.ranges, ['bytes=2000000-']);
    expect(File(modelPath(dir.path, m)).readAsBytesSync(), body);
  });

  test('starts over when the server ignores Range', () async {
    final m = fakeModel(body);
    hub.honourRange = false;
    File('${dir.path}/model.gguf.part').writeAsBytesSync(body.sublist(0, 1000));
    final events = await run(m);
    expect(events.last, isA<DownloadDone>());
    expect(File(modelPath(dir.path, m)).readAsBytesSync(), body);
  });

  test('a file with the wrong hash is deleted, not kept', () async {
    final m = fakeModel(body, sha: '0' * 64);
    final events = await run(m);
    expect(events.last, isA<DownloadFailed>());
    expect((events.last as DownloadFailed).message, contains('damaged'));
    expect(isDownloaded(dir.path, m), isFalse);
    expect(partialBytes(dir.path, m), 0);
  });

  test('a server error is reported and nothing is kept', () async {
    final m = fakeModel(body);
    hub.status = 404;
    final events = await run(m);
    expect((events.last as DownloadFailed).message, contains('404'));
    expect(isDownloaded(dir.path, m), isFalse);
  });
}
