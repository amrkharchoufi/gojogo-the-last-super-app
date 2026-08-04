// swift-tools-version:6.0

// Local SwiftPM wrapper for Signal's libsignal (see E2EE-PLAN.md, Phase B).
//
// This manifest is tracked; everything beside it — Sources/ and lib/ — is
// fetched by scripts/fetch-libsignal.sh and gitignored (~560 MB of prebuilt
// Rust). Run the script before resolving packages, locally and in CI.
//
// Mirrors upstream's swift/Package.swift (v0.99.3) minus the docc plugin and
// the test target — the test target is where upstream's `unsafeFlags` lives,
// which is the one thing SwiftPM would reject. The library target needs no
// linker flags at all: SignalFfi's module map says `link "signal_ffi"`, so the
// linker gets -lsignal_ffi from the module and the app target only supplies
// the sdk-conditional LIBRARY_SEARCH_PATHS that picks the device or simulator
// slice from lib/.
//
// Tools 6.0 and StrictConcurrency match upstream exactly: the sources are
// written against them, and the FFI is a C ABI where source and binary must
// stay the same version.

import PackageDescription

let package = Package(
    name: "LibSignalClient",
    platforms: [
        .macOS(.v10_15), .iOS(.v13),
    ],
    products: [
        .library(
            name: "LibSignalClient",
            targets: ["LibSignalClient"]
        )
    ],
    targets: [
        .systemLibrary(name: "SignalFfi"),
        .target(
            name: "LibSignalClient",
            dependencies: ["SignalFfi"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
