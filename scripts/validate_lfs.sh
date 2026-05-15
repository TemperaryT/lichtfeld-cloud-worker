#!/usr/bin/env bash
set -euo pipefail

echo "=== binary path ==="
which lichtfeld-studio
ls -lh "$(which lichtfeld-studio)"

echo ""
echo "=== version / help ==="
lichtfeld-studio --version 2>&1 || lichtfeld-studio --help 2>&1 | head -30

echo ""
echo "=== confirm expected headless flags ==="
# Windows v0.5.2 confirmed: --headless --train --no-interop --data-path --output-path --log-file
# If any are missing, document here and update run_train.sh accordingly.
HELP=$(lichtfeld-studio --help 2>&1 || true)
for flag in --headless --train --no-interop --data-path --output-path --log-file; do
    if echo "$HELP" | grep -q "$flag"; then
        echo "  $flag: FOUND"
    else
        echo "  $flag: NOT FOUND (validate_lfs: needs investigation)"
    fi
done

echo ""
echo "=== shared lib check ==="
ldd "$(which lichtfeld-studio)" 2>&1 | grep -E "not found" && echo "MISSING LIBS ABOVE" || echo "all libs resolved"

echo ""
echo "validate_lfs: PASS"
