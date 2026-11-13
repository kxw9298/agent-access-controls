#!/usr/bin/env bash
# Stage 2 of the image path: show a real Kubernetes API server enforcing the
# digests the policy published.
#
# Needs a cluster reachable with kubectl (Kubernetes 1.30 or later) and the
# ConfigMap written by scripts/demo_image_admission.sh. Admission is checked
# with server-side dry run, so no image is pulled and no pod is started.
# The digests are fixed examples that identify no real image.
#
# This runs in CI against a kind cluster. It has not been run against a managed
# cluster or against any other admission setup.
#
# Usage: scripts/demo_image_admission_cluster.sh <approved-images.yaml>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/portable.sh
. "$ROOT/scripts/lib/portable.sh"
require_tools kubectl jq

CONFIGMAP="${1:?usage: $0 <approved-images.yaml>}"
NS=agent-managed
APPROVED="sha256:3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855a"
OTHER="sha256:9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
REPO="registry.example/team/app"

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl label namespace "$NS" agent-managed=true --overwrite >/dev/null
kubectl apply -f "$ROOT/examples/image_admission/admission-policy.yaml" >/dev/null
kubectl apply -f "$CONFIGMAP" >/dev/null

# The policy takes a moment to start enforcing. Wait until a pod that must be
# refused is refused, instead of sleeping for a fixed time.
pod_yaml() { # pod_yaml <image> [init-image]
  cat <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: demo
  namespace: $NS
spec:
  containers:
    - name: app
      image: $1
YAML
  if [ -n "${2:-}" ]; then
    printf '  initContainers:\n    - name: init\n      image: %s\n' "$2"
  fi
}

# Prints "admitted", "refused: <message>" when this policy refused the pod, or
# "error: <message>" for any other failure, which must not count as a refusal.
admit() {
  local out
  if out="$(pod_yaml "$@" | kubectl apply --dry-run=server -f - 2>&1)"; then
    echo admitted
  elif grep -q approved-image-digests <<<"$out"; then
    echo "refused: $(tail -1 <<<"$out")"
  else
    echo "error: $(tail -1 <<<"$out")"
  fi
}

ready=false
for _ in $(seq 1 60); do
  case "$(admit "$REPO:latest")" in refused:*) ready=true; break ;; esac
  sleep 2
done
$ready || { echo "admission policy did not start enforcing; last result: $(admit "$REPO:latest")" >&2; exit 1; }

failures=0
check() { # check <id> <expected admitted|refused> <image> [init-image]
  local id="$1" expected="$2" result observed
  shift 2
  result="$(admit "$@")"
  observed="${result%%:*}"
  printf '%-24s %-9s %-9s %s\n' "$id" "$expected" "$observed" "${result#*: }"
  [ "$observed" = "$expected" ] || { echo "  UNEXPECTED: $id" >&2; failures=$((failures+1)); }
}

printf '%-24s %-9s %-9s %s\n' scenario expected observed message
check approved-digest        admitted "$REPO@$APPROVED"
check unapproved-digest      refused  "$REPO@$OTHER"
check tag-only               refused  "$REPO:latest"
check versioned-tag          refused  "$REPO:1.0"
check init-container-other   refused  "$REPO@$APPROVED" "$REPO@$OTHER"

# A missing ConfigMap must refuse, not admit.
kubectl -n "$NS" delete configmap approved-images >/dev/null
for _ in $(seq 1 30); do
  case "$(admit "$REPO@$APPROVED")" in refused:*) break ;; esac
  sleep 1
done
check no-approved-list       refused  "$REPO@$APPROVED"
kubectl apply -f "$CONFIGMAP" >/dev/null

if [ "$failures" -ne 0 ]; then
  echo "$failures scenario(s) did not behave as expected" >&2
  exit 1
fi
echo "All 6 cluster scenarios behaved as expected."
