#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n "${APP_VERSION:-}" && ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'APP_VERSION must have the form 1.2.3\n' >&2
    exit 1
fi
swift build -c release "$@"
binary_dir="$(swift build -c release --show-bin-path "$@")"
app_dir="$PWD/dist/Clockify Bar.app"
mkdir -p "$app_dir/Contents/MacOS"
cp "$binary_dir/ClockifyBar" "$app_dir/Contents/MacOS/ClockifyBar"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
if [[ -n "${APP_VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$app_dir/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_VERSION" "$app_dir/Contents/Info.plist"
fi
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
printf 'Built %s\n' "$app_dir"
