// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "RoamVibing",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "LidAwakeCore", targets: ["LidAwakeCore"]),
        .library(name: "PrivilegedHelperProtocol", targets: ["PrivilegedHelperProtocol"]),
        .library(name: "PrivilegedHelperCore", targets: ["PrivilegedHelperCore"]),
        .executable(name: "RoamVibing", targets: ["RoamVibing"]),
        .executable(name: "RoamVibingPrivilegedHelper", targets: ["RoamVibingPrivilegedHelper"])
    ],
    targets: [
        .target(name: "PrivilegedHelperProtocol"),
        .target(
            name: "LidAwakeCore",
            dependencies: ["PrivilegedHelperProtocol"]
        ),
        .target(
            name: "PrivilegedHelperCore",
            dependencies: ["PrivilegedHelperProtocol"]
        ),
        .executableTarget(
            name: "RoamVibing",
            dependencies: ["LidAwakeCore"],
            path: "Sources/LidAwake",
            linkerSettings: [
                .linkedFramework("CoreAudio")
            ]
        ),
        .executableTarget(
            name: "RoamVibingPrivilegedHelper",
            dependencies: ["PrivilegedHelperCore", "PrivilegedHelperProtocol"]
        ),
        .testTarget(
            name: "LidAwakeCoreTests",
            dependencies: ["LidAwakeCore", "PrivilegedHelperProtocol", "PrivilegedHelperCore"]
        )
    ]
)
