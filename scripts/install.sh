#!/bin/bash
# Build, install to /Applications, (re)launch. Ad-hoc signed: re-allow any TCC permissions afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
pkill -x Cut 2>/dev/null || true
for _ in $(seq 50); do pgrep -xq Cut || break; sleep 0.1; done  # let it quit, or `open` fails with -600
rm -rf /Applications/Cut.app
cp -R build/Cut.app /Applications/Cut.app
open /Applications/Cut.app
echo "Installed /Applications/Cut.app"
