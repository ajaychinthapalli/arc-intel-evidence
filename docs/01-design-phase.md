# 1. Design phase (Sat 2026-10-17)

## The problem

ARC runner pools are configured through Helm values, but runtime state drifts: someone patches `maxRunners`
during an incident, a runner image tag floats to `latest`, a scale set's controller version falls behind.
These changes are invisible until something breaks, and when they are found nobody can say who made them,
whether Git still describes reality, or whether the configuration was ever compliant.

## The use case

**ARC Configuration Compliance & Drift Intelligence**: continuously score every ARC scale set against a
policy pack, detect drift from the source of truth (Argo CD), attribute each out-of-band change to an IAM
identity from the EKS audit log, and let platform engineers ask an agent in plain language: "how compliant
are we?", "who changed this?", "how do I fix it in Git?".

## How it works

```
GitHub (arc-intel repo) ──► Argo CD ──► ARC controller + runner scale sets (EKS)
                                 ▲                  │
          target state (API)     │                  │ live state (K8s API, read-only)
                                 │                  ▼
       EKS audit log (CloudWatch) ──► arc-intel MCP server ──► Prometheus alerts / daily digest
                                                │
                                   MCP (streamable HTTP)
                                                │
                    Kagent agent  ◄── A2A ──  engineers, digest
                    (Claude on Amazon Bedrock)
```

- **arc-intel** (Python MCP server) evaluates 16 rules, computes a score
  (`100 − 25·critical − 10·high − 5·medium − 2·low`) and a posture (`healthy`, `drifted`, `non_compliant`,
  `drift_introduced_violation`, `unknown_baseline`).
- **Drift** compares live AutoscalingRunnerSets with Argo CD's rendered target state; each violation is
  tagged with its origin, either `drift` (fix the cluster) or `source_of_truth` (fix Git).
- **Attribution** reads `managedFields`, then the EKS audit log via CloudWatch Logs Insights for the IAM
  principal, source IP, user agent and time. It also detects writes that Argo CD self-healed.
- **Remediation** is proposed as a Git change (values file and Argo CD app), or as an RFC 6902 patch guarded
  by `test` operations for emergencies. The agent has no write access to ARC.

### Policy pack

| Rule | Check | Severity |
|---|---|---|
| ARC-001 | GitHub App authentication (no PAT) | critical |
| ARC-002 | Allowed GitHub scope | high |
| ARC-003 | Bounded `maxRunners` | high |
| ARC-004 | Sane `minRunners` | medium |
| ARC-005 | Pinned images | high |
| ARC-006 | Approved registries | high |
| ARC-007 | Minimum runner version | medium |
| ARC-008 | No privileged containers | critical |
| ARC-009 | No host namespaces or hostPath | high |
| ARC-010 | Runner resource requests and limits | medium |
| ARC-011 | No privilege escalation in runner | medium |
| ARC-012 | Explicit runner group | low |
| ARC-013 | Required ownership labels | low |
| ARC-014 | NetworkPolicy present | medium |
| ARC-015 | Controller / scale-set version match | high |
| ARC-016 | Declaratively managed | medium |

### MCP tools

`arc_inventory`, `arc_check_compliance`, `arc_detect_drift`, `arc_assess`, `arc_audit_trail`,
`arc_fleet_report`, `arc_controller_health`, `arc_propose_remediation`, `arc_list_policies` (read-only), and
`arc_capture_baseline` (writes only the `arc-intel-baselines` ConfigMap, off by default).

## Enterprise considerations captured in the design

- Least privilege: read-only RBAC, a separate read-only Argo CD account, an IAM role limited to Logs Insights
  on one log group, and Pod Identity/IRSA (no static keys).
- GitOps-only change path: fixes are PRs; Argo CD applies; self-heal reverts manual edits.
- Secrets in AWS Secrets Manager, synced by External Secrets; nothing secret in Git.
- Pod Security `restricted`, NetworkPolicies, immutable ECR tags with scan-on-push.
- Observability: Prometheus metrics, five alert rules, Grafana, daily digest.

## Design deliverables

| Deliverable | Location |
|---|---|
| Platform repo | [ajaychinthapalli/arc-intel](https://github.com/ajaychinthapalli/arc-intel) |
| Architecture document | [claude.ai artifact](https://claude.ai/code/artifact/28def6b9-5d68-4f9b-9a66-0826752c5967) |
| Deployment guide (incl. "Existing cluster: adopt into Argo CD") | [claude.ai artifact](https://claude.ai/code/artifact/83310ef1-31e2-4f2c-8821-3d3d1d0b4007) |
| Architecture diagram | [../diagram/](../diagram/) (vector rebuild; earlier AI-generated drafts had recurring text errors) |

Diagram title: *ARC Configuration Compliance & Drift Intelligence on Amazon EKS — GitOps with Argo CD and Kagent*.
