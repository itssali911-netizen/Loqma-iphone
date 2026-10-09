#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -m unittest discover -s BuildTests -v
if [[ "$(uname -s)" != Darwin ]]; then
 swift test -j 1
    echo "Core checks complete. iOS build verification requires macOS and Xcode."
    exit 0
fi
python3 Scripts/build_ios.py check
