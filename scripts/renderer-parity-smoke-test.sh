#!/bin/sh
set -eu

APP_PATH="${1:-build/DerivedData/Build/Products/Debug/MarkdStage.app}"
EXECUTABLE="$APP_PATH/Contents/MacOS/MarkdStage"
FIXTURE_DIR="src/MarkdStageTests/Fixtures/RenderingParity"
WORK_DIR="build/.renderer-parity-smoke.$$"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT INT TERM

test -x "$EXECUTABLE" || {
  echo "MarkdStage executable not found: $EXECUTABLE" >&2
  exit 1
}

sh scripts/pdf-export-smoke-test.sh "$APP_PATH" samples/demo.md 5
sh scripts/pdf-export-smoke-test.sh "$APP_PATH" "$FIXTURE_DIR/deck.md" 7

mkdir -p "$WORK_DIR"
set +e
"$EXECUTABLE" \
  --pdf-smoke \
  "$FIXTURE_DIR/missing-asset.md" \
  "$WORK_DIR/missing-asset.pdf" \
  >"$WORK_DIR/stdout.log" \
  2>"$WORK_DIR/stderr.log"
STATUS="$?"
set -e

if [ "$STATUS" -eq 0 ]; then
  echo "PDF export unexpectedly accepted a missing local asset." >&2
  exit 1
fi
if ! grep -F "parity-missing.svg" "$WORK_DIR/stderr.log" >/dev/null; then
  echo "Missing-asset failure did not identify the affected file." >&2
  cat "$WORK_DIR/stderr.log" >&2 || true
  exit 1
fi
if [ -e "$WORK_DIR/missing-asset.pdf" ]; then
  echo "PDF export saved a partial file after an asset failure." >&2
  exit 1
fi

echo "MarkdStage renderer parity smoke test passed."
