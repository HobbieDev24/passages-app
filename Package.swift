// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Passages",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Passages", targets: ["PassagesApp"])
    ],
    targets: [
        .target(
            name: "PassagesCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "PassagesApp",
            dependencies: ["PassagesCore"]
        )
    ]
)
