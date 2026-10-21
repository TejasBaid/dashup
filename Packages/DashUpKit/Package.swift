// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DashUpKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "DashUpKit", targets: ["DashUpKit"]),
        .executable(name: "dashup-cli", targets: ["dashup-cli"]),
    ],
    targets: [
        .target(name: "DashUpKit"),
        .executableTarget(name: "dashup-cli", dependencies: ["DashUpKit"]),
        .testTarget(name: "DashUpKitTests", dependencies: ["DashUpKit"]),
    ]
)
