// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HostsManager",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "HostsManager", targets: ["HostsManagerApp"]),
        .executable(name: "HostsManagerHelper", targets: ["HostsManagerHelper"])
    ],
    dependencies: [],
    targets: [
        // MARK: - Shared Module (Models, XPC Protocol, Errors)
        .target(
            name: "Shared",
            path: "Sources/Shared"
        ),

        // MARK: - Menu Bar App
        .executableTarget(
            name: "HostsManagerApp",
            dependencies: ["Shared"],
            path: "Sources/HostsManagerApp",
            exclude: ["Info.plist"],
            resources: [.process("Resources")]
        ),

        // MARK: - Privileged Helper (root LaunchDaemon)
        .executableTarget(
            name: "HostsManagerHelper",
            dependencies: ["Shared"],
            path: "Sources/HostsManagerHelper",
            exclude: ["Info.plist"]
        )
    ]
)
