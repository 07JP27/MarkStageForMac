#!/bin/sh
set -eu

APP_PATH="${1:-build/DerivedData/Build/Products/Debug/MarkdStage.app}"
TARGET_PATH="${2:-samples/demo.md}"
TIMEOUT_SECONDS="${CLI_LAUNCH_TIMEOUT_SECONDS:-30}"

resolve_path() {
  path="$1"
  if [ ! -e "$path" ]; then
    printf '%s\n' "$path"
    return
  fi
  dir="$(dirname "$path")"
  base="$(basename "$path")"
  printf '%s/%s\n' "$(cd "$dir" && pwd -P)" "$base"
}

window_count_for_pid() {
  swift -e 'import CoreGraphics
import Foundation
let pid = Int32(CommandLine.arguments[1])!
let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
let count = windows.filter {
  (($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value) == pid &&
  (($0[kCGWindowBounds as String] as? [String: Any])?["Width"] as? Double ?? 0) > 100 &&
  (($0[kCGWindowBounds as String] as? [String: Any])?["Height"] as? Double ?? 0) > 100
}.count
print(count)' "$1"
}

APP_PATH="$(resolve_path "$APP_PATH")"
TARGET_PATH="$(resolve_path "$TARGET_PATH")"
EXECUTABLE="$APP_PATH/Contents/MacOS/MarkdStage"
TMP_DIR="$(mktemp -d /tmp/markdstage-cli-smoke.XXXXXX)"
LOCAL_COMMAND="$TMP_DIR/markdstage"
STDOUT_LOG="$TMP_DIR/stdout.log"
STDERR_LOG="$TMP_DIR/stderr.log"
APP_PID=""

cleanup() {
  if [ -n "$APP_PID" ] && ps -p "$APP_PID" -o pid= >/dev/null 2>&1; then
    kill "$APP_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

test -d "$APP_PATH" || { echo "App bundle not found: $APP_PATH" >&2; exit 1; }
test -x "$EXECUTABLE" || { echo "MarkdStage executable not found: $EXECUTABLE" >&2; exit 1; }
test -f "$TARGET_PATH" || { echo "Target deck not found: $TARGET_PATH" >&2; exit 1; }

ln -s "$EXECUTABLE" "$LOCAL_COMMAND"
"$LOCAL_COMMAND" "$TARGET_PATH" >"$STDOUT_LOG" 2>"$STDERR_LOG" &
APP_PID="$!"

START_TIME="$(date +%s)"
while :; do
  NOW="$(date +%s)"
  if [ "$((NOW - START_TIME))" -ge "$TIMEOUT_SECONDS" ]; then
    echo "No MarkdStage window was reported for PID $APP_PID within ${TIMEOUT_SECONDS}s." >&2
    cat "$STDERR_LOG" >&2 || true
    exit 1
  fi
  if ! ps -p "$APP_PID" -o pid= >/dev/null 2>&1; then
    echo "MarkdStage exited during CLI symlink launch." >&2
    cat "$STDOUT_LOG" >&2 || true
    cat "$STDERR_LOG" >&2 || true
    exit 1
  fi
  if [ "$(window_count_for_pid "$APP_PID")" -gt 0 ]; then
    break
  fi
  sleep 1
done

sleep 2
if ! ps -p "$APP_PID" -o pid= >/dev/null 2>&1; then
  echo "MarkdStage exited after opening the deck." >&2
  cat "$STDERR_LOG" >&2 || true
  exit 1
fi

echo "MarkdStage CLI symlink smoke test passed."
