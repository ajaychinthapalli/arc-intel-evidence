# 5. Compliance remediation through Git

## Starting point: 78 (B), `non_compliant`

Expected before adoption ([01/04](../evidence/01-aws-and-generate/04-generated-values-review.log)), confirmed
by `verify` ([06/01](../evidence/06-verify-and-agent/01-verify.log)) and by the agent
([06/03](../evidence/06-verify-and-agent/03-agent-first-answer-a2a.log)). All four violations had origin
`source_of_truth`: the adopted Helm values themselves broke policy, so the fix belonged in Git.

| Rule | Severity | Finding | Score impact |
|---|---|---|---|
| ARC-005 | high | Runner image `ghcr.io/actions/actions-runner:latest`, unpinned | −10 |
| ARC-010 | medium | No `limits.cpu` on the runner | −5 |
| ARC-011 | medium | `allowPrivilegeEscalation` not `false` | −5 |
| ARC-013 | low | Missing `owner` / `cost-center` labels | −2 |
| | | **Score** | **100 − 22 = 78 (B)** |

Adoption was kept change-free on purpose: the first sync carried only tracking annotations, and the fixes
came afterwards as a separate, reviewable PR.

## The change: PR #3

[ajaychinthapalli/arc-intel#3](https://github.com/ajaychinthapalli/arc-intel/pull/3), "arc-runner-set: fix
ARC-005/010/011/013", commit `8a3c206`, merged as `2207959`. File:
`clusters/[REDACTED_CLUSTER_NAME]/runner-scale-sets/arc-runner-set/values.yaml` (13 insertions, 6 deletions).

```yaml
labels:                                   # ARC-013
  owner: ajaychinthapalli
  cost-center: sandbox
template:
  spec:
    containers:
      - name: runner
        image: ghcr.io/actions/actions-runner:2.338.0   # ARC-005 (latest release via gh api)
        resources:
          limits:
            cpu: "1"                      # ARC-010
            memory: 2Gi
        securityContext:
          allowPrivilegeEscalation: false # ARC-011
```

## Review: `argocd app diff` before sync

The diff contained exactly the PR and nothing else:
- labels `cost-center`/`owner` on the ServiceAccount, Role, RoleBinding and AutoscalingRunnerSet;
- `image: …:latest` → `…:2.338.0`;
- `cpu: "1"` limit;
- `securityContext.allowPrivilegeEscalation: false`;
- a new chart `values-hash` annotation.

## Apply and rescore

- `argocd app sync arc-runners-arc-runner-set` at 19:08:32, revision `2207959`, succeeded in 0 s.
- After the next 5-minute scan, the agent reported:

> **Fleet Grade: A (Score: 100/100)** … `arc-runners/arc-runner-set` | A | healthy | 100 … No top risks, no drift, no compliance violations.

Evidence: [07/01](../evidence/07-compliance-remediation/01-pr3-sync-and-grade-a.log)

## What this proves

The full change path on the diagram: **detect** (arc-intel), **explain** (agent), **change** (Git PR with
review), **apply** (Argo CD), **verify** (arc-intel rescore). No `kubectl` or `helm` was used to change ARC.

## Remaining hardening (not scored as violations today)

- Pin the runner image by digest (`@sha256:…`) as well as by tag.
- Tighten the runner egress NetworkPolicy (it currently allows all egress so runners keep working).
