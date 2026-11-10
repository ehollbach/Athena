/// Athena's native side: what the phone is (a method channel) and kneejerk's decision engine (dart:ffi).
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show MethodChannel;

const _channel = MethodChannel('athena_native');

/// The phone, as far as choosing a model goes.
class DeviceFacts {
  const DeviceFacts({
    required this.platform,
    required this.machine,
    required this.name,
    required this.ramBytes,
    required this.osVersion,
    required this.cpuSupported,
  });

  final String platform; // "ios" or "android"
  final String machine; // "iPhone14,5", "Pixel 8a"
  final String name; // "iPhone 13", "Google Pixel 8a"
  final int ramBytes;
  final String osVersion;

  /// The engine is built for ARMv8.2 with dot product: the A13 (iPhone 11) and newer, and on Android
  /// Cortex-A55/A75 and newer. An older CPU would crash on the first instruction it lacks.
  final bool cpuSupported;

  bool get isIOS => platform == 'ios';
}

abstract final class AthenaNative {
  static Future<DeviceFacts> deviceFacts() async {
    final m = (await _channel.invokeMapMethod<String, Object?>('deviceFacts'))!;
    final platform = m['platform']! as String;
    final machine = m['machine']! as String;
    final ios = platform == 'ios';
    return DeviceFacts(
      platform: platform,
      machine: machine,
      name: ios ? appleDeviceName(machine) : m['name']! as String,
      ramBytes: (m['ramBytes']! as num).toInt(),
      osVersion: m['osVersion']! as String,
      cpuSupported: ios ? appleChipSupported(machine) : _androidCpuHasDotProd(),
    );
  }

  /// A directory for models that backups skip. iOS: Application Support/models; Android: no_backup/models.
  static Future<String> modelsDir() async => (await _channel.invokeMethod<String>('modelsDir'))!;

  /// Free space on the volume of [path], or null if the phone would not say.
  static Future<int?> freeBytes(String path) async =>
      (await _channel.invokeMethod<num>('freeBytes', {'path': path}))?.toInt();

  /// iOS launch arguments (devicectl ... --autotest); empty on Android.
  static Future<List<String>> launchArguments() async =>
      (await _channel.invokeListMethod<String>('launchArguments')) ?? const [];

  /// Keeps the screen from locking, so a long download is not suspended with the app.
  static Future<void> keepScreenOn(bool on) => _channel.invokeMethod('keepScreenOn', {'on': on});

  /// iOS only: how much more memory this app may take before iOS ends it (os_proc_available_memory).
  /// GPU memory the model holds is not counted against it.
  static int? appAvailableMemoryBytes() {
    if (!Platform.isIOS) return null;
    try {
      return DynamicLibrary.process()
          .lookupFunction<Size Function(), int Function()>('os_proc_available_memory')();
    } on ArgumentError {
      return null;
    }
  }
}

/// iPhone11,8 and older are the A12 and before: no dot product. iPads follow the same numbering
/// closely enough (iPad12,x is the A13 iPad).
bool appleChipSupported(String machine) {
  final m = RegExp(r'^(iPhone|iPad)(\d+),').firstMatch(machine);
  if (m == null) return false;
  return int.parse(m.group(2)!) >= 12;
}

bool _androidCpuHasDotProd() {
  try {
    final features = File('/proc/cpuinfo').readAsLinesSync().where((l) => l.startsWith('Features'));
    return features.isNotEmpty && features.every((l) => l.split(RegExp(r'\s+')).contains('asimddp'));
  } on FileSystemException {
    return false;
  }
}

/// "iPhone14,5" → "iPhone 13". Unknown identifiers come back as they are.
String appleDeviceName(String machine) => _appleNames[machine] ?? machine;

