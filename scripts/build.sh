#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
xcodegen generate
xcodebuild -project Chup.xcodeproj -scheme Chup -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .artifacts/DerivedData CODE_SIGNING_ALLOWED=NO build
