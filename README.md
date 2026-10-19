# ARC Configuration Compliance & Drift Intelligence — Implementation Evidence

Record of the build and rollout of **arc-intel**: compliance scoring and drift intelligence for GitHub
Actions Runner Controller (ARC), driven by a Kagent agent, with **Argo CD as the source of truth** on the
existing Amazon EKS cluster `[REDACTED_CLUSTER_NAME]`.

This repository holds the evidence: what was done, in what order, terminal captures of every step,
every problem hit and how it was resolved, and the open follow-ups. The platform code itself lives in
[`ajaychinthapalli/arc-intel`](https://github.com/ajaychinthapalli/arc-intel).

## Outcome

| Objective | Result | Evidence |
|---|---|---|
| Adopt the running ARC Helm releases into Argo CD with no runtime change | Controller pod kept running (age 5d20h, 0 restarts); first diffs were tracking annotations only | [04-arc-adoption/01](evidence/04-arc-adoption/01-diagnostics-and-arc-controller-diff.log), [03](evidence/04-arc-adoption/03-controller-pod-age-and-arc-intel-podsecurity.log), [06](evidence/04-arc-adoption/06-runner-set-controller-sa-fix-and-diff.log) |
| Argo CD is the source of truth for drift | `baseline_source: argocd:arc-runners-arc-runner-set` | [06-verify-and-agent/01](evidence/06-verify-and-agent/01-verify.log) |
| Name who changed what | `identity_source: eks_audit_log`; IAM principal, source IP, client and time per write | [06/01](evidence/06-verify-and-agent/01-verify.log), [08/01](evidence/08-self-heal-and-drift-drill/01-pr4-and-first-drift-drill.log) |
| All platform apps healthy | 10/10 Argo CD applications Synced + Healthy | [06/01](evidence/06-verify-and-agent/01-verify.log) |
| Agent answers from live data | Kagent → Bedrock → arc-intel MCP tools → cluster, over A2A | [06/03](evidence/06-verify-and-agent/03-agent-first-answer-a2a.log) |
| Fix violations through Git | Score **78 (B) → 100 (A)** after PR #3 + Argo CD sync | [07/01](evidence/07-compliance-remediation/01-pr3-sync-and-grade-a.log) |
| Detect, attribute and auto-correct manual changes | Manual `maxRunners 3→10` reverted within 30 s by self-heal; agent reported actor, time and `self_healed: true` | [08/02](evidence/08-self-heal-and-drift-drill/02-refresh-and-second-drift-drill.log) |

## Repository layout

```
CODEOWNERS                        default code owner
CONTRIBUTING.md                   contribution and evidence-handling guidelines
.gitignore                        local files and credential-file exclusions
README.md                         this file
TIMELINE.md                       every activity, in order, with timestamps and evidence links
docs/
  01-design-phase.md              use case, architecture, diagram, guides
  02-environment-and-inventory.md cluster before/after, AWS and Kubernetes resources created, versions
  03-adoption-runbook-as-executed.md  the phases exactly as run on [REDACTED_CLUSTER_NAME]
  04-issues-and-resolutions.md    13 problems: symptom, root cause, fix, evidence, prevention
  05-compliance-remediation.md    findings, the PR, the rescore
  06-drift-drill.md               self-heal and attribution, both runs
  07-git-history.md               every commit and PR on arc-intel that touched the cluster
  08-security-findings-and-follow-ups.md  open risks and remaining work, prioritised
evidence/                         raw terminal output, one file per step (see TIMELINE.md)
  00-discovery/  01-aws-and-generate/  02-argocd/  03-bootstrap/  04-arc-adoption/
  05-github-app-recovery/  06-verify-and-agent/  07-compliance-remediation/  08-self-heal-and-drift-drill/
diagram/                          architecture diagram (PNG, SVG, PDF)
scripts/collect-final-state.sh    read-only snapshot of the current state into evidence/09-final-state/
```

## How to read it

1. Start with [TIMELINE.md](TIMELINE.md): one row per activity, linked to its log.
2. For any problem, [docs/04-issues-and-resolutions.md](docs/04-issues-and-resolutions.md) explains cause and fix.
3. [docs/08-security-findings-and-follow-ups.md](docs/08-security-findings-and-follow-ups.md) lists what is still open.
4. To add current-state evidence, run `scripts/collect-final-state.sh` against the cluster and commit the output.

See [CONTRIBUTING.md](CONTRIBUTING.md) before adding evidence or documentation.

## Environment

| | |
|---|---|
| Cluster | Amazon EKS `[REDACTED_CLUSTER_NAME]`, Kubernetes 1.36, us-east-2, 5 nodes (amd64) |
| GitOps | Argo CD (chart 10.10.5), app-of-apps `[REDACTED_CLUSTER_NAME]-root`, repo `ajaychinthapalli/arc-intel@main` |
| ARC | gha-runner-scale-set-controller 0.14.2 (`arc` in `arc-systems`), scale set `arc-runner-set` (`arc-runners`) → `ajaychinthapalli/arc-runners-sandbox` |
| Agent | Kagent 0.10.3, agent `arc-compliance-agent`, ModelConfig `bedrock-native` (Claude Sonnet 4.6 on Amazon Bedrock) |
| arc-intel | MCP server image `arc-intel-mcp:0.1.0` in ECR, namespace `arc-intel` |
| Operator | macOS (arm64), bash 5.3, kubectl 1.37, Helm 4.2.4, AWS CLI, gh, argocd CLI |
| Date | 2026-10-17 (design) and 2026-10-18 (implementation), America/Phoenix (UTC-7) |

## Redaction and secret handling

- Logs are terminal captures with sensitive values redacted, including AWS account and resource identifiers,
  GitHub App and installation IDs, internal hostnames, IP addresses, local paths, and password values.
  Redactions preserve the surrounding diagnostic context where possible.
- Every credential step was written so the secret never reached the terminal: the GitHub config Secret was
  compared key by key without printing values, the Argo CD token was piped straight into Secrets Manager,
  the GitHub App key was tested with a locally signed JWT, and passwords were entered at hidden prompts.
- One exception is recorded on purpose: the Argo CD admin password was briefly set to a placeholder string and
  changed minutes later ([issue 7](docs/04-issues-and-resolutions.md#7-argo-cd-admin-password-reset-to-a-placeholder)).
- Secret scan of `evidence/`: no `github_pat_`, `ghp_`, private-key blocks or JWTs. The only match is the
  scan command itself in `01-aws-and-generate/04`.
