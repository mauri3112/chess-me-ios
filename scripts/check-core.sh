#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

# Keep the usual Xcode path unchanged on configured machines and CI runners.
# xcrun may return a cached binary path while Xcode setup is still pending.
xcode_directory="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ -d "$xcode_directory" ]] && DEVELOPER_DIR="$xcode_directory" /usr/bin/xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
  DEVELOPER_DIR="$xcode_directory" /usr/bin/xcrun swift test "$@"
  exit
fi

# This machine's standalone command-line toolchain can run Swift Testing even
# while Xcode's first-launch setup is pending. It needs the installed framework.
swift_binary=/Library/Developer/CommandLineTools/usr/bin/swift
frameworks_dir=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks
if [[ ! -x "$swift_binary" || ! -d "$frameworks_dir/Testing.framework" ]]; then
  echo "Configure Xcode and run swift test, or install Command Line Tools and Xcode's Testing framework." >&2
  exit 1
fi

# File-provider metadata in a synced Documents folder can prevent codesigning
# the generated test bundle. Keep this temporary build outside the checkout.
scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/chess-me-core.XXXXXX")"
trap 'rm -rf -- "$scratch_dir"' EXIT

DEVELOPER_DIR=/Library/Developer/CommandLineTools "$swift_binary" test \
  --scratch-path "$scratch_dir" \
  --build-system native --disable-xctest \
  -Xswiftc -F -Xswiftc "$frameworks_dir" \
  -Xlinker -F -Xlinker "$frameworks_dir" \
  -Xlinker -rpath -Xlinker "$frameworks_dir" "$@"
