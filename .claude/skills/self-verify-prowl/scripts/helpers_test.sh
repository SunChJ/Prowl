#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$script_dir/helpers.sh"

assert_debug_executable() {
  local executable="$1"
  if ! is_debug_prowl_executable "$executable"; then
    printf 'Expected debug executable: %s\n' "$executable" >&2
    return 1
  fi
}

assert_not_debug_executable() {
  local executable="$1"
  if is_debug_prowl_executable "$executable"; then
    printf 'Expected non-debug executable: %s\n' "$executable" >&2
    return 1
  fi
}

assert_debug_executable \
  "/Users/test/Library/Developer/Xcode/DerivedData/Prowl-abc/Build/Products/Debug/Prowl Debug.app/Contents/MacOS/ProwlApp"
assert_debug_executable \
  "/tmp/DerivedData/Prowl-abc/Build/Products/Debug/Prowl.app/Contents/MacOS/ProwlApp"
assert_not_debug_executable "/Applications/Prowl.app/Contents/MacOS/ProwlApp"
assert_not_debug_executable \
  "/Users/test/Library/Developer/Xcode/DerivedData/Prowl-abc/Build/Products/Release/Prowl.app/Contents/MacOS/ProwlApp"
assert_not_debug_executable \
  "/Users/test/Library/Developer/Xcode/DerivedData/Prowl-abc/Build/Products/Debug/Prowl Debug.app/Contents/MacOS/Other"

printf 'helpers_test: PASS\n'
