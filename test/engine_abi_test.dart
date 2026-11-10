import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Dart FFI struct _Params (packages/athena_native/lib/athena_native.dart) mirrors systemone_params
/// from the kneejerk submodule. A field added, removed or retyped upstream compiles fine and then passes
/// garbage to the engine on the phone, so a submodule bump that changes the struct fails here first.
void main() {
  test('systemone_params in the submodule is the struct the Dart side mirrors', () {
    final header = File('third_party/kneejerk/include/systemone.h');
    if (!header.existsSync()) {
      markTestSkipped('no submodule: git submodule update --init --recursive');
      return;
    }
    final body = RegExp(r'typedef struct systemone_params \{(.*?)\} systemone_params;', dotAll: true)
        .firstMatch(header.readAsStringSync())!
        .group(1)!;
    final fields = [
      for (final m in RegExp(r'^\s*(\w+)\s+(\w+);', multiLine: true).allMatches(body)) '${m[1]} ${m[2]}',
    ];
    expect(fields, [
      'int32_t n_gpu_layers',
      'uint32_t n_ctx',
      'int32_t n_threads',
      'bool verbose',
      'bool repack',
      'bool flash_attn',
    ]);

    final dart = File('packages/athena_native/lib/athena_native.dart').readAsStringSync();
    final dartFields = [
      for (final m in RegExp(r'@(\w+)\(\)\s+external \w+ (\w+);').allMatches(dart)) '${m[1]} ${m[2]}',
    ];
    expect(dartFields, ['Int32 nGpuLayers', 'Uint32 nCtx', 'Int32 nThreads', 'Bool verbose', 'Bool repack', 'Bool flashAttn']);
  });
}
