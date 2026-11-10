# Athena

Paste a message, tap a question (is it urgent? a scam? does it need a reply?), get a big YES or NO
and how sure it is. A decision model answers on the phone itself; Athena goes online once, to
download that model from Hugging Face. iPhone and Android, one Flutter app.

## Which model a phone gets

Athena reads the phone's memory and picks the biggest model that leaves the phone room:

| memory | model | download |
|---|---|---|
| 8 GB+ | H2O Lightning 4B, IQ3_XXS | 1.9 GB |
| 6 GB | Liquid d1 2B, Q4_K_M | 1.1 GB |
| 4 GB | Kev 0.8B, Q8_0 (or vLLM d3 Edge) | 0.8 GB |
| 3 GB | Laya, Q8_0 | 0.45 GB |

Each file is pinned to a Hugging Face commit and checked against its SHA-256 before it is used
(`lib/catalog.dart`). Downloads resume where they stopped. Settings lists the other models that fit.
On iPhone the model runs on the GPU (Metal), on Android on four CPU cores.

Athena needs an iPhone 11 or newer (iOS 16.4+), or an Android 9+ phone with a 64-bit ARMv8.2 CPU
(Cortex-A55/A75 or newer).

## Build

The engine is [kneejerk](https://github.com/moudrkat/kneejerk) (libsystemone on llama.cpp), a
submodule at `third_party/kneejerk`: the `main` branch of
[ehollbach/kneejerk](https://github.com/ehollbach/kneejerk), with llama.cpp b12207 inside it.

```bash
git clone --recurse-submodules --shallow-submodules https://github.com/ehollbach/Athena.git
# or, in an existing clone: git submodule update --init --recursive --depth 1

# iPhone: the engine as AthenaEngine.xcframework (once), then an unsigned build/Athena.ipa
packages/athena_native/scripts/build-ios.sh
scripts/build-ipa.sh            # install it with Impactor, or sign it with your team

# Android: Gradle builds the engine with the NDK (28.2) as libathena_engine.so
flutter build apk --release --target-platform android-arm64
```

## Test

```bash
flutter test                         # catalog, requests and answers, downloader (resume, redirects, bad hash)
scripts/device.sh autotest           # on a USB iPhone: download, load, 8 questions, timings, memory
scripts/device.sh autotest --model vllm-d3-edge
```

## Layout

- `lib/`: the app. `catalog.dart` models and tiers, `downloader.dart`, `decision.dart` requests
  and verdicts, `controller.dart` state, `ui/` three screens, `autotest.dart`.
- `packages/athena_native/`: the plugin. Dart FFI to kneejerk's C API on a worker isolate, and a
  method channel for the phone's memory, name and free space. iOS: Swift and the xcframework
  (Swift Package Manager); Android: Kotlin and `src/CMakeLists.txt`.

## License

Athena is free software under the GNU General Public License, version 3 or later: see `LICENSE`.

kneejerk and llama.cpp keep their own (MIT) licenses, in the submodule; the app shows them on its
licenses page. The models come from Hugging Face under their own licenses: Apache 2.0, except
Liquid d1 2B (LFM Open License v1.0).
