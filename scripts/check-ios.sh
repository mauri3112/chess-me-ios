#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mode="${1:---build}"
case "$mode" in
  --build|--test) ;;
  *) echo "Usage: scripts/check-ios.sh [--build|--test]" >&2; exit 2 ;;
esac

if [[ ! -d "$DEVELOPER_DIR" ]]; then
  echo "Set DEVELOPER_DIR to an installed Xcode.app/Contents/Developer." >&2
  exit 1
fi

build_options=(
  -project "$repo_dir/ios/ChessMe.xcodeproj"
  -scheme ChessMe
  -configuration Debug
  -derivedDataPath "$repo_dir/.build/ios"
  CODE_SIGNING_ALLOWED=NO
)

if [[ "$mode" == "--build" ]]; then
  xcodebuild "${build_options[@]}" -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
else
  if [[ -n "${IOS_TEST_DESTINATION:-}" ]]; then
    destination="$IOS_TEST_DESTINATION"
  else
    simulator_id="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
candidates = [d for runtime, group in devices.items() if "iOS" in runtime
              for d in group if d.get("isAvailable") and d["name"].startswith("iPhone")]
if not candidates:
    sys.exit("No available iPhone simulator. Install an iOS runtime in Xcode Settings > Components.")
print(sorted(candidates, key=lambda d: (d["state"] != "Booted", d["name"]))[0]["udid"])
')"
    destination="platform=iOS Simulator,id=$simulator_id"
  fi
  result_path="${IOS_RESULT_BUNDLE_PATH:-$repo_dir/.build/ios-results/$(date +%Y%m%d-%H%M%S).xcresult}"
  mkdir -p "$(dirname "$result_path")"
  xcodebuild "${build_options[@]}" -destination "$destination" \
    -parallel-testing-enabled NO -resultBundlePath "$result_path" test
fi
