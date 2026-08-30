#!/bin/sh
set -eu

APP_PATH="${1:-build/DerivedData/Build/Products/Debug/MarkdStage.app}"
TARGET_PATH="${2:-samples/demo.md}"

resolve_path() {
  path="$1"
  dir="$(dirname "$path")"
  base="$(basename "$path")"
  printf '%s/%s\n' "$(cd "$dir" && pwd -P)" "$base"
}

APP_PATH="$(resolve_path "$APP_PATH")"
TARGET_PATH="$(resolve_path "$TARGET_PATH")"
EXECUTABLE="$APP_PATH/Contents/MacOS/MarkdStage"
TMP_DIR="$(mktemp -d /tmp/markdstage-local-cli.XXXXXX)"
LOCAL_COMMAND="$TMP_DIR/markdstage"
APP_PID=""

cleanup() {
  if [ -n "$APP_PID" ] && ps -p "$APP_PID" -o pid= >/dev/null 2>&1; then
    kill "$APP_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

test -x "$EXECUTABLE" || { echo "MarkdStage executable not found: $EXECUTABLE" >&2; exit 1; }
test -f "$TARGET_PATH" || { echo "Target deck not found: $TARGET_PATH" >&2; exit 1; }

ln -s "$EXECUTABLE" "$LOCAL_COMMAND"
echo "Launching this checkout through a temporary markdstage command:"
echo "  $LOCAL_COMMAND \"$TARGET_PATH\""
echo
echo "This does not modify /Applications/MarkdStage.app or /usr/local/bin/markdstage."
echo "Quit MarkdStage, or press Ctrl-C here, to finish."
"$LOCAL_COMMAND" "$TARGET_PATH" &
APP_PID="$!"
wait "$APP_PID"
