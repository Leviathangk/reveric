#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
version=0.39.0
sha=cc5a820c848ecd637d8c38e5a444ae489bbe95315de4a71884f2a8e52d63fc73
if [[ -f Frameworks/.mdk-version ]] && [[ "$(cat Frameworks/.mdk-version)" == "$version:$sha" ]]; then
  exit 0
fi
mkdir -p .cache Frameworks
archive=".cache/mdk-sdk-$version.tar.xz"
if [[ ! -f "$archive" ]]; then
  curl --fail --location --retry 3 "https://github.com/wang-bin/mdk-sdk/releases/download/v$version/mdk-sdk-macOS.tar.xz" -o "$archive.part"
  mv "$archive.part" "$archive"
fi
echo "$sha  $archive" | shasum -a 256 -c -
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
tar -xf "$archive" -C "$staging"
# MDK weak-links its optional FFmpeg runtime. Only FFmpegKit supplies FFmpeg.
rsync -a --delete --delete-excluded --exclude 'libffmpeg*' --exclude '_CodeSignature' \
  "$staging/mdk-sdk/lib/mdk.framework/" Frameworks/mdk.framework/
printf '%s' "$version:$sha" > Frameworks/.mdk-version
