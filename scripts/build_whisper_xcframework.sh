#!/bin/bash
# 构建 whisper.xcframework（精简版：macOS arm64 + iOS 模拟器 arm64）
# 基于官方 build-xcframework.sh 思路：Metal 内嵌 shader + Accelerate，静态库合并
# 依赖：cmake、Xcode；源码走 codeload 快速通道
# 用法：bash scripts/build_whisper_xcframework.sh
# 产出：Packages/WhisperCpp/whisper.xcframework
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="v1.9.5"
SRC=".cache/whisper-src"
OUT="Packages/WhisperCpp/whisper.xcframework"
mkdir -p .cache Packages/WhisperCpp

# 1. 源码
if [ ! -d "$SRC" ]; then
  echo "下载 whisper.cpp $TAG …"
  curl -sL --retry 3 "https://codeload.github.com/ggml-org/whisper.cpp/tar.gz/refs/tags/$TAG" -o .cache/whisper.tar.gz
  mkdir -p "$SRC"
  tar -xzf .cache/whisper.tar.gz -C "$SRC" --strip-components=1
  rm -f .cache/whisper.tar.gz
fi

COMMON_ARGS=(
  -G Xcode
  -DBUILD_SHARED_LIBS=OFF
  -DWHISPER_BUILD_EXAMPLES=OFF
  -DWHISPER_BUILD_TESTS=OFF
  -DWHISPER_BUILD_SERVER=OFF
  -DWHISPER_COREML=OFF
  -DGGML_METAL=ON
  -DGGML_METAL_EMBED_LIBRARY=ON
  -DGGML_BLAS=ON
  -DGGML_BLAS_DEFAULT=ON
  -DGGML_OPENMP=OFF
  -DGGML_NATIVE=OFF
  -DCMAKE_OSX_ARCHITECTURES=arm64
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY=""
)

# 2. macOS arm64
if [ ! -f .cache/combined-macos.a ]; then
  echo "=== 构建 macOS arm64 ==="
  cmake -B .cache/build-macos "${COMMON_ARGS[@]}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 -S "$SRC"
  cmake --build .cache/build-macos --config Release -- -quiet
  find .cache/build-macos -name "*.a" -path "*Release*" -print0 | xargs -0 libtool -static -o .cache/combined-macos.a 2>/dev/null
fi

# 3. iOS 模拟器 arm64 + x86_64
if [ ! -f .cache/combined-iphonesimulator.a ]; then
  echo "=== 构建 iOS Simulator (arm64+x86_64) ==="
  cmake -B .cache/build-iossim "${COMMON_ARGS[@]}" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphonesimulator \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -S "$SRC"
  cmake --build .cache/build-iossim --config Release -- -quiet
  find .cache/build-iossim -name "*.a" -path "*Release*" -print0 | xargs -0 libtool -static -o .cache/combined-iphonesimulator.a 2>/dev/null
fi

# 3b. iOS 真机 arm64
if [ ! -f .cache/combined-iphoneos.a ]; then
  echo "=== 构建 iOS Device (arm64) ==="
  cmake -B .cache/build-iosdev "${COMMON_ARGS[@]}" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -S "$SRC"
  cmake --build .cache/build-iosdev --config Release -- -quiet
  find .cache/build-iosdev -name "*.a" -path "*Release*" -print0 | xargs -0 libtool -static -o .cache/combined-iphoneos.a 2>/dev/null
fi

# 4. 头文件 + modulemap
HEADERS=".cache/whisper-headers"
rm -rf "$HEADERS"; mkdir -p "$HEADERS"
cp "$SRC/include/whisper.h" "$HEADERS/"
for h in ggml.h ggml-alloc.h ggml-backend.h ggml-metal.h ggml-cpu.h ggml-blas.h gguf.h; do
  cp "$SRC/ggml/include/$h" "$HEADERS/" 2>/dev/null || true
done
cat > "$HEADERS/module.modulemap" <<'EOF'
module CWhisper {
    header "whisper.h"
    header "ggml.h"
    header "ggml-alloc.h"
    header "ggml-backend.h"
    header "ggml-metal.h"
    header "ggml-cpu.h"
    header "ggml-blas.h"
    header "gguf.h"
    link "c++"
    link framework "Accelerate"
    link framework "Metal"
    link framework "Foundation"
    export *
}
EOF

# 5. xcframework
rm -rf "$OUT"
xcodebuild -create-xcframework \
  -library .cache/combined-macos.a -headers "$HEADERS" \
  -library .cache/combined-iphonesimulator.a -headers "$HEADERS" \
  -library .cache/combined-iphoneos.a -headers "$HEADERS" \
  -output "$OUT"

echo "✅ $OUT"
ls -la "$OUT"
