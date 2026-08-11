#!/bin/bash
#
# Fails the build if a binary was signed without an entitlement it needs.
#
# This exists because the failure it catches is completely silent. Archiving
# with CODE_SIGNING_ALLOWED=NO succeeds, export re-signs the result, and the
# .ipa uploads and installs — but CODE_SIGN_ENTITLEMENTS is a *build setting*,
# and a build that skipped signing never processed it. The archive carries no
# entitlements, so export signs with only the four the profile implies:
# application-identifier, team-identifier, get-task-allow, beta-reports-active.
#
# For Verso that would mean App Groups and iCloud quietly absent. The app would
# look fine. The widget would show no notes and sync would never happen, with
# nothing anywhere saying why — App Store validation only checks entitlements
# that a *declared capability* requires, and neither of those triggers one.
#
# Usage:
#   verify-entitlements.sh <path-to-.app-or-.appex> <required-key>...

set -euo pipefail

BUNDLE="${1:?usage: verify-entitlements.sh <bundle> <required-key>...}"
shift
REQUIRED=("$@")

if [[ ! -d "$BUNDLE" ]]; then
    echo "::error::No bundle at $BUNDLE"
    exit 1
fi

echo "▸ Entitlements actually signed into $(basename "$BUNDLE")"

# `codesign -d --entitlements -` reads what is in the signature, not what the
# project asked for. That distinction is the entire point of this script.
ENTITLEMENTS=$(codesign -d --entitlements - --xml "$BUNDLE" 2>/dev/null | plutil -convert xml1 -o - - || true)

if [[ -z "$ENTITLEMENTS" ]]; then
    echo "::error::$(basename "$BUNDLE") carries no entitlements at all."
    echo "::error::That is what archiving with signing disabled looks like."
    exit 1
fi

echo "$ENTITLEMENTS"

MISSING=()
for key in "${REQUIRED[@]}"; do
    if grep -q "<key>${key}</key>" <<<"$ENTITLEMENTS"; then
        echo "  ✓ $key"
    else
        echo "  ✗ $key"
        MISSING+=("$key")
    fi
done

if (( ${#MISSING[@]} > 0 )); then
    echo "::error::$(basename "$BUNDLE") is missing ${#MISSING[@]} required entitlement(s): ${MISSING[*]}"
    echo "::error::Check that (a) archiving did not disable code signing, and"
    echo "::error::(b) every capability in the entitlements file is enabled on the App ID."
    exit 1
fi

echo "▸ All ${#REQUIRED[@]} required entitlements present."
