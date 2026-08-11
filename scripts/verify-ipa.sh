#!/bin/bash
#
# Checks the thing that actually ships.
#
# The archive can be right and the .ipa still wrong — export re-signs, and it
# re-signs against the provisioning profile it chose. So this unpacks the .ipa
# and compares two independent sources of truth:
#
#   1. what the binary carries   — codesign, via verify-entitlements.sh
#   2. what the profile grants   — embedded.mobileprovision
#
# A key present in the first but absent from the second means the profile was
# issued before the capability was enabled on the App ID, and the entitlement
# will be ignored at runtime rather than rejected at upload.
#
# The provisioning profile is a CMS envelope, but the plist inside it is plain
# text, so `security cms -D` reads it without needing the signing certificate.
#
# Usage:
#   verify-ipa.sh <path-to-.ipa> <required-key>...

set -euo pipefail

IPA="${1:?usage: verify-ipa.sh <ipa> <required-key>...}"
shift
REQUIRED=("$@")

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "▸ Unpacking $(basename "$IPA")"
unzip -q "$IPA" -d "$WORK"

APP=$(find "$WORK/Payload" -maxdepth 1 -name "*.app" | head -1)
if [[ -z "$APP" ]]; then
    echo "::error::No .app inside the .ipa"
    exit 1
fi

# The app itself.
"$HERE/verify-entitlements.sh" "$APP" "${REQUIRED[@]}"

# Every extension it embeds. A widget missing App Groups reads an empty store
# and shows nothing, which looks like "no notes yet" rather than a bug.
shopt -s nullglob
for appex in "$APP"/PlugIns/*.appex; do
    echo
    "$HERE/verify-entitlements.sh" "$appex" \
        com.apple.security.application-groups \
        com.apple.developer.icloud-container-identifiers
done
shopt -u nullglob

echo
echo "▸ What the embedded profile grants"

PROFILE="$APP/embedded.mobileprovision"
if [[ ! -f "$PROFILE" ]]; then
    echo "::error::No embedded.mobileprovision — the app is not provisioned."
    exit 1
fi

PLIST="$WORK/profile.plist"
security cms -D -i "$PROFILE" > "$PLIST"

echo "  Name:       $(/usr/libexec/PlistBuddy -c 'Print :Name' "$PLIST" 2>/dev/null || echo '?')"
echo "  Team:       $(/usr/libexec/PlistBuddy -c 'Print :TeamName' "$PLIST" 2>/dev/null || echo '?')"
echo "  Expires:    $(/usr/libexec/PlistBuddy -c 'Print :ExpirationDate' "$PLIST" 2>/dev/null || echo '?')"

GRANTED=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements' "$PLIST" 2>/dev/null || echo "")

MISSING=()
for key in "${REQUIRED[@]}"; do
    if grep -q "$key" <<<"$GRANTED"; then
        echo "  ✓ profile grants $key"
    else
        echo "  ✗ profile does NOT grant $key"
        MISSING+=("$key")
    fi
done

if (( ${#MISSING[@]} > 0 )); then
    echo "::error::The profile is missing ${#MISSING[*]}."
    echo "::error::Enable the capability on the App ID in the developer portal."
    echo "::error::A binary can carry an entitlement its profile does not grant —"
    echo "::error::iOS then ignores it silently at runtime."
    exit 1
fi

echo
echo "▸ Binary and profile agree."
