#!/usr/bin/env bash
# Build the demo image and run the baseline and the approval-binding
# demonstration inside it. Needs only Docker (Linux or Docker Desktop on macOS).
# Arguments, if any, replace the default command, for example:
#   scripts/run_in_container.sh scripts/demo_approval_binding.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="agent-access-controls-demo"

command -v docker >/dev/null 2>&1 || { echo "missing required tool: docker" >&2; exit 2; }

docker build -q -t "$IMAGE" -f "$ROOT/containers/demo/Dockerfile" "$ROOT" >/dev/null
docker run --rm --network none "$IMAGE" "$@"
