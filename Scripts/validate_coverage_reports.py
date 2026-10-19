#!/usr/bin/env python3
"""Fail CI before Codecov upload when either coverage report is missing or empty."""

import sys
import xml.etree.ElementTree as ET
from pathlib import Path


class CoverageReportError(ValueError):
    pass


def validate_lcov(path: Path) -> None:
    if not path.is_file() or path.stat().st_size == 0:
        raise CoverageReportError(f"Missing or empty SwiftPM LCOV report: {path}")

    sources = 0
    executable_lines = 0
    in_record = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("SF:"):
            if not line[3:].strip():
                raise CoverageReportError("LCOV record has no source path")
            sources += 1
            in_record = True
        elif line.startswith("DA:"):
            if not in_record:
                raise CoverageReportError("LCOV executable line has no source record")
            parts = line[3:].split(",")
            if len(parts) < 2 or not all(p.isdecimal() for p in parts[:2]):
                raise CoverageReportError(f"Invalid LCOV executable line: {line}")
            executable_lines += 1
        elif line == "end_of_record":
            in_record = False

    if not sources or not executable_lines:
        raise CoverageReportError("SwiftPM LCOV has no source records or executable lines")


def validate_cobertura(path: Path) -> None:
    if not path.is_file() or path.stat().st_size == 0:
        raise CoverageReportError(f"Missing or empty app-hosted Cobertura report: {path}")

    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as error:
        raise CoverageReportError(f"Malformed app-hosted Cobertura report: {error}") from error

    if root.tag != "coverage":
        raise CoverageReportError(f"Unexpected Cobertura root element: {root.tag}")

    try:
        valid = int(root.attrib["lines-valid"])
        covered = int(root.attrib["lines-covered"])
    except (KeyError, ValueError) as error:
        raise CoverageReportError("Cobertura is missing valid line totals") from error

    if valid <= 0 or covered < 0 or covered > valid:
        raise CoverageReportError("Cobertura contains invalid or empty line totals")
    if not root.findall(".//class"):
        raise CoverageReportError("Cobertura has no instrumented classes")


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: validate_coverage_reports.py <swiftpm.lcov> <cobertura.xml>", file=sys.stderr)
        return 2
    try:
        validate_lcov(Path(sys.argv[1]))
        validate_cobertura(Path(sys.argv[2]))
    except (CoverageReportError, OSError, UnicodeError) as error:
        print(f"Coverage preflight failed: {error}", file=sys.stderr)
        return 1
    print("Both SwiftPM and app-hosted coverage reports are present and non-empty")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
