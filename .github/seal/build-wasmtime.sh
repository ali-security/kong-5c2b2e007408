#!/bin/bash
# Build the Wasmtime 23.0.2 C API from source with the patches in build/openresty/wasmx/wasmtime/patches,
# laid out like upstream's wasmtime-v23.0.2-x86_64-linux-c-api release (include/, lib/libwasmtime.a), plus
# the WORKSPACE/BUILD.bazel Bazel needs for --override_repository=wasmtime-linux-x86_64=<out-dir>.
# Release-build settings follow wasmtime's ci/build-release-artifacts.sh at v23.0.2.
# usage: build-wasmtime.sh <kong-checkout> <out-dir>      (needs rustc 1.79.0, cmake, git, curl, patch)
set -euo pipefail
ROOT=$(realpath "$1"); OUT=$(realpath -m "$2"); P=$ROOT/build/openresty/wasmx/wasmtime/patches
SRC=$(mktemp -d)/wasmtime
git clone -q --depth 1 --branch v23.0.2 https://github.com/bytecodealliance/wasmtime "$SRC"
cd "$SRC"
test "$(git rev-parse HEAD)" = 694ee661e6f2ef89841487c7ba9aa6e64c9078df
for p in "$P"/wasmtime-23.0.2_*.patch; do patch -p1 -s -F0 < "$p"; done

# cap-primitives 3.0.0 exactly as Cargo.lock pins it, plus its security patch
mkdir -p vendor
curl -fsSL -o vendor/cap-primitives-3.0.0.crate https://static.crates.io/crates/cap-primitives/cap-primitives-3.0.0.crate
echo "90a0b44fc796b1a84535a63753d50ba3972c4db55c7255c186f79140e63d56d0  vendor/cap-primitives-3.0.0.crate" | sha256sum -c --quiet
tar xzf vendor/cap-primitives-3.0.0.crate -C vendor
mv vendor/cap-primitives-3.0.0 vendor/cap-primitives
(cd vendor/cap-primitives && for p in "$P"/cap-primitives-3.0.0_*.patch; do patch -p1 -s -F0 < "$p"; done)

export CARGO_PROFILE_RELEASE_STRIP=debuginfo CARGO_PROFILE_RELEASE_PANIC=abort
cmake -S crates/c-api -B target/c-api-build -DCMAKE_BUILD_TYPE=Release \
  -DWASMTIME_TARGET=x86_64-unknown-linux-gnu -DCMAKE_INSTALL_PREFIX="$OUT" -DCMAKE_INSTALL_LIBDIR="$OUT/lib"
cmake --build target/c-api-build --target install -j"$(nproc)"

cat > "$OUT/WORKSPACE" <<'WS'
workspace(name = "wasmtime-linux-x86_64")
WS
cat > "$OUT/BUILD.bazel" <<'BZ'
filegroup(
    name = "all_srcs",
    # note: we do static link only for runtimes
    srcs = glob(["include/**", "lib/*.a"]),
    visibility = ["//visibility:public"]
)

filegroup(
    name = "lib",
    srcs = glob(["**/*.so", "**/*.dylib"]),
    visibility = ["//visibility:public"]
)
BZ
ls -la "$OUT" "$OUT/lib"
