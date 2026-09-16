#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CHUP_DESIGN_OUTPUT="$PWD/Design/Previews"
'.artifacts/DerivedData/Build/Products/Debug/Chup!.app/Contents/MacOS/Chup!' --render-design
