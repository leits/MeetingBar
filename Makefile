PROJECT := MeetingBar.xcodeproj
SCHEME := MeetingBar
XCODEBUILD ?= xcodebuild
SWIFT ?= swift
SWIFTLINT ?= swiftlint
BUILD_DIR ?= build
COVERAGE_DIR := $(BUILD_DIR)/coverage
XCODE_RESULT_BUNDLE := $(COVERAGE_DIR)/MeetingBar.xcresult
DERIVED_DATA_DIR := $(BUILD_DIR)/DerivedData
XCODE_SOURCE_PACKAGES_DIR := $(BUILD_DIR)/SourcePackages
HOST_ARCH := $(shell uname -m)
DESTINATION ?= platform=macOS,arch=$(HOST_ARCH)
XCODEBUILD_FLAGS := -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA_DIR) -clonedSourcePackagesDirPath $(XCODE_SOURCE_PACKAGES_DIR) -onlyUsePackageVersionsFromResolvedFile
LOCAL_CODESIGN_FLAGS := CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
LOGIC_COVERAGE_SOURCES := MeetingBar/Calendar MeetingBar/Meetings MeetingBar/Notifications MeetingBar/UI/StatusBar MeetingBar/Utilities/Diagnostics

# Pipe xcodebuild through xcbeautify when available; otherwise grep for the lines that matter.
XCFILTER := $(shell command -v xcbeautify >/dev/null 2>&1 && echo 'xcbeautify --quiet --renderer terminal' || echo "grep -E '(error:|warning:|FAIL|PASS|\\*\\* )'")

.PHONY: build build-quiet build-release test test-quiet test-app test-app-quiet test-logic test-logic-quiet coverage coverage-report coverage-logic-report coverage-app-report coverage-gate test-summary lint lint-fix open validate-strings

build:
	@mkdir -p $(BUILD_DIR)
	$(XCODEBUILD) $(XCODEBUILD_FLAGS) -configuration Debug build $(LOCAL_CODESIGN_FLAGS)

build-quiet:
	@mkdir -p $(BUILD_DIR)
	@set -o pipefail; $(XCODEBUILD) $(XCODEBUILD_FLAGS) -configuration Debug build $(LOCAL_CODESIGN_FLAGS) 2>&1 | $(XCFILTER)

build-release:
	@mkdir -p $(BUILD_DIR)
	$(XCODEBUILD) $(XCODEBUILD_FLAGS) -configuration Release build

test: test-logic test-app

test-quiet: test-logic-quiet test-app-quiet

test-app:
	@mkdir -p $(COVERAGE_DIR)
	@rm -rf $(XCODE_RESULT_BUNDLE)
	$(XCODEBUILD) $(XCODEBUILD_FLAGS) -configuration Debug -enableCodeCoverage YES -resultBundlePath $(XCODE_RESULT_BUNDLE) build test $(LOCAL_CODESIGN_FLAGS)
	@$(MAKE) --no-print-directory coverage-app-report

test-app-quiet:
	@mkdir -p $(COVERAGE_DIR)
	@rm -rf $(XCODE_RESULT_BUNDLE)
	@set -o pipefail; $(XCODEBUILD) $(XCODEBUILD_FLAGS) -configuration Debug -enableCodeCoverage YES -resultBundlePath $(XCODE_RESULT_BUNDLE) build test $(LOCAL_CODESIGN_FLAGS) 2>&1 | $(XCFILTER)
	@$(MAKE) --no-print-directory coverage-app-report

test-logic:
	$(SWIFT) test --enable-code-coverage
	@$(MAKE) --no-print-directory coverage-logic-report

test-logic-quiet:
	$(SWIFT) test --enable-code-coverage --quiet
	@$(MAKE) --no-print-directory coverage-logic-report

coverage: test

coverage-report: coverage-logic-report coverage-app-report

coverage-logic-report:
	@PROFILE="$$(ls -d .build/*/debug/codecov/default.profdata .build/debug/codecov/default.profdata 2>/dev/null | head -n 1)" ; \
	TEST_BINARY="$$(ls -d .build/*/debug/MeetingBarLogicPackageTests.xctest/Contents/MacOS/MeetingBarLogicPackageTests .build/debug/MeetingBarLogicPackageTests.xctest/Contents/MacOS/MeetingBarLogicPackageTests 2>/dev/null | head -n 1)" ; \
	if [ ! -f "$$PROFILE" ] || [ ! -x "$$TEST_BINARY" ]; then \
		echo "SwiftPM coverage is unavailable. Run 'make test-logic' first."; \
		exit 1; \
	fi ; \
	echo "" ; \
	echo "SwiftPM hostless coverage (source files only):" ; \
	xcrun llvm-cov report "$$TEST_BINARY" -instr-profile "$$PROFILE" $(LOGIC_COVERAGE_SOURCES)

coverage-gate:
	@PROFILE="$$(ls -d .build/*/debug/codecov/default.profdata .build/debug/codecov/default.profdata 2>/dev/null | head -n 1)" ; \
	TEST_BINARY="$$(ls -d .build/*/debug/MeetingBarLogicPackageTests.xctest/Contents/MacOS/MeetingBarLogicPackageTests .build/debug/MeetingBarLogicPackageTests.xctest/Contents/MacOS/MeetingBarLogicPackageTests 2>/dev/null | head -n 1)" ; \
	if [ ! -f "$$PROFILE" ] || [ ! -x "$$TEST_BINARY" ]; then \
		echo "SwiftPM coverage data not found. Run 'make test-logic' first."; \
		exit 1; \
	fi ; \
	COVERAGE=$$(xcrun llvm-cov report "$$TEST_BINARY" -instr-profile "$$PROFILE" $(LOGIC_COVERAGE_SOURCES) 2>/dev/null | tail -1 | awk '{print $$4}' | tr -d '%') ; \
	echo "" ; \
	echo "Logic coverage gate (threshold: 90%):" ; \
	awk -v cov="$$COVERAGE" 'BEGIN { if (cov + 0 < 90.0) { print "  NOTE: " cov "% is below 90% target (gate is reporting-only)" } else { print "  PASS: " cov "% meets 90% target" } }'

coverage-app-report:
	@if [ ! -d "$(XCODE_RESULT_BUNDLE)" ]; then \
		echo "Xcode coverage is unavailable. Run 'make test' or 'make test-quiet' first."; \
		exit 1; \
	fi
	@echo ""
	@echo "Xcode app-hosted coverage (target summary):"
	@set -o pipefail; xcrun xccov view --report --only-targets $(XCODE_RESULT_BUNDLE) 2>/dev/null | awk 'NR <= 2 || /MeetingBar\.app/'

lint:
	@if command -v $(SWIFTLINT) >/dev/null 2>&1; then \
		$(SWIFTLINT); \
	else \
		echo "SwiftLint is not installed. Install it from https://github.com/realm/SwiftLint"; \
		exit 1; \
	fi

lint-fix:
	@if command -v $(SWIFTLINT) >/dev/null 2>&1; then \
		$(SWIFTLINT) --fix; \
		$(SWIFTLINT); \
	else \
		echo "SwiftLint is not installed. Install it from https://github.com/realm/SwiftLint"; \
		exit 1; \
	fi

open:
	open $(PROJECT)

validate-strings:
	@bash Scripts/validate_localizations.sh

test-summary:
	@bash Scripts/test_summary.sh $(XCODE_RESULT_BUNDLE)
