#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
bridge="$project_dir/dist/Scrcpy.app/Contents/Helpers/ScrcpyMirror.app/Contents/Frameworks/MirrorMenuBridge.dylib"
test_bin="$project_dir/.build/IMEBridgeTests"

/usr/bin/xcrun clang -fobjc-arc -target arm64-apple-macos13 -framework AppKit \
    -Wl,-export_dynamic -o "$test_bin" "$project_dir/tests/IMEBridgeTests.m"
SCRCPY_MAC_IME_BRIDGE=1 DYLD_INSERT_LIBRARIES="$bridge" "$test_bin"
