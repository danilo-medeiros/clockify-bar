#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

release_version="${1:?Usage: bash scripts/package-release.sh 1.2.3}"
if [[ ! "$release_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'Release version must have the form 1.2.3\n' >&2
    exit 1
fi

APP_VERSION="$release_version" bash scripts/build-app.sh --arch arm64 --arch x86_64
app_dir="$PWD/dist/Clockify Bar.app"
architectures="$(lipo -archs "$app_dir/Contents/MacOS/ClockifyBar")"
for architecture in arm64 x86_64; do
    case " $architectures " in
        *" $architecture "*) ;;
        *) printf 'Release binary is missing %s\n' "$architecture" >&2; exit 1 ;;
    esac
done
release_dir="$PWD/dist/releases/v$release_version"
archive_name="Clockify-Bar-$release_version-macOS-universal.zip"
mkdir -p "$release_dir"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$release_dir/$archive_name"
(
    cd "$release_dir"
    shasum -a 256 "$archive_name" > SHA256SUMS.txt
)
printf 'Release assets: %s\n' "$release_dir"
