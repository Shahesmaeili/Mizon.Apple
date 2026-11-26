#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

scratch="$(mktemp -d "${TMPDIR:-/tmp}/mizon-deep-links.XXXXXXXX")"
trap 'rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/Sources/MizonAppleCore" "$scratch/Sources/MizonAppleUI" "$scratch/Tests"
cp Sources/MizonAppleCore/Models/MizonDeepLink{,Result}.swift "$scratch/Sources/MizonAppleCore/"
cp Sources/MizonAppleUI/Components/MizonDeepLinkRouter.swift "$scratch/Sources/MizonAppleUI/"
cp Tests/MizonDeepLink{,Parity,Router}Tests.swift Tests/Fixtures/deep-links-v1.json "$scratch/Tests/"

cat > "$scratch/Package.swift" <<'SWIFT'
// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "MizonDeepLinkChecks",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "MizonAppleCore"),
        .target(name: "MizonAppleUI", dependencies: ["MizonAppleCore"]),
        .testTarget(name: "MizonDeepLinkChecks", dependencies: ["MizonAppleCore", "MizonAppleUI"],
                    path: "Tests", resources: [.copy("deep-links-v1.json")])
    ],
    swiftLanguageModes: [.v6]
)
SWIFT
swift test -c release --package-path "$scratch"
