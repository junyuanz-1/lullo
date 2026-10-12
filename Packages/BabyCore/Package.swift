// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BabyCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BabyCore", targets: ["BabyCore"]),
    ],
    targets: [
        .target(name: "BabyCore"),
        .testTarget(name: "BabyCoreTests", dependencies: ["BabyCore"]),
    ]
)
