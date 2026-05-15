#!/usr/bin/env bash
# LFS binary validation — called by run/validate.sh, output goes to logs/validate.log.
set -euo pipefail

# Print version to confirm Linux build matches Windows v0.5.2 baseline
VERSION=$(lichtfeld-studio --version 2>&1 || lichtfeld-studio --help 2>&1 | head -1)
echo "LFS=$VERSION"

# Confirm expected headless flags — if any missing, note for run_train.sh update
HELP=$(lichtfeld-studio --help 2>&1 || true)
MISSING=""
for flag in --headless --train --no-interop --data-path --output-path --log-file; do
    echo "$HELP" | grep -q "$flag" || MISSING="$MISSING $flag"
done
[[ -n "$MISSING" ]] && echo "flags_missing=$MISSING"

# Shared lib check — missing libs surface here before a real run
ldd "$(which lichtfeld-studio)" 2>&1 | grep "not found" && { echo "missing_libs=see above"; exit 1; } || true
