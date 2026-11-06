#!/bin/bash
# Command Line Tools don't pass the swift-testing macro plugin to the compiler; point it there.
set -euo pipefail
cd "$(dirname "$0")/.."
DEV="$(xcode-select -p)"
for P in "$DEV/usr/lib/swift/host/plugins/testing" "$DEV/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/testing"; do
  if [ -d "$P" ]; then exec swift test -Xswiftc -plugin-path -Xswiftc "$P" "$@"; fi
done
exec swift test "$@"
