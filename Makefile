PROJECT := MeetingBar.xcodeproj
SCHEME := MeetingBar
XCODEBUILD ?= xcodebuild
SWIFT ?= swift
SWIFTLINT ?= swiftlint

.PHONY: build build-release test test-logic lint lint-fix open validate-strings

build:
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Debug build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO

build-release:
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Release build

test: test-logic
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -enableCodeCoverage YES build test CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO

test-logic:
	$(SWIFT) test --enable-code-coverage

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
