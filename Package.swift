// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "InputSourceLock",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "BoardLock", targets: ["InputSourceLockApp"]),
        .library(name: "InputSourceLockCore", targets: ["InputSourceLockCore"]),
        .executable(name: "InputSourceLockTests", targets: ["InputSourceLockTests"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "InputSourceLockCore",
            dependencies: []
        ),
        .executableTarget(
            name: "InputSourceLockApp",
            dependencies: ["InputSourceLockCore"]
        ),
        .executableTarget(
            name: "InputSourceLockTests",
            dependencies: ["InputSourceLockCore"],
            path: "Tests/InputSourceLockTests"
        )
    ]
)
