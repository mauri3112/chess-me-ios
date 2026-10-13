#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
# The core now imports a native C++ target and uses a generated resource bundle.
# Let Xcode resolve and check the real package graph, including those dependencies.
exec "$repo_dir/scripts/check-ios.sh" --build
