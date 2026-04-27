#!/bin/bash
#
# validate_localizations.sh
#
# Fails if any localization key referenced via `"key".loco(...)` in Swift
# source is not defined in the English source strings file. Other locales
# are allowed to lag behind English (they are managed via Weblate).
#
# Optional: set VERBOSE=1 to also list defined-but-unused English keys.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="$ROOT/MeetingBar"
EN_STRINGS="$ROOT/MeetingBar/Resources /Localization /en.lproj/Localizable.strings"

if [ ! -f "$EN_STRINGS" ]; then
    echo "ERROR: English strings file not found at:"
    echo "  $EN_STRINGS"
    exit 2
fi

# Keys referenced in source via "<key>".loco(...).
used_keys=$(grep -rhoE '"[a-zA-Z0-9_]+"\.loco\b' "$SOURCE_DIR" --include="*.swift" \
    | sed -E 's/^"([^"]+)"\.loco$/\1/' \
    | sort -u)

# Keys defined in en.lproj/Localizable.strings (lines like: "key" = "value";).
defined_keys=$(grep -E '^"[^"]+"[[:space:]]*=' "$EN_STRINGS" \
    | sed -E 's/^"([^"]+)".*/\1/' \
    | sort -u)

missing=$(comm -23 <(echo "$used_keys") <(echo "$defined_keys"))

if [ -n "$missing" ]; then
    echo "ERROR: localization keys used in source but missing from English strings:"
    echo "$missing" | sed 's/^/  /'
    echo
    echo "Add the missing keys to:"
    echo "  $EN_STRINGS"
    exit 1
fi

if [ "${VERBOSE:-0}" = "1" ]; then
    unused=$(comm -13 <(echo "$used_keys") <(echo "$defined_keys"))
    if [ -n "$unused" ]; then
        echo "Defined but unused English keys (informational, not an error):"
        echo "$unused" | sed 's/^/  /'
        echo
    fi
fi

used_count=$(echo "$used_keys" | grep -c .)
defined_count=$(echo "$defined_keys" | grep -c .)
echo "OK: $used_count used keys all defined in English ($defined_count total defined)."
