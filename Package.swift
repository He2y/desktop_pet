// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DesktopPet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DesktopPet", targets: ["DesktopPet"])
    ],
    targets: [
        .executableTarget(
            name: "DesktopPet",
            path: "Sources/DesktopPet",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
