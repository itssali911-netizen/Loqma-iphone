// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "LuqmaCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "LuqmaCore", targets: ["LuqmaCore"])],
    targets: [
        .target(name: "LuqmaCore", path: "Luqma/Core"),
        .testTarget(name: "LuqmaCoreTests", dependencies: ["LuqmaCore"], path: "Tests", resources: [.copy("niddk-weight-golden.json"), .copy("foods-data.json"), .copy("photo-foods.json")])
    ],
    swiftLanguageVersions: [.v5]
)
