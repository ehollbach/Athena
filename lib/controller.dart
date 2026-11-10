/// Athena's state: which phone, which model, whether it is downloaded and loaded, and the answers.
library;

import 'dart:async';
import 'dart:io';

import 'package:athena_native/athena_native.dart';
import 'package:flutter/foundation.dart';

import 'catalog.dart';
import 'decision.dart';
import 'downloader.dart';

enum Phase { starting, unsupported, needsDownload, downloading, verifying, loading, ready, failed }

class AthenaController extends ChangeNotifier {
  Phase phase = Phase.starting;
  DeviceFacts? device;
  ModelInfo? model;

  /// For unsupported and failed: what to tell the user.
  String? message;
  int received = 0;

  bool busy = false;
  final verdicts = <Verdict>[]; // newest first, for the text as it is now
  String? askError;

  String? _dir;
  DecisionEngine? _engine;
  StreamSubscription<DownloadEvent>? _download;

  String get modelsDir => _dir!;
  bool get onGpu => _engine?.settings.onGpu ?? false;
  List<ModelInfo> get fittingModels => device == null ? const [] : modelsThatFit(device!.ramBytes);
  List<ModelInfo> get downloadedModels => [
        for (final m in catalog)
          if (_dir != null && isDownloaded(_dir!, m)) m,
      ];
  int get partial => model == null ? 0 : partialBytes(modelsDir, model!);

  Future<void> start() async {
    try {
      device = await AthenaNative.deviceFacts();
      _dir = await AthenaNative.modelsDir();
    } on Object catch (e) {
      return _fail('Athena could not read this phone ($e).');
    }
    final d = device!;
    if (!d.cpuSupported) {
      phase = Phase.unsupported;
      message = d.isIOS
          ? 'Athena needs an iPhone 11 or newer. This ${d.name} has an older chip.'
          : "Athena needs a newer processor than this phone's (it lacks the dot-product instructions).";
      return notifyListeners();
    }
    final best = recommendedModel(d.ramBytes);
    if (best == null) {
      phase = Phase.unsupported;
      message = 'Athena needs a phone with at least 3 GB of memory. This one has ${marketingRam(d.ramBytes)}.';
      return notifyListeners();
    }
    model = _savedChoice() ?? best;
    isDownloaded(modelsDir, model!) ? await _load() : _needsDownload();
  }

  // --- downloading

  void _needsDownload() {
    phase = Phase.needsDownload;
    received = partial;
    notifyListeners();
  }

  /// Free space the download still needs, with 300 MB spare; null if there is enough.
  Future<String?> _spaceProblem(ModelInfo m) async {
    final free = await AthenaNative.freeBytes(modelsDir);
    final needed = m.bytes - partialBytes(modelsDir, m) + 300 * 1000 * 1000;
    if (free == null || free >= needed) return null;
    return 'Your phone needs ${formatBytes(needed - free)} more free space for ${m.name}. '
        'Free some up, then try again.';
  }

  Future<void> download() async {
    final m = model!;
    if (phase == Phase.downloading) return;
    final problem = await _spaceProblem(m);
    if (problem != null) return _fail(problem, retry: Phase.needsDownload);
    phase = Phase.downloading;
    received = partial;
    message = null;
    notifyListeners();
    unawaited(AthenaNative.keepScreenOn(true));
    _download = downloadModel(modelsDir, m).listen((e) async {
      switch (e) {
        case DownloadProgress(:final received):
          this.received = received;
        case DownloadVerifying():
          phase = Phase.verifying;
        case DownloadFailed(:final message):
          unawaited(AthenaNative.keepScreenOn(false));
          _download = null;
          _fail(message, retry: Phase.needsDownload);
          return;
        case DownloadDone():
          unawaited(AthenaNative.keepScreenOn(false));
          _download = null;
          await _load();
          return;
      }
      notifyListeners();
    });
  }

  /// Stops the download; what came in so far is kept.
  Future<void> pauseDownload() async {
    await _download?.cancel();
    _download = null;
    unawaited(AthenaNative.keepScreenOn(false));
    _needsDownload();
  }

  // --- loading

