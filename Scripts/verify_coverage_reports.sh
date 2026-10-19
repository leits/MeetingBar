#!/usr/bin/env bash
# Fail closed if either coverage suite did not produce a usable report.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <swiftpm.lcov> <cobertura.xml>" >&2
  exit 2
fi

logic_report="$1"
app_report="$2"

if [[ ! -s "$logic_report" ]] ||
   ! grep -q '^SF:' "$logic_report" ||
   ! grep -q '^DA:' "$logic_report"; then
  echo "Missing, empty, or invalid SwiftPM LCOV coverage: $logic_report" >&2
  exit 1
fi

if [[ ! -s "$app_report" ]] ||
   ! grep -q '<coverage\b' "$app_report" ||
   ! grep -q '<class\b' "$app_report"; then
  echo "Missing, empty, or invalid app-hosted Cobertura coverage: $app_report" >&2
  exit 1
fi

echo "Both SwiftPM and app-hosted coverage reports exist and contain file coverage."
