// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MultiGuard",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MultiGuard", targets: ["MultiGuard"]),
        .executable(name: "MultiGuardHelper", targets: ["MultiGuardHelper"])
    ],
    targets: [
        .executableTarget(name: "MultiGuard"),
        .executableTarget(
            name: "MultiGuardHelper",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/MultiGuardHelper/Info.plist"
                ])
            ]
        )
    ]
)
