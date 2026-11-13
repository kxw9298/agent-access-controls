# Workload identity for the change path, from a GitHub Actions OIDC token.
#
# Supports control AAC-ID-01 on the change path: the agent and the user it
# acts for are taken from a token the CI system signed, not from values the
# agent supplies.
#
# Expected input:
#   {
#     "token":  "<GitHub Actions OIDC token (JWT)>",
#     "jwks":   "<JSON Web Key Set of the issuer, as a string>",
#     "now_ns": 1794225900000000000   # optional; defaults to the current time
#   }
#
# Expected data:
#   data.identity_policy = {
#     "issuer": "https://token.actions.githubusercontent.com",
#     "audience": "...",              # audience the pipeline requests
#     "repositories": ["owner/repo"]  # repositories allowed to run it
#   }
#
# The caller must fetch `jwks` from the issuer over TLS. This policy does
# not fetch keys itself.
package agentaccess.workload_identity

default verified := false

verified if count(deny_reasons) == 0

policy_loaded if {
	is_string(data.identity_policy.issuer)
	is_string(data.identity_policy.audience)
	is_array(data.identity_policy.repositories)
}

base_constraints := {
	"cert": input.jwks,
	"alg": "RS256",
	"iss": data.identity_policy.issuer,
	"aud": data.identity_policy.audience,
}

constraints := object.union(base_constraints, {"time": input.now_ns}) if {
	is_number(input.now_ns)
} else := base_constraints

# Signature, algorithm, issuer, audience, expiry, and not-before are all
# checked here. Any failure, including a malformed token, leaves this
# undefined.
claims := payload if {
	[valid, _, payload] := io.jwt.decode_verify(input.token, constraints)
	valid == true
}

token_valid if is_object(claims)

repository_allowed if claims.repository in data.identity_policy.repositories

nonempty_string(value) if {
	is_string(value)
	value != ""
}

agent_claim_present if nonempty_string(claims.workflow_ref)

actor_claim_present if nonempty_string(claims.actor)

deny_reasons contains "identity policy data is missing" if not policy_loaded

deny_reasons contains "token is missing, malformed, expired, or not signed by the issuer for this audience" if {
	not token_valid
}

deny_reasons contains "repository is not allowed to run this pipeline" if {
	token_valid
	not repository_allowed
}

deny_reasons contains "token has no workflow_ref claim" if {
	token_valid
	not agent_claim_present
}

deny_reasons contains "token has no actor claim" if {
	token_valid
	not actor_claim_present
}

# Verified identity. Claims are exposed only when every check passed.
#   agent        - the workflow acting, e.g. owner/repo/.github/workflows/x.yml@refs/heads/main
#   requested_by - the account that triggered the run
identity := {
	"verified": true,
	"agent": claims.workflow_ref,
	"requested_by": claims.actor,
	"repository": claims.repository,
	"ref": object.get(claims, "ref", null),
	"sha": object.get(claims, "sha", null),
	"run_id": object.get(claims, "run_id", null),
	"reasons": set(),
} if {
	verified
} else := {
	"verified": false,
	"reasons": deny_reasons,
}
