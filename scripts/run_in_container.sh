#!/usr/bin/env bash
# Build the demo image, run the baseline and the approval-binding
# demonstration inside it, and copy results.json to ./results/ (or $RESULTS_DIR).
# Needs only Docker (Linux or Docker Desktop on macOS).
# Arguments, if any, replace the default command, for example:
#   scripts/run_in_container.sh scripts/demo_approval_binding.sh
# Exit status is the container's: non-zero if any case did not behave as expected.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="agent-access-controls-demo"
CONTAINER="aac-demo-$$"
OUT="${RESULTS_DIR:-$ROOT/results}"

command -v docker >/dev/null 2>&1 || { echo "missing required tool: docker" >&2; exit 2; }

COMMIT="${SOURCE_COMMIT:-$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)}"
docker build -q -t "$IMAGE" --build-arg "SOURCE_COMMIT=$COMMIT" \
  -f "$ROOT/containers/demo/Dockerfile" "$ROOT" >/dev/null

status=0
docker run --name "$CONTAINER" --network none "$IMAGE" "$@" || status=$?
mkdir -p "$OUT"
docker cp "$CONTAINER:/results/." "$OUT/" >/dev/null 2>&1 || echo "no results were produced" >&2
docker rm -f "$CONTAINER" >/dev/null
exit "$status"
