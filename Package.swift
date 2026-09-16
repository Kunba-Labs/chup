// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Chup", platforms: [.macOS(.v15)],
    products: [.library(name: "ChupCore", targets: ["ChupCore"]),
        .library(name: "CAudioSafety", targets: ["CAudioSafety"])],
    targets: [
        .target(name: "CAudioSafety", publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("AVFoundation"), .linkedFramework("AudioToolbox")]),
        .target(name: "CSQLite", publicHeadersPath: "include", cSettings: [
            .define("NDEBUG"), .define("SQLITE_HAS_CODEC"), .define("SQLCIPHER_CRYPTO_CC"),
            .define("SQLITE_EXTRA_INIT", to: "sqlcipher_extra_init"),
            .define("SQLITE_EXTRA_SHUTDOWN", to: "sqlcipher_extra_shutdown"),
            .define("SQLITE_TEMP_STORE", to: "3"), .define("SQLITE_THREADSAFE", to: "1"),
            .define("SQLITE_ENABLE_FTS5"), .define("SQLITE_DEFAULT_MEMSTATUS", to: "0")
        ], linkerSettings: [.linkedFramework("Security")]),
        .target(name: "ChupCore", dependencies: ["CSQLite"]),
        .testTarget(name: "ChupCoreTests", dependencies: ["ChupCore"])
    ], swiftLanguageModes: [.v5]
)
