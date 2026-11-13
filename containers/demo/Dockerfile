# syntax=docker/dockerfile:1
#
# Runs the approval-binding demonstration and its no-control baseline in a
# container, so a reviewer needs only Docker. The demo needs no network and no
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

WORKDIR /repo
COPY policies policies
COPY examples examples
COPY scripts scripts
RUN useradd --create-home demo && chown -R demo /repo
USER demo

CMD ["bash", "-c", "scripts/demo_baseline_no_binding.sh && echo && scripts/demo_approval_binding.sh"]
