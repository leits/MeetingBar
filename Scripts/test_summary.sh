#!/bin/bash
#
# test_summary.sh
#
# Emits a Markdown table summarizing app-hosted test results read from an
# Xcode result bundle. Used to publish results to the CI job summary; prints
# a placeholder (and exits 0) when no bundle is present so it never breaks a
# run that failed before producing results.

set -euo pipefail

BUNDLE="${1:-build/coverage/MeetingBar.xcresult}"

if [ ! -d "$BUNDLE" ]; then
    echo "_No app test results found._"
    exit 0
fi

python3 - "$BUNDLE" <<'PY'
import json
import subprocess
import sys

out = subprocess.run(
    ["xcrun", "xcresulttool", "get", "test-results", "summary",
     "--path", sys.argv[1], "--format", "json"],
    capture_output=True, text=True,
)
try:
    d = json.loads(out.stdout)
except json.JSONDecodeError:
    print("_Could not read app test results._")
    sys.exit(0)

print("| Result | Passed | Failed | Skipped |")
print("|--------|--------|--------|---------|")
print(f"| {d.get('result', '?')} | {d.get('passedTests', 0)} | "
      f"{d.get('failedTests', 0)} | {d.get('skippedTests', 0)} |")
PY
