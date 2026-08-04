#!/usr/bin/env bash
#
# Vendors libsignal for GojoMessages E2EE.
#
# libsignal cannot be added as a normal SPM dependency: its Swift package links
# the Rust core with `unsafeFlags`, and SwiftPM forbids those in *remote*
# packages. Signal-iOS gets around this by vendoring locally, and so do we.
#
# The Rust core does not need building — Signal publishes the same prebuilt
# `libsignal_ffi.a` their CocoaPods spec downloads. This script pairs that
# binary with the matching Swift sources and wraps the result in an
# XCFramework, which sidesteps `unsafeFlags` entirely: a binaryTarget carries
# its own linker metadata and picks the right slice per destination, so no
# `-L` flag is needed anywhere.
#
# Output (all gitignored — the slices total ~560 MB):
#   Vendor/libsignal/LibSignalFFI.xcframework
#   Vendor/libsignal/Sources/LibSignalClient/**
#
# Run before `xcodebuild -resolvePackageDependencies`, locally and in CI.
set -euo pipefail

# The binary and the Swift sources MUST be the same version: this is a C ABI
# across the FFI boundary, and a mismatch fails at runtime, not at link time.
VERSION="${LIBSIGNAL_VERSION:-0.99.3}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$REPO_ROOT/Vendor/LibSignalClient"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [[ -d "$VENDOR/LibSignalFFI.xcframework" && "${FORCE:-0}" != "1" ]]; then
    echo "libsignal $VERSION already vendored — FORCE=1 to refetch."
    exit 0
fi

echo "==> Fetching prebuilt libsignal_ffi v$VERSION (~151 MB)"
curl -fsSL -o "$WORK/ffi.tar.gz" \
    "https://build-artifacts.signal.org/libraries/libsignal-client-ios-build-v${VERSION}.tar.gz"
mkdir -p "$WORK/ffi" && tar -xzf "$WORK/ffi.tar.gz" -C "$WORK/ffi"

echo "==> Fetching libsignal Swift sources v$VERSION"
curl -fsSL -o "$WORK/src.tar.gz" \
    "https://codeload.github.com/signalapp/libsignal/tar.gz/refs/tags/v${VERSION}"
mkdir -p "$WORK/src" && tar -xzf "$WORK/src.tar.gz" -C "$WORK/src" --strip-components=1

# Locate rather than hardcode: the archive's directory layout is Signal's build
# tree, and it is not part of any contract they publish.
device="$(find "$WORK/ffi" -path "*aarch64-apple-ios/release/libsignal_ffi.a" | head -1)"
sim_arm="$(find "$WORK/ffi" -path "*aarch64-apple-ios-sim/release/libsignal_ffi.a" | head -1)"
sim_x86="$(find "$WORK/ffi" -path "*x86_64-apple-ios/release/libsignal_ffi.a" | head -1)"
headers="$(dirname "$(find "$WORK/src/swift" -name "signal_ffi.h" | head -1)")"

for required in "$device" "$sim_arm" "$sim_x86" "$headers"; do
    [[ -n "$required" ]] || { echo "!! layout changed upstream — inspect $WORK" >&2; exit 1; }
done

# An XCFramework holds one library per platform *variant*, so the two simulator
# architectures have to be fattened into a single slice first.
echo "==> Merging simulator slices"
lipo -create "$sim_arm" "$sim_x86" -output "$WORK/libsignal_ffi_sim.a"

echo "==> Building LibSignalFFI.xcframework"
rm -rf "$VENDOR/LibSignalFFI.xcframework"
mkdir -p "$VENDOR"
xcodebuild -create-xcframework \
    -library "$device" -headers "$headers" \
    -library "$WORK/libsignal_ffi_sim.a" -headers "$headers" \
    -output "$VENDOR/LibSignalFFI.xcframework"

echo "==> Copying Swift sources"
rm -rf "$VENDOR/Sources"
mkdir -p "$VENDOR/Sources"
cp -R "$WORK/src/swift/Sources/LibSignalClient" "$VENDOR/Sources/LibSignalClient"

echo "==> Vendored libsignal $VERSION into Vendor/libsignal"
