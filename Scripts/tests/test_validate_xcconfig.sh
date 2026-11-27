#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
validator="$script_dir/validate_xcconfig.sh"

export CI=true
export GOOGLE_CLIENT_NUMBER=123456789
export GOOGLE_CLIENT_SECRET=test-secret
export GOOGLE_AUTH_KEYCHAIN_NAME=meetingbar-test

bash "$validator"

assert_rejected() {
    local key="$1"
    local output
    if output="$(bash "$validator" 2>&1)"; then
        echo "Expected invalid configuration for $key to fail" >&2
        exit 1
    fi
    if [[ "$output" != *"$key"* || "$output" == *"test-secret"* ]]; then
        echo "Expected a useful error without disclosing credentials for $key" >&2
        exit 1
    fi
}

for key in GOOGLE_CLIENT_NUMBER GOOGLE_CLIENT_SECRET GOOGLE_AUTH_KEYCHAIN_NAME; do
    (
        unset "$key"
        assert_rejected "$key"
    )
    (
        printf -v "$key" '%s' '   '
        export "$key"
        assert_rejected "$key"
    )
    (
        printf -v "$key" '%s' '$('"$key"')'
        export "$key"
        assert_rejected "$key"
    )
done

echo "xcconfig validation tests passed"
