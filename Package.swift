// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacPowerToys",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MacPowerToys", targets: ["MacPowerToys"])],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "3.1.0")
    ],
    targets: [
        .executableTarget(name: "MacPowerToys", dependencies: ["KeyboardShortcuts"]),
        .testTarget(name: "MacPowerToysTests", dependencies: ["MacPowerToys"])
    ]
)
