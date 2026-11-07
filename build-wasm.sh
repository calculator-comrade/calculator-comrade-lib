#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SDK_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/emsdk-version.txt")"
SDK_DIR="$ROOT_DIR/.tools/emsdk"

if [[ ! "$SDK_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid Emscripten SDK version in emsdk-version.txt: $SDK_VERSION" >&2
    exit 1
fi

# The SDK is project-local: it does not replace the user's globally active SDK.
if [[ ! -f "$SDK_DIR/emsdk" ]]; then
    mkdir -p "$(dirname "$SDK_DIR")"
    git clone --depth 1 https://github.com/emscripten-core/emsdk.git "$SDK_DIR"
fi

# Prepare the pinned SDK once per version, not on every build.
SDK_SETUP_STAMP="$SDK_DIR/.calculator-emsdk-version"
if [[ "$(cat "$SDK_SETUP_STAMP" 2>/dev/null || true)" != "$SDK_VERSION" || \
      ! -f "$SDK_DIR/.emscripten" || ! -x "$SDK_DIR/upstream/emscripten/emcc" ]]; then
    echo "Preparing project-local Emscripten SDK $SDK_VERSION"
    "$SDK_DIR/emsdk" install "$SDK_VERSION"
    "$SDK_DIR/emsdk" activate --embedded "$SDK_VERSION"
    printf '%s\n' "$SDK_VERSION" > "$SDK_SETUP_STAMP"
fi

# Activate only within this script's process.
source "$SDK_DIR/emsdk_env.sh" > /dev/null
export EMSDK="$SDK_DIR"
export EM_CONFIG="$SDK_DIR/.emscripten"

EMCC_VERSION="$(emcc --version | sed -n '1p')"
if [[ "$EMCC_VERSION" != *" $SDK_VERSION "* ]]; then
    echo "Unexpected Emscripten compiler: $EMCC_VERSION (expected $SDK_VERSION)" >&2
    exit 1
fi
echo "$EMCC_VERSION"

cd "$ROOT_DIR"
for BUILD_TYPE in debug release; do
    BUILD_DIR="$ROOT_DIR/build/wasm-${BUILD_TYPE}"
    BUILD_STAMP="$BUILD_DIR/.calculator-emsdk-version"

    # An existing CMake cache may point to another SDK (for example, 5.0.7).
    # Reconfigure from scratch only when the pinned SDK has changed or is unknown.
    if [[ -f "$BUILD_DIR/CMakeCache.txt" ]] && \
       [[ "$(cat "$BUILD_STAMP" 2>/dev/null || true)" != "$SDK_VERSION" ]]; then
        echo "Removing stale WASM build directory: $BUILD_DIR"
        rm -rf -- "$BUILD_DIR"
    fi

    echo -e "\n========= Target: WebAssembly, BuildType: ${BUILD_TYPE} (Emscripten ${SDK_VERSION}) =========\n"
    cmake --preset "wasm-${BUILD_TYPE}"
    printf '%s\n' "$SDK_VERSION" > "$BUILD_STAMP"
    cmake --build --preset "wasm-${BUILD_TYPE}"
done
