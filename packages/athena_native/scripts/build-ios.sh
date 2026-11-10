#!/usr/bin/env bash
# Builds ios/athena_native/AthenaEngine.xcframework: kneejerk (libsystemone on llama.cpp, Metal shaders
# embedded, Accelerate) as a dynamic framework for iPhone, arm64, iOS 16.4+. It exports only systemone_*.
#
#   scripts/build-ios.sh                         builds kneejerk from KNEEJERK_DIR (default: the submodule)
#   KNEEJERK_LIB=libkneejerk.a scripts/build-ios.sh   links an already merged static library instead
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
kneejerk="${KNEEJERK_DIR:-$here/../../third_party/kneejerk}"
build="$here/build/ios"
out="$here/ios/athena_native/AthenaEngine.xcframework"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
min_ios=16.4
mkdir -p "$build"

lib="${KNEEJERK_LIB:-}"
if [ -z "$lib" ]; then
    [ -f "$kneejerk/llama.cpp/CMakeLists.txt" ] || { echo "no kneejerk at $kneejerk: git submodule update --init --recursive" >&2; exit 1; }
    # armv8.2-a+dotprod+fp16 is the A13 (iPhone 11) and newer; the app refuses older iPhones
    cmake -S "$kneejerk" -B "$build/cmake" \
        -DSYSTEMONE_BUILD_CLI=OFF -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=$min_ios \
        -DGGML_NATIVE=OFF -DGGML_CPU_ARM_ARCH=armv8.2-a+dotprod+fp16 \
        -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_OPENMP=OFF
    cmake --build "$build/cmake" --target systemone -j "$(sysctl -n hw.ncpu)"
    lib="$build/libkneejerk.a"
    # shellcheck disable=SC2046
    libtool -static -no_warning_for_no_symbols -o "$lib" $(find "$build/cmake" -name '*.a')
fi

# -u pulls in the API and what it needs; dead stripping drops the rest of llama.cpp
fw="$build/AthenaEngine.framework"
rm -rf "$fw" "$out" && mkdir -p "$fw"
xcrun -sdk iphoneos clang++ -target "arm64-apple-ios$min_ios" -dynamiclib \
    -Wl,-u,_systemone_load -Wl,-u,_systemone_free -Wl,-u,_systemone_decide \
    -Wl,-u,_systemone_free_string -Wl,-u,_systemone_model_type \
    "$lib" -framework Foundation -framework Metal -framework MetalKit -framework Accelerate \
    -Wl,-exported_symbol,'_systemone_*' -Wl,-dead_strip \
    -install_name @rpath/AthenaEngine.framework/AthenaEngine -o "$fw/AthenaEngine"
xcrun strip -x "$fw/AthenaEngine"

cat > "$fw/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>AthenaEngine</string>
    <key>CFBundleIdentifier</key><string>dev.ehollbach.athena.engine</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>AthenaEngine</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
    <key>MinimumOSVersion</key><string>$min_ios</string>
</dict>
</plist>
EOF

xcodebuild -create-xcframework -framework "$fw" -output "$out" >/dev/null
echo "built $out ($(du -sh "$out" | cut -f1))"
xcrun nm -gU "$fw/AthenaEngine" | grep -c ' _systemone_' | xargs echo "exported systemone functions:"
