#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift test
npm ci --prefix backend --no-audit --no-fund
npm test --prefix backend
