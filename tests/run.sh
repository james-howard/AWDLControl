#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/awdl-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter \
    -framework Cocoa -framework Network -framework ServiceManagement \
    -framework UserNotifications \
    tests/GameModeTests.m AWDLControl/Reachability.m -o "$test_dir/game-mode-tests"
"$test_dir/game-mode-tests"
