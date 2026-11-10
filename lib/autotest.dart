/// A test run on a real phone, without touching it:
///
///   xcrun devicectl device process launch --console --device ID BUNDLE --autotest [--model kev-0.8b]
///
/// Picks the model (the recommended one, or --model), downloads it if it is missing, loads it, asks
/// the quick questions about two sample messages, prints answers, timings and memory, frees the
/// model and exits.
library;

import 'dart:async';
import 'dart:io';

import 'package:athena_native/athena_native.dart';

import 'catalog.dart';
import 'controller.dart';
import 'decision.dart';

const _samples = {
  'bank': 'Your account has been locked due to unusual sign-in activity. Verify your identity within '
      '24 hours at http://secure-account-check.co/login or your account will be permanently suspended.',
  'dinner': 'Hey! Dinner at ours on Saturday at 7? Bring nothing but yourselves. Let me know if you can make it.',
};

Future<void> runAutotest(AthenaController c, List<String> args) async {
  void log(String s) => stdout.writeln('[athena] $s');
  String mb(int? bytes) => bytes == null ? '?' : '${bytes ~/ (1024 * 1024)} MB';
  final i = args.indexOf('--model');
  final wanted = i >= 0 && i + 1 < args.length ? modelById(args[i + 1]) : null;

  await c.start();
  final d = c.device;
  if (d != null) {
    log('phone: ${d.name} (${d.machine}), ${ramGiB(d.ramBytes).toStringAsFixed(2)} GiB reported, '
        'recommended: ${recommendedModel(d.ramBytes)?.id}');
  }
  if (wanted != null && wanted.id != c.model?.id) await c.useModel(wanted);
  log('model: ${c.model?.id}, phase: ${c.phase.name}');
  if (c.phase == Phase.needsDownload) await c.download();

  var lastTenth = -1;
  final clock = Stopwatch()..start();
  while (c.phase != Phase.ready && c.phase != Phase.failed && c.phase != Phase.unsupported) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (c.phase == Phase.downloading && c.model != null) {
      final tenth = c.received * 10 ~/ c.model!.bytes;
      if (tenth != lastTenth) {
        lastTenth = tenth;
        log('download: ${tenth * 10}% (${mb(c.received)}) after ${clock.elapsed.inSeconds} s');
      }
    }
  }
  if (c.phase != Phase.ready) {
    log('stopped at ${c.phase.name}: ${c.message}');
    exit(1);
  }
  log('ready after ${clock.elapsed.inMilliseconds} ms on the ${c.onGpu ? 'GPU' : 'CPU'}; '
      'app may still use ${mb(AthenaNative.appAvailableMemoryBytes())}');

  for (final MapEntry(key: name, value: text) in _samples.entries) {
    for (final q in quickQuestions) {
      await c.ask(text, q);
      if (c.askError != null) {
        log('$name | ${q.label} | error: ${c.askError}');
        continue;
      }
      final v = c.verdicts.first;
      log('$name | ${q.label} | ${v.headline} | p(yes) ${v.yesProbability.toStringAsFixed(4)} | '
          '${v.elapsed.inMilliseconds} ms');
    }
    c.textChanged();
  }
  log('memory: app may still use ${mb(AthenaNative.appAvailableMemoryBytes())}');
  await c.shutdown();
  log('done');
  exit(0);
}