const _appleNames = {
  'iPhone10,1': 'iPhone 8', 'iPhone10,4': 'iPhone 8', 'iPhone10,2': 'iPhone 8 Plus', 'iPhone10,5': 'iPhone 8 Plus',
  'iPhone10,3': 'iPhone X', 'iPhone10,6': 'iPhone X', 'iPhone11,2': 'iPhone XS', 'iPhone11,4': 'iPhone XS Max',
  'iPhone11,6': 'iPhone XS Max', 'iPhone11,8': 'iPhone XR', 'iPhone12,1': 'iPhone 11', 'iPhone12,3': 'iPhone 11 Pro',
  'iPhone12,5': 'iPhone 11 Pro Max', 'iPhone12,8': 'iPhone SE', 'iPhone13,1': 'iPhone 12 mini',
  'iPhone13,2': 'iPhone 12', 'iPhone13,3': 'iPhone 12 Pro', 'iPhone13,4': 'iPhone 12 Pro Max',
  'iPhone14,4': 'iPhone 13 mini', 'iPhone14,5': 'iPhone 13', 'iPhone14,2': 'iPhone 13 Pro',
  'iPhone14,3': 'iPhone 13 Pro Max', 'iPhone14,6': 'iPhone SE', 'iPhone14,7': 'iPhone 14',
  'iPhone14,8': 'iPhone 14 Plus', 'iPhone15,2': 'iPhone 14 Pro', 'iPhone15,3': 'iPhone 14 Pro Max',
  'iPhone15,4': 'iPhone 15', 'iPhone15,5': 'iPhone 15 Plus', 'iPhone16,1': 'iPhone 15 Pro',
  'iPhone16,2': 'iPhone 15 Pro Max', 'iPhone17,1': 'iPhone 16 Pro', 'iPhone17,2': 'iPhone 16 Pro Max',
  'iPhone17,3': 'iPhone 16', 'iPhone17,4': 'iPhone 16 Plus', 'iPhone17,5': 'iPhone 16e',
};

// ---------------------------------------------------------------------------------------------------
// The engine: kneejerk's C API (third_party/kneejerk/include/systemone.h) on a worker isolate.
// _Params mirrors systemone_params field for field: change both together.

/// How to load a model. See systemone_params in systemone.h.
class EngineSettings {
  const EngineSettings({
    required this.contextTokens,
    this.gpuLayers = 0,
    this.threads = 0,
    this.repack = false,
    this.verbose = false,
  });

  final int contextTokens; // longest request; kneejerk sizes its batch, and the GPU buffers, to it
  final int gpuLayers; // -1 = all on the GPU (Metal), 0 = CPU only
  final int threads; // 0 = the library's default
  final bool repack; // faster CPU kernels for a second copy of the weights in RAM
  final bool verbose; // llama.cpp's log on stderr

  bool get onGpu => gpuLayers != 0;
}

class EngineException implements Exception {
  EngineException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One loaded model on its own isolate: requests run one at a time and never block the UI.
class DecisionEngine {
  DecisionEngine._(this._isolate, this._port, this.modelType, this.settings);

  final Isolate _isolate;
  final SendPort _port;
  final EngineSettings settings;

  /// The decision family llama.cpp read from the GGUF, e.g. "lfm3_d1"; "none" for a model that is not one.
  final String modelType;
  bool _closed = false;

  static Future<DecisionEngine> load(String modelPath, EngineSettings settings) async {
    final hello = ReceivePort();
    final isolate = await Isolate.spawn(_worker, hello.sendPort, debugName: 'athena-engine');
    final port = await hello.first as SendPort;
    final reply = await _call(port, _Op.load, (modelPath, settings));
    if (reply case (true, final String type)) return DecisionEngine._(isolate, port, type, settings);
    isolate.kill();
    throw EngineException(reply is (bool, String) ? reply.$2 : 'Could not load the model.');
  }

  /// The answer JSON for one /v1/systemone request, or an {"error": ...} JSON.
  Future<String> decide(String requestJson) async {
    if (_closed) throw EngineException('The model is closed.');
    return await _call(_port, _Op.decide, requestJson) as String;
  }

