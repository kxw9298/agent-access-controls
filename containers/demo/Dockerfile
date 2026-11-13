# syntax=docker/dockerfile:1
#
# Runs the approval-binding demonstration and its no-control baseline in a
# container and writes results.json to /results, so a reviewer needs only Docker. The demo needs no network and no
# cloud account; the container is run with --network none to show that.
#
# Build from the repository root:
#   docker build -t agent-access-controls-demo -f containers/demo/Dockerfile .
ARG OPA_VERSION=1.4.2
ARG TERRAFORM_VERSION=1.9.8

FROM openpolicyagent/opa:${OPA_VERSION}-static AS opa
FROM hashicorp/terraform:${TERRAFORM_VERSION} AS terraform

FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends bash jq ca-certificates coreutils \
 && rm -rf /var/lib/apt/lists/*
COPY --from=opa /opa /usr/local/bin/opa
COPY --from=terraform /bin/terraform /usr/local/bin/terraform

# Recorded in results.json as the tested commit. Pass it at build time:
#   --build-arg SOURCE_COMMIT=$(git rev-parse HEAD)
ARG SOURCE_COMMIT=unknown
ENV SOURCE_COMMIT=${SOURCE_COMMIT} RESULTS_DIR=/results

WORKDIR /repo
COPY policies policies
COPY examples examples
COPY scripts scripts
RUN useradd --create-home demo && mkdir /results && chown -R demo /repo /results
USER demo

CMD ["scripts/run_evaluation.sh"]
