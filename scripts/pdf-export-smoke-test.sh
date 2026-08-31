#!/bin/sh
set -eu

APP_PATH="${1:-build/DerivedData/Build/Products/Debug/MarkdStage.app}"
DECK_PATH="${2:-samples/demo.md}"
EXPECTED_PAGE_COUNT="${3:-5}"
EXPECTED_TEXT="${4:-Markdown}"
TIMEOUT_SECONDS="${PDF_EXPORT_SMOKE_TIMEOUT_SECONDS:-60}"

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

APP_PATH="$(resolve_path "$APP_PATH")"
DECK_PATH="$(resolve_path "$DECK_PATH")"
EXECUTABLE="$APP_PATH/Contents/MacOS/MarkdStage"
WORK_DIR="build/.pdf-export-smoke.$$"
OUTPUT_PDF="$WORK_DIR/output.pdf"
STDOUT_LOG="$WORK_DIR/stdout.log"
STDERR_LOG="$WORK_DIR/stderr.log"
APP_PID=""

cleanup() {
  if [ -n "$APP_PID" ] && kill -0 "$APP_PID" >/dev/null 2>&1; then
    kill "$APP_PID" >/dev/null 2>&1 || true
    sleep 1
    if kill -0 "$APP_PID" >/dev/null 2>&1; then
      kill -KILL "$APP_PID" >/dev/null 2>&1 || true
    fi
    wait "$APP_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT INT TERM

test -d "$APP_PATH" || { echo "App bundle not found: $APP_PATH" >&2; exit 1; }
test -x "$EXECUTABLE" || { echo "MarkdStage executable not found: $EXECUTABLE" >&2; exit 1; }
test -f "$DECK_PATH" || { echo "Deck not found: $DECK_PATH" >&2; exit 1; }
case "$EXPECTED_PAGE_COUNT" in
  ''|*[!0-9]*) echo "Expected page count must be a positive integer." >&2; exit 1 ;;
esac
test "$EXPECTED_PAGE_COUNT" -gt 1 || {
  echo "PDF smoke requires an expected page count greater than one." >&2
  exit 1
}

mkdir -p "$WORK_DIR"
"$EXECUTABLE" --pdf-smoke "$DECK_PATH" "$OUTPUT_PDF" \
  >"$STDOUT_LOG" 2>"$STDERR_LOG" &
APP_PID="$!"

START_TIME="$(date +%s)"
while kill -0 "$APP_PID" >/dev/null 2>&1; do
  STATE="$(ps -p "$APP_PID" -o state= 2>/dev/null | tr -d ' ' || true)"
  case "$STATE" in
    ''|Z*) break ;;
  esac
  NOW="$(date +%s)"
  if [ "$((NOW - START_TIME))" -ge "$TIMEOUT_SECONDS" ]; then
    echo "PDF export smoke timed out after ${TIMEOUT_SECONDS}s (PID $APP_PID)." >&2
    cat "$STDERR_LOG" >&2 || true
    exit 1
  fi
  sleep 1
done

if wait "$APP_PID"; then
  STATUS=0
else
  STATUS="$?"
fi
APP_PID=""
if [ "$STATUS" -ne 0 ]; then
  echo "PDF export smoke process failed with exit status $STATUS." >&2
  cat "$STDOUT_LOG" >&2 || true
  cat "$STDERR_LOG" >&2 || true
  exit "$STATUS"
fi

test -f "$OUTPUT_PDF" || { echo "PDF smoke did not create an output file." >&2; exit 1; }
HEADER="$(dd if="$OUTPUT_PDF" bs=4 count=1 2>/dev/null)"
test "$HEADER" = "%PDF" || { echo "Output does not have a valid PDF header." >&2; exit 1; }

xcrun swift -e 'import Foundation
import PDFKit

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let expectedPages = Int(CommandLine.arguments[2])!
let expectedText = CommandLine.arguments[3]
guard let document = PDFDocument(url: url) else {
    fputs("PDFKit could not open the output PDF.\n", stderr)
    exit(1)
}
guard document.pageCount == expectedPages else {
    fputs("Expected \(expectedPages) PDF pages, found \(document.pageCount).\n", stderr)
    exit(1)
}
let renderedText = (0..<document.pageCount)
    .compactMap { document.page(at: $0)?.string }
    .joined(separator: "\n")
guard renderedText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 else {
    fputs("PDF does not contain meaningful rendered text.\n", stderr)
    exit(1)
}
guard renderedText.localizedCaseInsensitiveContains(expectedText) else {
    fputs("PDF text does not contain expected marker: \(expectedText)\n", stderr)
    exit(1)
}' "$OUTPUT_PDF" "$EXPECTED_PAGE_COUNT" "$EXPECTED_TEXT"

cat "$STDOUT_LOG"
echo "MarkdStage live WebKit PDF export smoke test passed."