  /// Frees the model (and its GPU memory) before the isolate goes.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _call(_port, _Op.free, null);
    _isolate.kill();
  }

  static Future<Object?> _call(SendPort port, _Op op, Object? arg) async {
    final reply = ReceivePort();
    port.send((op, reply.sendPort, arg));
    final result = await reply.first;
    reply.close();
    return result;
  }
}

enum _Op { load, decide, free }

final class _Params extends Struct {
  @Int32()
  external int nGpuLayers;
  @Uint32()
  external int nCtx;
  @Int32()
  external int nThreads;
  @Bool()
  external bool verbose;
  @Bool()
  external bool repack;
  @Bool()
  external bool flashAttn; // fused attention; off only to read attention maps ("layers")
}

final class _Api {
  _Api(DynamicLibrary lib)
      : load = lib.lookupFunction<Pointer<Void> Function(Pointer<Utf8>, Pointer<_Params>),
            Pointer<Void> Function(Pointer<Utf8>, Pointer<_Params>)>('systemone_load'),
        free = lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('systemone_free'),
        decide = lib.lookupFunction<Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
            Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)>('systemone_decide'),
        freeString = lib.lookupFunction<Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>(
            'systemone_free_string'),
        modelType = lib.lookupFunction<Pointer<Utf8> Function(Pointer<Void>), Pointer<Utf8> Function(Pointer<Void>)>(
            'systemone_model_type');

  final Pointer<Void> Function(Pointer<Utf8>, Pointer<_Params>) load;
  final void Function(Pointer<Void>) free;
  final Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>) decide;
  final void Function(Pointer<Utf8>) freeString;
  final Pointer<Utf8> Function(Pointer<Void>) modelType;
}

DynamicLibrary _openEngine() {
  if (Platform.isAndroid) return DynamicLibrary.open('libathena_engine.so');
  if (Platform.isIOS) {
    final framework =
        '${File(Platform.resolvedExecutable).parent.path}/Frameworks/AthenaEngine.framework/AthenaEngine';
    try {
      return DynamicLibrary.open(framework);
    } on ArgumentError {
      return DynamicLibrary.process(); // linked statically some other way
    }
  }
  throw UnsupportedError('Athena runs on iOS and Android');
}

/// The engine isolate: holds the library and the model handle, answers one message at a time.
void _worker(SendPort hello) {
  final inbox = ReceivePort();
  hello.send(inbox.sendPort);
  _Api? api;
  var handle = nullptr.cast<Void>();

  inbox.listen((message) {
    final (op, reply, arg) = message as (_Op, SendPort, Object?);
    switch (op) {
      case _Op.load:
        final (path, s) = arg! as (String, EngineSettings);
        try {
          api ??= _Api(_openEngine());
        } on Object catch (e) {
          reply.send((false, 'The engine library is missing from this build ($e).'));
          return;
        }
        final params = calloc<_Params>();
        final cPath = path.toNativeUtf8();
        params.ref
          ..nGpuLayers = s.gpuLayers
          ..nCtx = s.contextTokens
          ..nThreads = s.threads
          ..verbose = s.verbose
          ..repack = s.repack
          ..flashAttn = true;
        handle = api!.load(cPath, params);
        calloc
          ..free(cPath)
          ..free(params);
        if (handle == nullptr) {
          reply.send((false, 'Could not load the model.'));
        } else {
          reply.send((true, api!.modelType(handle).toDartString()));
        }
      case _Op.decide:
        if (handle == nullptr) {
          reply.send('{"error": {"message": "no model loaded"}}');
          return;
        }
        final request = (arg! as String).toNativeUtf8();
        final out = api!.decide(handle, request);
        calloc.free(request);
        if (out == nullptr) {
          reply.send('{"error": {"message": "out of memory"}}');
        } else {
          reply.send(out.toDartString());
          api!.freeString(out);
        }
      case _Op.free:
        if (handle != nullptr) api!.free(handle);
        handle = nullptr;
        reply.send(null);
        inbox.close();
    }
  });
}
