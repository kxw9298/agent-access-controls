# Image admission by approved digest (second interface)

**Status:** demonstrated in CI with a local policy stage and a kind cluster. Not production-ready. Signature and attestation verification are not implemented.

## The problem

An AI agent that can propose a deployment can also name the image to run. A person approves "the deployment", and a different image, or a mutable tag that now points to different content, ends up running. A tag such as `app:latest` can change after review. A digest (`app@sha256:...`) cannot, because it is the hash of the image content.

## What is built

Two stages, kept separate on purpose.

**Stage 1, the approval decision** ([`policies/image_admission`](../policies/image_admission/image_admission.rego)). An OPA policy that allows a deployment request only if:

- the image reference is pinned to a `sha256` digest;
- the digest equals the digest in the approval record;
- the agent and the user the agent acts for are the ones named in the approval;
- the approver is neither the requester nor the agent;
- the approval has not expired.

When it allows, it publishes the approved digest. When it denies, it publishes nothing.

**Stage 2, admission in the cluster** ([`examples/image_admission/admission-policy.yaml`](../examples/image_admission/admission-policy.yaml)). A built-in Kubernetes `ValidatingAdmissionPolicy` (Kubernetes 1.30 or later, no extra controller). In namespaces labeled `agent-managed=true`, it refuses any pod, including its init containers, whose images are not pinned by digest to a digest in the `approved-images` ConfigMap. A missing ConfigMap refuses.

Stage 2 does not trust stage 1 or the agent. Someone who skips the pipeline and runs `kubectl apply` directly is still checked against the published list.

## Run it

```sh
scripts/demo_image_admission.sh                    # stage 1; needs OPA and jq
scripts/demo_image_admission_cluster.sh results/image-admission/approved-images.yaml   # stage 2; needs a cluster
```

Stage 2 uses server-side dry run, so no image is pulled and no pod starts. CI runs both against a kind cluster in the `image-admission` job. The digests in the scripts are fixed examples that identify no real image.

## What the scenarios show

| Stage | Scenario | Result |
| --- | --- | --- |
| 1 | approved image | allowed; its digest is published |
| 1 | different digest than approved | denied |
| 1 | tag instead of digest | denied |
| 1 | different agent | denied |
| 1 | expired approval | denied |
| 1 | self-approval | denied |
| 1 | no approval | denied |
| 2 | approved digest | admitted |
| 2 | unapproved digest | refused |
| 2 | tag only, or a versioned tag | refused |
| 2 | approved main image, unapproved init container | refused |
| 2 | approved list missing | refused |

## What this does not show

- **Who built the image.** A digest proves the content is the content that was approved. It does not prove who built it, that it came from a trusted pipeline, or that it is free of vulnerabilities. Signing and attestation (cosign, in-toto, Kyverno `verifyImages`) are planned and not implemented. Do not read this page as a supply-chain provenance control.
- **How the approved list is written.** In the demonstration a script writes the ConfigMap from the policy decision. In a real setup, whoever can edit that ConfigMap, or the admission policy itself, can approve anything. Protecting them (RBAC, a controller that only the pipeline can use) is not built.
- **Ephemeral containers** added through the `pods/ephemeralcontainers` subresource are not covered.
- **Controllers.** The policy matches pods. A Deployment with a bad image is accepted, and its pods are refused.
- **Other clusters and products.** It has been run on a kind cluster in CI only, not on a managed cluster, and not with any other admission controller.
- **Policy-level stage 1.** The scenarios show what the policy decides for given inputs. They do not show how an agent would obtain or forge an approval in a real pipeline.
- **Comparison with existing tools.** I have not compared this against what Kyverno or other tools already do for digest pinning. Existing tools may cover part of stage 2; the intended contribution is the approval decision in stage 1 and how the two fit together, and that has not been independently assessed.
