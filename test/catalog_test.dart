import 'package:athena/catalog.dart';
import 'package:athena_native/athena_native.dart';
import 'package:flutter_test/flutter_test.dart';

int gib(double g) => (g * 1024 * 1024 * 1024).round();

void main() {
  test('each phone class gets the biggest model that leaves it room', () {
    expect(recommendedModel(gib(1.9)), isNull); // 2 GB
    expect(recommendedModel(gib(2.8))?.id, 'laya'); // 3 GB Android
    expect(recommendedModel(gib(3.7))?.id, 'kev-0.8b'); // 4 GB: iPhone 13, not the 4B
    expect(recommendedModel(gib(5.5))?.id, 'd1-2b'); // 6 GB
    expect(recommendedModel(gib(7.4))?.id, 'h2o-lightning-4b'); // 8 GB
    expect(recommendedModel(gib(11.2))?.id, 'h2o-lightning-4b'); // 12 GB
  });

  test('a 4 GB phone is offered the two small models and Laya, nothing bigger', () {
    expect(modelsThatFit(gib(3.7)).map((m) => m.id), ['kev-0.8b', 'vllm-d3-edge', 'laya']);
  });

  test('memory is shown as the size on the box', () {
    expect(marketingRam(gib(3.66)), '4 GB');
    expect(marketingRam(gib(4.0)), '4 GB');
    expect(marketingRam(gib(5.5)), '6 GB');
    expect(marketingRam(gib(7.4)), '8 GB');
  });

  test('catalog entries are pinned: a commit, a SHA-256, a size', () {
    for (final m in catalog) {
      expect(m.revision, matches(RegExp(r'^[0-9a-f]{40}$')), reason: m.id);
      expect(m.sha256, matches(RegExp(r'^[0-9a-f]{64}$')), reason: m.id);
      expect(m.bytes, greaterThan(100 * 1000 * 1000), reason: m.id);
      expect(m.url, 'https://huggingface.co/${m.repo}/resolve/${m.revision}/${m.file}');
      expect(m.maxTextChars, greaterThan(1000), reason: m.id);
    }
    expect(catalog.map((m) => m.id).toSet(), hasLength(catalog.length));
  });

  test('iPhone 11 (A13) and newer run the engine, older ones do not', () {
    expect(appleChipSupported('iPhone11,8'), isFalse); // XR, A12
    expect(appleChipSupported('iPhone12,1'), isTrue); // 11
    expect(appleChipSupported('iPhone14,5'), isTrue); // 13
    expect(appleDeviceName('iPhone14,5'), 'iPhone 13');
    expect(appleDeviceName('iPhone99,1'), 'iPhone99,1');
  });
}
