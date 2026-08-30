#!/bin/sh
set -eu

APP_PATH="${1:-build/DerivedData/Build/Products/Debug/MarkdStage.app}"
BUNDLE_ID="dev.jp27.MarkdStage"

if [ ! -d "$APP_PATH" ]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

cleanup() {
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
sleep 1
open -n "$APP_PATH"
sleep 3
osascript -e "tell application id \"$BUNDLE_ID\" to activate" >/dev/null 2>&1 || true
sleep 1

ONSCREEN_COUNT="$(swift -e 'import CoreGraphics
let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
let count = windows.filter {
  ($0[kCGWindowOwnerName as String] as? String) == "MarkdStage" &&
  (($0[kCGWindowBounds as String] as? [String: Any])?["Width"] as? Double ?? 0) > 100 &&
  (($0[kCGWindowBounds as String] as? [String: Any])?["Height"] as? Double ?? 0) > 100
}.count
print(count)')"

if [ "$ONSCREEN_COUNT" -lt 1 ]; then
  echo "No on-screen MarkdStage window was reported by CoreGraphics." >&2
  exit 1
fi

test -f "$APP_PATH/Contents/Resources/Web/index.html"
test -f "$APP_PATH/Contents/Resources/Web/renderer/renderer.js"
test -f "$APP_PATH/Contents/Resources/Web/vendor/mermaid.min.js"

echo "MarkdStage launch smoke test passed."
