PROJECT := MeetingBar.xcodeproj
SCHEME := MeetingBar
XCODEBUILD ?= xcodebuild
SWIFT ?= swift
SWIFTLINT ?= swiftlint
BUILD_DIR ?= build
COVERAGE_DIR := $(BUILD_DIR)/coverage
XCODE_RESULT_BUNDLE := $(COVERAGE_DIR)/MeetingBar.xcresult
LOGIC_COVERAGE_SOURCES := MeetingBar/Core/Policies

# Pipe xcodebuild through xcbeautify when available; otherwise grep for the lines that matter.
XCFILTER := $(shell command -v xcbeautify >/dev/null 2>&1 && echo 'xcbeautify --quiet --renderer terminal' || echo "grep -E '(error:|warning:|FAIL|PASS|\\*\\* )'")

.PHONY: build build-quiet build-release test test-quiet test-logic test-logic-quiet coverage coverage-report coverage-logic-report coverage-app-report lint lint-fix open validate-strings

build:
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Debug build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO

build-quiet:
	@set -o pipefail; $(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Debug build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO 2>&1 | $(XCFILTER)

build-release:
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Release build

test: test-logic
	@mkdir -p $(COVERAGE_DIR)
	@rm -rf $(XCODE_RESULT_BUNDLE)
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -enableCodeCoverage YES -resultBundlePath $(XCODE_RESULT_BUNDLE) build test CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
	@$(MAKE) --no-print-directory coverage-app-report

test-quiet: test-logic-quiet
	@mkdir -p $(COVERAGE_DIR)
	@rm -rf $(XCODE_RESULT_BUNDLE)
	@set -o pipefail; $(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -enableCodeCoverage YES -resultBundlePath $(XCODE_RESULT_BUNDLE) build test CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO 2>&1 | $(XCFILTER)
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
