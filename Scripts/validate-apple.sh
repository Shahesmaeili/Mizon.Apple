#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch_path="${SWIFT_SCRATCH_PATH:-$PWD/.build}"
swift test --scratch-path "$scratch_path"
swift build --scratch-path "$scratch_path" --target MizonAppleUI --triple arm64-apple-ios26.0 --sdk "$(xcrun --sdk iphoneos --show-sdk-path)"
swift build --scratch-path "$scratch_path" --target MizonAppleUI --triple arm64_32-apple-watchos26.0 --sdk "$(xcrun --sdk watchos --show-sdk-path)"
