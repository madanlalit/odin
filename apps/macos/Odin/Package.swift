// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Odin",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "Odin", targets: ["Odin"])
    ],
    targets: [
        .executableTarget(
            name: "Odin",
            path: "Sources/Odin",
            resources: [
                .process("Assets.xcassets"),
                .process("OdinLogo.png"),
            ],
            linkerSettings: [
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
            ]
        )
    ]
)
