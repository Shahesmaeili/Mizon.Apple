// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Mizon.Apple",
    platforms: [.macOS(.v26), .iOS(.v26), .watchOS(.v26)],
    products: [
        .library(name: "MizonAppleCore", targets: ["MizonAppleCore"]),
        .library(name: "MizonAppleUI", targets: ["MizonAppleUI"]),
        .executable(name: "MizonPreview", targets: ["MizonPreview"])
    ],
    dependencies: [.package(url: "https://github.com/Shahesmaeili/Mizon.API.Swift", branch: "main")],
    targets: [
        .target(name: "MizonAppleCore", dependencies: [
            .product(name: "MizonAPI", package: "Mizon.API.Swift"),
            .product(name: "MizonAPIClient", package: "Mizon.API.Swift")
        ]),
        .target(name: "MizonAppleUI", dependencies: ["MizonAppleCore"], resources: [.process("Resources")]),
        .executableTarget(name: "MizonPreview", dependencies: ["MizonAppleUI", "MizonAppleCore"], path: "App/Mac"),
        .testTarget(name: "MizonAppleTests", dependencies: ["MizonAppleCore", .product(name: "MizonAPI", package: "Mizon.API.Swift"), .product(name: "MizonAPIClient", package: "Mizon.API.Swift")], path: "Tests")
    ],
    swiftLanguageModes: [.v6]
)
