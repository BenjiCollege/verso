#!/bin/bash
#
# What the tests actually cover.
#
# `xcrun xccov` cannot answer this. It reports per Xcode target, and the whole
# app is a Swift package — which is not one. Ask it, and it describes the two
# `@main` files and calls that the coverage of the project.
#
# The instrumentation was never the problem: `gatherCoverageData: true` in the
# scheme produces a perfectly good `Coverage.profdata` covering every line of
# VersoKit. Only the reporting was missing. This reads that profile directly
# with `llvm-cov`, against the package's built framework.
#
#   scripts/coverage.sh [path/to/DerivedData]
#
# With no argument it finds the most recent Verso DerivedData directory. Run a
# test build first, or there is nothing to read.

set -euo pipefail

DERIVED="${1:-$(ls -dt "$HOME"/Library/Developer/Xcode/DerivedData/Verso-* 2>/dev/null | head -1)}"

if [ -z "$DERIVED" ] || [ ! -d "$DERIVED" ]; then
    echo "error: no DerivedData for Verso. Run the tests first:" >&2
    echo "  xcodebuild test -project Verso.xcodeproj -scheme Verso -destination '<sim>'" >&2
    exit 1
fi

# Newest profile, because a run per simulator leaves one directory each.
PROFDATA=$(find "$DERIVED/Build/ProfileData" -name "Coverage.profdata" 2>/dev/null \
    | xargs -r ls -t 2>/dev/null | head -1)

if [ -z "$PROFDATA" ]; then
    echo "error: no Coverage.profdata under $DERIVED." >&2
    echo "The scheme gathers coverage; a build that skipped testing does not." >&2
    exit 1
fi

# The product name carries a build-specific hash, so it is matched rather than
# spelled out — hard-coding it would break on the next clean build.
FRAMEWORK=$(find "$DERIVED/Build/Products" -type d -name "VersoKit*PackageProduct.framework" 2>/dev/null | head -1)

if [ -z "$FRAMEWORK" ]; then
    echo "error: VersoKit framework not found under $DERIVED/Build/Products." >&2
    exit 1
fi

BINARY="$FRAMEWORK/$(basename "$FRAMEWORK" .framework)"

if [ ! -f "$BINARY" ]; then
    echo "error: no executable inside $FRAMEWORK." >&2
    exit 1
fi

echo "profile:   $PROFDATA"
echo "binary:    $BINARY"
echo

# Per area rather than per file: 164 files is a list nobody reads, and the
# question this answers is "which part of the engine is untested".
xcrun llvm-cov export "$BINARY" -instr-profile "$PROFDATA" -summary-only 2>/dev/null \
    | python3 -c '
import json, sys, collections

report = json.load(sys.stdin)
areas = collections.defaultdict(lambda: [0, 0])
total = [0, 0]

for entry in report["data"][0]["files"]:
    path = entry["filename"]
    if "/Sources/VersoKit/" not in path:
        continue
    relative = path.split("/Sources/VersoKit/")[1]
    parts = relative.split("/")
    area = "/".join(parts[:2]) if len(parts) > 1 else relative
    lines = entry["summary"]["lines"]
    areas[area][0] += lines["covered"]
    areas[area][1] += lines["count"]
    total[0] += lines["covered"]
    total[1] += lines["count"]

print("area".ljust(36) + "lines".rjust(8) + "covered".rjust(9))
print("-" * 58)
for area, (covered, count) in sorted(areas.items(), key=lambda kv: kv[1][0] / max(kv[1][1], 1)):
    print(f"{area:<36}{count:>8}{100 * covered / max(count, 1):>8.1f}%")
print("-" * 58)
label = "VersoKit"
print(f"{label:<36}{total[1]:>8}{100 * total[0] / max(total[1], 1):>8.1f}%")
'
