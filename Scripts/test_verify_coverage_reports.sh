#!/usr/bin/env bash
# Pure shell smoke checks for the coverage-report completeness gate.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check="$script_dir/verify_coverage_reports.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

printf 'SF:MeetingBar/Calendar/EventSelection.swift\nDA:1,1\nend_of_record\n' > "$tmp/swiftpm.lcov"
printf '<?xml version="1.0"?><coverage><packages><package><classes><class name="MeetingBar" /></classes></package></packages></coverage>\n' > "$tmp/cobertura.xml"

bash "$check" "$tmp/swiftpm.lcov" "$tmp/cobertura.xml"

# Neither missing nor syntactically empty/invalid reports may silently pass.
for missing in logic app; do
  if [[ "$missing" == logic ]]; then
    if bash "$check" "$tmp/no-such-file" "$tmp/cobertura.xml"; then
      echo "Missing SwiftPM report was incorrectly accepted" >&2
      exit 1
    fi
  else
    if bash "$check" "$tmp/swiftpm.lcov" "$tmp/no-such-file"; then
      echo "Missing app-hosted report was incorrectly accepted" >&2
      exit 1
    fi
  fi
done

printf 'TN:empty\n' > "$tmp/swiftpm.lcov"
if bash "$check" "$tmp/swiftpm.lcov" "$tmp/cobertura.xml"; then
  echo "LCOV report without source/line data was incorrectly accepted" >&2
  exit 1
fi

printf 'SF:MeetingBar/Calendar/EventSelection.swift\nDA:1,1\n' > "$tmp/swiftpm.lcov"
printf '<?xml version="1.0"?><coverage></coverage>\n' > "$tmp/cobertura.xml"
if bash "$check" "$tmp/swiftpm.lcov" "$tmp/cobertura.xml"; then
  echo "Cobertura report without file data was incorrectly accepted" >&2
  exit 1
fi

echo "Coverage report completeness contracts passed."
