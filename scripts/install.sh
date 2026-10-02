#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT

echo "Building Veyra (Release)…"
if ! xcodebuild -project Veyra.xcodeproj -scheme Veyra -configuration Release \
  -derivedDataPath "$build_dir" build > "$build_dir/build.log" 2>&1; then
  grep -E "error:" "$build_dir/build.log" || tail -20 "$build_dir/build.log"
  echo "Build failed." >&2
  exit 1
fi

echo "Installing to /Applications…"
pkill -x Veyra || true
while pgrep -x Veyra > /dev/null; do sleep 0.1; done
rm -rf /Applications/Veyra.app
cp -R "$build_dir/Build/Products/Release/Veyra.app" /Applications/

open /Applications/Veyra.app
echo "Veyra is installed and running. Look for the V in the menu bar."
