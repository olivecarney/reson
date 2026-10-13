// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Reson", platforms: [.macOS(.v14)], products: [.executable(name: "Reson", targets: ["Reson"])], targets: [
    .systemLibrary(name: "CReson", path: "Bridge"),
    .executableTarget(name: "Reson", dependencies: ["CReson"], path: ".", exclude: ["Bridge", "Tests", "Package.swift", "Info.plist"], sources: ["App", "Views"], linkerSettings: [.unsafeFlags(["-L", "../target/release", "-lreson_engine"]), .linkedLibrary("sqlite3"), .linkedFramework("CoreAudio"), .linkedFramework("AudioToolbox"), .linkedFramework("CoreFoundation")]),
    .testTarget(name: "ResonTests", dependencies: ["Reson"], path: "Tests")
])
