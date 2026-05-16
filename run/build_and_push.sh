#!/usr/bin/env bash
# Trigger the GHA build-and-push workflow and follow it to completion.
# First build: ~60-90 min. Cached re-builds: ~15-30 min.
#
# Usage:
#   bash run/build_and_push.sh             # builds tag v0.5.2 (default)
#   bash run/build_and_push.sh v0.5.3      # builds a different tag
#
# After the first successful run, make the GHCR package public ONCE:
#   gh api -X PATCH /user/packages/container/lichtfeld-cloud-worker/visibility \
#       -f visibility=public
set -euo pipefail

TAG="${1:-v0.5.2}"

# gh infers the target repo from cwd's git context. cd into the repo root so
# the script works regardless of where the user runs it from.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

command -v gh >/dev/null || { echo "gh CLI not installed" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh not authenticated — run 'gh auth login'" >&2; exit 1; }

echo "triggering build-and-push workflow with tag=$TAG (repo: $REPO_ROOT)"
gh workflow run build-and-push.yml -f tag="$TAG"

# Give the API a beat to register the new run, then follow the latest one
sleep 3
echo "following latest run (Ctrl-C to stop watching; build continues in background)"
gh run watch --exit-status
