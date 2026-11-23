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
        .target(name: "CosmNotesUpdates"),
        .executableTarget(
            name: "cosmNotes",
            dependencies: ["StickyNotesGeometry", "CosmNotesWork", "CosmNotesUpdates"],
            path: "Sources/StickyNotes"
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
        ),
        .executableTarget(
            name: "CosmNotesUpdateChecks",
            dependencies: ["CosmNotesUpdates"],
            path: "Tests/CosmNotesUpdateChecks"
        )
    ]
)
