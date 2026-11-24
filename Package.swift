// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "cosmNotes",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "StickyNotesGeometry",
            path: "Sources/StickyNotesGeometry"
        ),
        .target(name: "CosmNotesWork"),
        .binaryTarget(
            name: "Sparkle",
            url: "https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-for-Swift-Package-Manager.zip",
            checksum: "4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a"
        ),
        .executableTarget(
            name: "cosmNotes",
            dependencies: ["StickyNotesGeometry", "CosmNotesWork", "Sparkle"],
            path: "Sources/StickyNotes",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .executableTarget(
            name: "StickyNotesGeometryChecks",
            dependencies: ["StickyNotesGeometry"],
            path: "Tests/StickyNotesGeometryChecks"
        ),
        .executableTarget(
            name: "CosmNotesWorkChecks",
            dependencies: ["CosmNotesWork"],
            path: "Tests/CosmNotesWorkChecks"
        )
    ]
)
