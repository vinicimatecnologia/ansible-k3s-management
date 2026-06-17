#!/usr/bin/env bash
# Wrapper used by the systemd unit on the Solid NAS to cd into the repo
# and run a make target. Kept symmetric with the jellyfin lifecycle wrapper.
#
# Usage: wrap.sh <make-target>   (e.g. wrap.sh cordon-drain)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_DIR"

exec make "$@"
