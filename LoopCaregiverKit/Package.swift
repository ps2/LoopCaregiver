// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LoopCaregiverKit",
    platforms: [.iOS(.v17), .watchOS(.v10)],
    products: [
        .library(
            name: "LoopCaregiverKit",
            targets: ["LoopCaregiverKit", "LoopCaregiverKitUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/ps2/LoopKit.git", branch: "loopcare"),
        // .package(path: "../../LoopKit"),
        .package(url: "https://github.com/LoopKit/LoopAlgorithm.git", branch: "main"),
        .package(url: "https://github.com/ps2/NightscoutKit.git", branch: "loopcare"),
        .package(url: "https://github.com/mattrubin/OneTimePassword.git", branch: "develop")
    ],
    targets: [
        .target(
            name: "LoopCaregiverKit",
            dependencies: [
                "LoopKit",
                "LoopAlgorithm",
                "NightscoutKit",
                "OneTimePassword"
            ]
        ),
        .target(
            name: "LoopCaregiverKitUI",
            dependencies: [
                "LoopCaregiverKit",
                "LoopKit",
                "LoopAlgorithm"
            ]
        ),
        .testTarget(
            name: "LoopCaregiverKitTests",
            dependencies: ["LoopCaregiverKit"])
    ]
)
