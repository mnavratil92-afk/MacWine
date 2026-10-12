// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "MacWine",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MacWine", targets: ["MacWine"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")],
    targets: [
        .target(name: "MacWineCore"),
        .executableTarget(name: "MacWine", dependencies: ["MacWineCore", .product(name: "Sparkle", package: "Sparkle")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "MacWineCoreTests", dependencies: ["MacWineCore"])
    ]
)
