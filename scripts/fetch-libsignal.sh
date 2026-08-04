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

# NOTE on packaging: an XCFramework does NOT work here and was tried — the
# prebuilt archives are *mixed* (Mach-O plus Rust LTO bitcode members), and
# `xcodebuild -create-xcframework` dies on the bitcode magic (0xb17c0de) even
# though the archive links fine. So the slices are laid out per destination
# and the app target selects one via sdk-conditional LIBRARY_SEARCH_PATHS,
# exactly as Signal's own podspec does. Device and simulator arm64 must never
# be lipo'd together — same architecture, different platform.
#
# The binary and the Swift sources MUST be the same version: this is a C ABI
# across the FFI boundary, and a mismatch fails at runtime, not at link time.
VERSION="${LIBSIGNAL_VERSION:-0.99.3}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$REPO_ROOT/Vendor/LibSignalClient"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [[ -f "$VENDOR/lib/device/libsignal_ffi.a" && "${FORCE:-0}" != "1" ]]; then
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

for required in "$device" "$sim_arm" "$sim_x86"; do
    [[ -n "$required" ]] || { echo "!! layout changed upstream — inspect $WORK" >&2; exit 1; }
done
[[ -d "$WORK/src/swift/Sources/LibSignalClient" && -d "$WORK/src/swift/Sources/SignalFfi" ]] \
    || { echo "!! Swift source layout changed upstream — inspect $WORK/src" >&2; exit 1; }

echo "==> Laying out slices per destination"
mkdir -p "$VENDOR/lib/device" "$VENDOR/lib/simulator"
cp "$device" "$VENDOR/lib/device/libsignal_ffi.a"
# The two *simulator* architectures do get fattened — they're distinct archs on
# the same platform, which is exactly what a fat archive is for.
lipo -create "$sim_arm" "$sim_x86" -output "$VENDOR/lib/simulator/libsignal_ffi.a"

echo "==> Copying Swift sources + FFI module"
rm -rf "$VENDOR/Sources"
mkdir -p "$VENDOR/Sources"
cp -R "$WORK/src/swift/Sources/LibSignalClient" "$VENDOR/Sources/LibSignalClient"
cp -R "$WORK/src/swift/Sources/SignalFfi" "$VENDOR/Sources/SignalFfi"

echo "==> Vendored libsignal $VERSION into Vendor/LibSignalClient"