  Future<void> _load() async {
    final m = model!;
    final d = device!;
    phase = Phase.loading;
    notifyListeners();
    await _engine?.close();
    _engine = null;
    final path = modelPath(modelsDir, m);
    try {
      if (d.isIOS) {
        // Metal first; if the GPU will not take it, the CPU
        try {
          _engine = await DecisionEngine.load(path, EngineSettings(contextTokens: m.contextTokens, gpuLayers: -1));
        } on EngineException {
          _engine = await DecisionEngine.load(path, EngineSettings(contextTokens: m.contextTokens));
        }
      } else {
        // Android: CPU, four threads (the big cores of most phones). Repacked weights are 2-3x faster
        // and take a second copy of the model: only where there is plenty of room.
        final roomy = d.ramBytes >= 2 * m.bytes + 3 * 1024 * 1024 * 1024;
        _engine = await DecisionEngine.load(
            path, EngineSettings(contextTokens: m.contextTokens, threads: 4, repack: roomy));
      }
    } on EngineException catch (e) {
      return _fail('${m.name} would not start: $e', retry: Phase.loading);
    }
    phase = Phase.ready;
    message = null;
    notifyListeners();
  }

  // --- asking

  /// Clears the answers: they belong to the text they were asked about.
  void textChanged() {
    if (verdicts.isEmpty && askError == null) return;
    verdicts.clear();
    askError = null;
    notifyListeners();
  }

  /// True if Athena reads only the start of [text] with this model.
  bool isTooLong(String text) => model != null && text.length > model!.maxTextChars;

  Future<void> ask(String text, QuickQuestion question) async {
    if (busy || _engine == null) return;
    final trimmed = text.trim();
    final state = trimmed.length > model!.maxTextChars ? trimmed.substring(0, model!.maxTextChars) : trimmed;
    busy = true;
    askError = null;
    notifyListeners();
    final watch = Stopwatch()..start();
    try {
      final out = await _engine!.decide(decisionRequest(state, question));
      final p = readYesProbability(out);
      verdicts.removeWhere((v) => v.question.instructions == question.instructions);
      verdicts.insert(0, Verdict(question: question, yesProbability: p, elapsed: watch.elapsed));
    } on DecisionError catch (e) {
      askError = e.message;
    } on EngineException catch (e) {
      askError = e.message;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  // --- settings

  /// Switches to another model: loads it if it is here, else asks to download it.
  Future<void> useModel(ModelInfo m) async {
    if (m.id == model?.id && phase == Phase.ready) return;
    await _download?.cancel();
    _download = null;
    await _engine?.close();
    _engine = null;
    model = m;
    verdicts.clear();
    _saveChoice(m);
    isDownloaded(modelsDir, m) ? await _load() : _needsDownload();
  }

  Future<void> delete(ModelInfo m) async {
    if (m.id == model?.id) {
      await _engine?.close();
      _engine = null;
      verdicts.clear();
    }
    deleteModel(modelsDir, m);
    if (m.id == model?.id) _needsDownload();
    notifyListeners();
  }

  /// After a failure: back to where it can be tried again.
  Future<void> retry() async {
    switch (_retry) {
      case Phase.loading:
        await _load();
      default:
        await download();
    }
  }

  Phase? _retry;

  void _fail(String text, {Phase? retry}) {
    phase = Phase.failed;
    message = text;
    _retry = retry;
    notifyListeners();
  }

  // the user's choice of model, kept next to the models
  File get _choiceFile => File('$modelsDir/selected-model.txt');

  ModelInfo? _savedChoice() {
    try {
      final m = modelById(_choiceFile.readAsStringSync().trim());
      return m != null && fittingModels.contains(m) ? m : null;
    } on FileSystemException {
      return null;
    }
  }

  void _saveChoice(ModelInfo m) {
    try {
      _choiceFile.writeAsStringSync(m.id);
    } on FileSystemException {
      // the choice is a convenience: without it Athena picks the recommended model again
    }
  }

  /// Frees the model (and its GPU memory) so the process can exit cleanly.
  Future<void> shutdown() async {
    await _download?.cancel();
    await _engine?.close();
    _engine = null;
  }

  @override
  void dispose() {
    unawaited(shutdown());
    super.dispose();
  }
}
