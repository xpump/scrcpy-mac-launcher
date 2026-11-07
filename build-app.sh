#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h}
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Info.plist")
if [[ "${GITHUB_REF_TYPE:-}" == "tag" && "${GITHUB_REF_NAME:-}" != "v$version" ]]; then
    print -u2 "Git tag $GITHUB_REF_NAME 与应用版本 v$version 不一致"
    exit 1
fi
scrcpy_version=5.0.1
archive_name="scrcpy-macos-aarch64-v${scrcpy_version}.tar.gz"
archive_sha256=33611e51977a8289e2e124b220f727895181ef2eb9060e0987a4dc2db9cf0d6b
archive_path="${SCRCPY_ARCHIVE:-$project_dir/.build/$archive_name}"
upstream_dir="$project_dir/.build/scrcpy-macos-aarch64-v${scrcpy_version}"
dist_dir="$project_dir/dist"
app_dir="$dist_dir/Scrcpy.app"
helper_dir="$app_dir/Contents/Helpers/ScrcpyMirror.app"
resources_dir="$app_dir/Contents/Resources"

mkdir -p "$project_dir/.build" "$dist_dir"
if [[ ! -f "$archive_path" ]]; then
    curl -fL --retry 3 \
        "https://github.com/Genymobile/scrcpy/releases/download/v${scrcpy_version}/$archive_name" \
        -o "$archive_path"
fi

actual_sha256=$(shasum -a 256 "$archive_path" | awk '{print $1}')
if [[ "$actual_sha256" != "$archive_sha256" ]]; then
    print -u2 "scrcpy 发行包 SHA-256 不匹配"
    exit 1
fi

if [[ ! -x "$upstream_dir/scrcpy" ]]; then
    tar -xzf "$archive_path" -C "$project_dir/.build"
fi

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$helper_dir/Contents/MacOS" "$helper_dir/Contents/Resources" \
    "$helper_dir/Contents/Frameworks" \
    "$resources_dir/bin" "$resources_dir/icons" "$resources_dir/docs" \
    "$project_dir/.build/ModuleCache" "$project_dir/.build/ClangCache"
cp -X "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
cp -X "$project_dir/Mirror-Info.plist" "$helper_dir/Contents/Info.plist"
cp -X "$upstream_dir/scrcpy" "$helper_dir/Contents/MacOS/scrcpy"
cp -X "$upstream_dir/adb" "$upstream_dir/scrcpy-server" "$resources_dir/bin/"
cp -X "$upstream_dir/scrcpy.png" "$upstream_dir/disconnected.png" "$resources_dir/icons/"
cp -X "$upstream_dir/LICENSE" "$upstream_dir/scrcpy.1" "$project_dir/NOTICE.md" "$resources_dir/docs/"
chmod 755 "$helper_dir/Contents/MacOS/scrcpy" "$resources_dir/bin/adb"

/usr/bin/sips -s format icns "$upstream_dir/scrcpy.png" --out "$resources_dir/scrcpy.icns" >/dev/null
cp -X "$resources_dir/scrcpy.icns" "$helper_dir/Contents/Resources/scrcpy.icns"
/usr/bin/xcrun swiftc -O -target arm64-apple-macos13 \
    -module-cache-path "$project_dir/.build/ModuleCache" \
    -Xcc "-fmodules-cache-path=$project_dir/.build/ClangCache" \
    -o "$app_dir/Contents/MacOS/ScrcpyLauncher" "$project_dir/ScrcpyLauncher.swift"

/usr/bin/xcrun clang -fobjc-arc -dynamiclib -target arm64-apple-macos13 \
    -framework AppKit -o "$helper_dir/Contents/Frameworks/MirrorMenuBridge.dylib" \
    "$project_dir/MirrorMenuBridge.m"
/usr/bin/codesign --force --sign - "$helper_dir/Contents/Frameworks/MirrorMenuBridge.dylib"
/usr/bin/codesign --force --sign - "$helper_dir"
/usr/bin/codesign --force --sign - "$app_dir"
/usr/bin/codesign --verify --deep --strict "$app_dir"

zip_path="$dist_dir/ScrcpyLauncher-macos-arm64-v${version}.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$zip_path"
checksum=$(shasum -a 256 "$zip_path" | awk '{print $1}')
printf '%s  %s\n' "$checksum" "${zip_path:t}" > "$zip_path.sha256"
print "已生成 $zip_path"
