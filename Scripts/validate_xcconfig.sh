#!/usr/bin/env bash
# Called as an Xcode Run Script phase: custom build settings are supplied as environment variables.
set -euo pipefail

invalid=0
for key in GOOGLE_CLIENT_NUMBER GOOGLE_CLIENT_SECRET GOOGLE_AUTH_KEYCHAIN_NAME; do
    value="${!key-}"
    if [[ -z "${value//[[:space:]]/}" || "$value" == *'$('* ]]; then
        printf 'error: Missing or unresolved Xcode build setting %s.\n' "$key" >&2
        invalid=1
    elif [[ "$value" == REPLACE_BY_YOUR_* && "${CI:-}" != "true" ]]; then
        printf 'warning: %s is a placeholder; Google Calendar sign-in will not work.\n' "$key" >&2
    fi
done

if (( invalid != 0 )); then
    echo 'error: Check Project-Debug/Release.xcconfig Base Configuration and XCConfig/Project.xcconfig.' >&2
    exit 1
fi
