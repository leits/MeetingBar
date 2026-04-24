PROJECT := MeetingBar.xcodeproj
SCHEME := MeetingBar
XCODEBUILD ?= xcodebuild
SWIFTLINT ?= swiftlint

.PHONY: build build-release test lint lint-fix open

build:
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Debug build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO

build-release:
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Release build

test:
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -enableCodeCoverage YES build test CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO

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
