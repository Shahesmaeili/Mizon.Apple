// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Mizon.Apple",
    defaultLocalization: "en",
    platforms: [.macOS(.v26), .iOS(.v26), .watchOS(.v26)],
    products: [
        .library(name: "MizonAppleCore", targets: ["MizonAppleCore"]),
        .library(name: "MizonAppleUI", targets: ["MizonAppleUI"]),
        .executable(name: "MizonPreview", targets: ["MizonPreview"])
    ],
    dependencies: [
        .package(url: "https://github.com/Shahesmaeili/Mizon.API.Swift", branch: "main"),
        .package(url: "https://github.com/warrenm/GLTFKit2", exact: "0.5.15"),
        .package(url: "https://github.com/airbnb/lottie-spm.git", exact: "4.6.1")
    ],
    targets: [
        .target(name: "MizonAppleCore", dependencies: [
            .product(name: "MizonAPI", package: "Mizon.API.Swift"),
            .product(name: "MizonAPIClient", package: "Mizon.API.Swift")
        ]),
        .target(name: "MizonAppleUI", dependencies: [
            "MizonAppleCore",
            .product(name: "GLTFKit2", package: "GLTFKit2", condition: .when(platforms: [.macOS, .iOS])),
            .product(name: "Lottie", package: "lottie-spm", condition: .when(platforms: [.macOS, .iOS]))
        ], resources: [.process("Resources")]),
        .executableTarget(name: "MizonPreview", dependencies: ["MizonAppleUI", "MizonAppleCore"], path: "App/Mac"),
        .testTarget(name: "MizonAppleTests", dependencies: ["MizonAppleCore", "MizonAppleUI", .product(name: "MizonAPI", package: "Mizon.API.Swift"), .product(name: "MizonAPIClient", package: "Mizon.API.Swift")], path: "Tests")
    ],
    swiftLanguageModes: [.v6]
)
