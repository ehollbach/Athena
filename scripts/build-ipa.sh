#!/usr/bin/env bash
# Builds Athena for iPhone, unsigned, as build/Athena.ipa: Impactor (or any re-signer) signs and installs it.
# Needs packages/athena_native/ios/athena_native/AthenaEngine.xcframework: run packages/athena_native/scripts/build-ios.sh once.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d packages/athena_native/ios/athena_native/AthenaEngine.xcframework ] ||
    { echo "no AthenaEngine.xcframework: run packages/athena_native/scripts/build-ios.sh first" >&2; exit 1; }
flutter build ios --release --no-codesign
rm -rf build/ipa build/Athena.ipa && mkdir -p build/ipa/Payload
cp -R build/ios/iphoneos/Runner.app build/ipa/Payload/
(cd build/ipa && zip -qry ../Athena.ipa Payload)
rm -rf build/ipa
echo "built $(pwd)/build/Athena.ipa ($(du -h build/Athena.ipa | cut -f1))"
