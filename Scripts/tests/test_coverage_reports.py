"""Checks for two-report preflight and layer-aware coverage policy."""

import re
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
ROOT = SCRIPTS.parent
sys.path.insert(0, str(SCRIPTS))

from validate_coverage_reports import (  # noqa: E402
    CoverageReportError,
    validate_cobertura,
    validate_lcov,
)


LCOV = (
    "TN:\n"
    "SF:MeetingBar/Calendar/EventFiltering.swift\n"
    "DA:12,1\n"
    "DA:13,0\n"
    "end_of_record\n"
)
XML = (
    '<coverage lines-valid="2" lines-covered="1">'
    '<packages><package name="MeetingBar"><classes>'
    '<class name="CalendarSync" filename="CalendarSync.swift"/>'
    '</classes></package></packages></coverage>'
)

class CoverageReportsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.logic = Path(self.temp.name) / "swiftpm.lcov"
        self.app = Path(self.temp.name) / "cobertura.xml"

    def write_both(self):
        self.logic.write_text(LCOV, encoding="utf-8")
        self.app.write_text(XML, encoding="utf-8")

    def test_valid_reports_pass(self):
        self.write_both()
        validate_lcov(self.logic)
        validate_cobertura(self.app)

    def test_missing_swiftpm_report_fails(self):
        self.app.write_text(XML, encoding="utf-8")
        with self.assertRaises(CoverageReportError):
            validate_lcov(self.logic)

    def test_missing_app_report_fails(self):
        self.logic.write_text(LCOV, encoding="utf-8")
        with self.assertRaises(CoverageReportError):
            validate_cobertura(self.app)

    def test_empty_or_incomplete_lcov_fails(self):
        self.logic.write_text("TN:\nSF:MeetingBar/foo.swift\nend_of_record\n", encoding="utf-8")
        with self.assertRaises(CoverageReportError):
            validate_lcov(self.logic)

    def test_malformed_or_empty_cobertura_fails(self):
        self.app.write_text("<coverage", encoding="utf-8")
        with self.assertRaises(CoverageReportError):
            validate_cobertura(self.app)
        self.app.write_text('<coverage lines-valid="0" lines-covered="0"/>', encoding="utf-8")
        with self.assertRaises(CoverageReportError):
            validate_cobertura(self.app)


class CoverageScopeTests(unittest.TestCase):
    def test_logic_gate_tracks_swiftpm_flag(self):
        package = (ROOT / "Package.swift").read_text(encoding="utf-8")
        source_block = re.search(r"sources:\s*\[(.*?)\]", package, re.S)
        self.assertIsNotNone(source_block)
        self.assertTrue(re.findall(r'"[^"]+\.swift"', source_block.group(1)))
        config = (ROOT / "codecov.yml").read_text(encoding="utf-8")
        logic_gate = config.split("      domain_logic:", 1)[1].split("      app_workflows:", 1)[0]
        self.assertIn("flags:\n          - swiftpm_logic", logic_gate)
        self.assertIn("target: 85%", logic_gate)
        self.assertIn("threshold: 0%", logic_gate)

    def test_app_workflows_cover_testable_orchestration_not_platform_adapters(self):
        config = (ROOT / "codecov.yml").read_text(encoding="utf-8")
        scope = config.split("      app_workflows:", 1)[1].split("      app_integration:", 1)[0]
        self.assertIn("flags:\n          - app_hosted", scope)
        for path in (
            "MeetingBar/Calendar/CalendarRepository.swift",
            "MeetingBar/Calendar/CalendarSync.swift",
            "MeetingBar/Notifications/NotificationScheduler.swift",
            "MeetingBar/Meetings/MeetingOpener.swift",
        ):
            self.assertIn(path, scope)
        for system_file in (
            "MeetingBar/Calendar/Providers/EventKit/EventKitEventStore.swift",
            "MeetingBar/Calendar/Providers/Google/GoogleCalendarEventStore.swift",
            "MeetingBar/Preferences/CalendarsTab.swift",
        ):
            self.assertNotIn(system_file, scope)
        self.assertNotIn("\nignore:", config)

    def test_system_boundaries_are_in_informational_reports(self):
        config = (ROOT / "codecov.yml").read_text(encoding="utf-8")
        integration = config.split("      app_integration:", 1)[1]
        self.assertIn("informational: true", integration)
        self.assertIn("          - app_hosted", integration)
        all_app = config.split("    patch:", 1)[1].split("      domain_logic:", 1)[0]
        self.assertIn("informational: true", all_app)


if __name__ == "__main__":
    unittest.main()
