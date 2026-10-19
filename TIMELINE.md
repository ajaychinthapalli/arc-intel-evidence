# Timeline

All times America/Phoenix (UTC-7). Times quoted from the EKS audit log by the agent are UTC: subtract 7 hours (02:16 UTC on 10-19 = 19:16 local on 10-18). Times marked ~ are approximate (from message times, not command output).

## Day 1: design (Sat 2026-10-17)

| Time | Activity | Output |
|---|---|---|
| 20:25 | Use case defined: ARC Configuration Compliance & Drift Intelligence with Kagent; deliverable is a deployable repo | `arc-intel` repo (MCP server, 16-rule policy pack, agent, manifests, tests) |
| 20:30–21:15 | Architecture write-up: problem, how it works, enterprise considerations; colour flow diagram; tech stack; switch target to Amazon EKS | Architecture document |
| 21:15–22:09 | Target stack fixed as **EKS + Argo CD + Kubernetes + ARC + Kagent**; title chosen; several AI-generated diagram drafts reviewed for text errors | Review notes |
| 22:09–22:13 | Clean vector diagram rebuilt (exact text), then step-by-step deployment guide based on it | [diagram/](diagram/), deployment guide |

Details: [docs/01-design-phase.md](docs/01-design-phase.md).

## Day 2: implementation on [REDACTED_CLUSTER_NAME] (Sun 2026-10-18)

### Discovery

| Time | Activity | Result | Evidence |
|---|---|---|---|
| 15:15 | List namespaces | ARC (`arc-systems`, `arc-runners`) and Kagent already present | [00/01](evidence/00-discovery/01-namespaces.log) |
| 15:19 | Read-only inventory: Helm releases, scale sets, controller, Kagent, EKS settings, add-ons, nodes, CRDs | ARC 0.14.2 via Helm, Kagent 0.10.3, audit logging on, no Argo CD / ESO / Prometheus | [00/02](evidence/00-discovery/02-cluster-inventory.log) |
| 15:22 | Decision: Argo CD is the source of truth, follow the diagram | Adoption path chosen instead of the Helm-baseline path | — |
| 16:29 | `adopt-existing-eks.sh discover` | 2 Helm releases to adopt, GitHub App Secret `arc-github-app`, NetworkPolicy enforcement on | [00/03](evidence/00-discovery/03-discover-phase.log) |
| 16:33 | Check how the existing agent reaches Bedrock | IRSA on `arc-readiness-agent`, no static key, no node pinning | [00/04](evidence/00-discovery/04-agent-irsa-check.log) |

### AWS resources and GitOps folder

| Time | Activity | Result | Evidence |
|---|---|---|---|
| 16:35 | `aws` phase | Image `arc-intel-mcp:0.1.0` pushed to ECR; IAM roles + Pod Identity for arc-intel and External Secrets | [01/01](evidence/01-aws-and-generate/01-aws-phase.log) |
| 16:38 | Compare pre-existing Secrets Manager `[REDACTED_SECRET_NAME]` with the cluster Secret (no values printed) | All 3 keys **differ** → [issue 1](docs/04-issues-and-resolutions.md#1-pre-existing-secrets-manager-secret-did-not-match-the-cluster) | [01/02](evidence/01-aws-and-generate/02-secret-comparison.log) |
| 16:43 | Create per-cluster secret `arc/[REDACTED_CLUSTER_NAME]/github-app`; `generate` the cluster folder; point ESO at it | `clusters/[REDACTED_CLUSTER_NAME]/` rendered | [01/03](evidence/01-aws-and-generate/03-per-cluster-secret-and-generate.log) |
| 16:44 | Review generated values and scan for credentials | Values match the Helm release; scan clean | [01/04](evidence/01-aws-and-generate/04-generated-values-review.log) |
| 16:49–16:54 | Create fine-grained read-only GitHub token for Argo CD (`Contents: read`, one repo) | Token loaded with a hidden prompt | — |

### Argo CD

| Time | Activity | Result | Evidence |
|---|---|---|---|
| 16:56 | `argocd` phase | Argo CD 10.10.5 installed, repo registered; token step failed with a `jq` parse error → [issue 2](docs/04-issues-and-resolutions.md#2-argocd-phase-failed-to-store-the-arc-intel-token) | [02/01](evidence/02-argocd/01-argocd-phase.log) |
| 16:58–16:59 | Create arc-intel read-only Argo CD token by hand → Secrets Manager `arc/argocd-token`; clean up stale port-forward; save and delete initial admin secret | `login ok`, `token ok` | [02/02](evidence/02-argocd/02-argocd-token-and-initial-secret.log) |
| 17:00 | Check what Argo CD will read | Working on `develop`; `main` had only the initial commit → [issue 4](docs/04-issues-and-resolutions.md#4-work-was-on-develop-argo-cd-follows-main) | [02/03](evidence/02-argocd/03-branch-check.log) |
| 17:01 | Merge to `main` | PR #2 already merged: 97 files on `main` (`1c7bb52`); `develop` deleted | [02/04](evidence/02-argocd/04-pr2-merged-to-main.log) |
| 17:02 | Pre-bootstrap checks | ESO key and `targetRevision: main` correct | [03/01](evidence/03-bootstrap/01-pre-bootstrap-checks.log) |

### Bootstrap

| Time | Activity | Result | Evidence |
|---|---|---|---|
| 18:11 | `bootstrap` (root app applied) | ESO and platform-secrets healthy; `kube-prometheus-stack` stuck, later waves blocked | [03/02](evidence/03-bootstrap/02-bootstrap.log) |
| 18:12 | Read the sync error | `namespace kube-system is not permitted in project 'arc-platform'` → [issue 5](docs/04-issues-and-resolutions.md#5-kube-prometheus-stack-blocked-by-the-appproject) | [03/03](evidence/03-bootstrap/03-kube-prometheus-stack-sync-error.log) |
| 18:13 | Disable EKS control-plane scrapers in values (`4e79346`); argocd CLI missing → [issue 6](docs/04-issues-and-resolutions.md#6-argocd-cli-not-installed) | Pushed | [03/04](evidence/03-bootstrap/04-kps-fix-commit-and-missing-cli.log) |
| 18:15–18:16 | Argo CD login; admin password reset (initial secret already deleted) → [issue 7](docs/04-issues-and-resolutions.md#7-argo-cd-admin-password-reset-to-a-placeholder) | Logged in | [03/05](evidence/03-bootstrap/05-argocd-login-prompt.log), [03/06](evidence/03-bootstrap/06-admin-password-reset.log) |
| 18:17–18:23 | Change admin password; terminate stuck op; resync Prometheus; watch apps | Prometheus Synced/Healthy; all apps created | [03/07](evidence/03-bootstrap/07-password-change-and-kps-sync.log) |

### Adopting ARC and starting arc-intel

| Time | Activity | Result | Evidence |
|---|---|---|---|
| 18:24 | Diagnostics + `argocd app diff arc-controller` | Controller diff = tracking annotations only. Runner set: `ComparisonError` (chart controller lookup) → [issue 8](docs/04-issues-and-resolutions.md#8-runner-set-comparisonerror-chart-cannot-look-up-the-controller). arc-intel: 0 pods | [04/01](evidence/04-arc-adoption/01-diagnostics-and-arc-controller-diff.log) |
| 18:25 | **`argocd app sync arc-controller`** | Synced in 4 s, server-side apply | [04/02](evidence/04-arc-adoption/02-arc-controller-sync.log) |
| 18:27 | Controller pod age; arc-intel ReplicaSet events | Pod **5d20h, 0 restarts** (no runtime change). arc-intel pods refused by Pod Security: injected `opentelemetry-auto-instrumentation-java` → [issue 9](docs/04-issues-and-resolutions.md#9-arc-intel-had-no-pods-cloudwatch-auto-instrumentation-vs-pod-security) | [04/03](evidence/04-arc-adoption/03-controller-pod-age-and-arc-intel-podsecurity.log) |
| 18:29 | Add `arc-intel` to CloudWatch add-on Application Signals exclusions (existing exclusions kept) | Add-on update `2395b293…` | [04/04](evidence/04-arc-adoption/04-cloudwatch-addon-exclusion.log) |
| 18:35 | Retry arc-intel; check runner set | arc-intel still refused; runner-set fix had not been pushed | [04/05](evidence/04-arc-adoption/05-arc-intel-retry-and-runner-set-comparison-error.log) |
| 18:36 | Push `controllerServiceAccount` (`fbe7656`); diff runner set | Diff = tracking annotation + values-hash only | [04/06](evidence/04-arc-adoption/06-runner-set-controller-sa-fix-and-diff.log) |
| 18:36 | **`argocd app sync arc-runners-arc-runner-set`** | Synced; listener restarted and failed → [issue 10](docs/04-issues-and-resolutions.md#10-runner-listener-404-integration-not-found) | [04/07](evidence/04-arc-adoption/07-runner-set-sync-and-listener-error.log) |
| 18:38–18:39 | Listener logs (GitHub 404); add OpenTelemetry opt-out annotations to arc-intel (`f7fc69d`) | **arc-intel rolled out** | [04/08](evidence/04-arc-adoption/08-listener-404-and-otel-optout-fix.log) |

### GitHub App recovery

| Time | Activity | Result | Evidence |
|---|---|---|---|
| 18:40 | Compare App/installation IDs | Cluster: app [REDACTED_GITHUB_APP_ID] / inst 170846377; old secret pending deletion | [05/01](evidence/05-github-app-recovery/01-credential-ids.log) |
| 18:41 | Restore old secret | Old: app [REDACTED_GITHUB_APP_ID] / inst 170469723 | [05/02](evidence/05-github-app-recovery/02-restore-old-secret.log) |
| 18:41 | Test both credential sets with a signed JWT | **Both Apps deleted** (`Integration not found`) | [05/03](evidence/05-github-app-recovery/03-jwt-credential-test.log) |
| 18:45–18:55 | Create GitHub App `[REDACTED_GITHUB_APP_NAME]` (App [REDACTED_GITHUB_APP_ID], inst 172872993); store, test, force ESO sync, restart listener | Listener **Running**, polling the broker | [05/04](evidence/05-github-app-recovery/04-new-app-and-listener-recovery.log) |

### Verification and agent

| Time | Activity | Result | Evidence |
|---|---|---|---|
| 18:56 | `verify` | **10/10 apps Synced+Healthy**; fleet 78 (B), `non_compliant`; `baseline_source: argocd:…`; `identity_source: eks_audit_log` | [06/01](evidence/06-verify-and-agent/01-verify.log) |
| 18:58 | `kagent invoke` | Command not in this CLI → [issue 11](docs/04-issues-and-resolutions.md#11-kagent-cli-has-no-invoke) | [06/02](evidence/06-verify-and-agent/02-kagent-cli-invoke.log) |
| 18:59 | Ask the agent over A2A | Correct 4 findings, severities and fixes; two inaccuracies → [issue 12](docs/04-issues-and-resolutions.md#12-agent-answer-inaccuracies) | [06/03](evidence/06-verify-and-agent/03-agent-first-answer-a2a.log) |

### Compliance remediation through Git

| Time | Activity | Result | Evidence |
|---|---|---|---|
| ~19:03–19:08 | PR #3: pin runner 2.338.0, CPU limit, `allowPrivilegeEscalation: false`, owner/cost-center labels; merge; diff; sync (`2207959`) | Diff matched the PR exactly | [07/01](evidence/07-compliance-remediation/01-pr3-sync-and-grade-a.log) |
| ~19:13 | Ask the agent for the grade after the next scan | **A, 100/100, healthy, no drift** | [07/01](evidence/07-compliance-remediation/01-pr3-sync-and-grade-a.log) |

### Self-heal and drift drill

| Time | Activity | Result | Evidence |
|---|---|---|---|
| ~19:15 | PR #4: automated sync + self-heal on the ARC apps, prune off (`2a8b39f`) | Merged | [08/01](evidence/08-self-heal-and-drift-drill/01-pr4-and-first-drift-drill.log) |
| 19:16:02 | Drill 1: `kubectl patch maxRunners 10` | **Not reverted**: Argo CD had not polled PR #4 yet → [issue 13](docs/04-issues-and-resolutions.md#13-first-drift-drill-not-reverted). Agent: DRIFTED, actor = AWS root ARN, 7.5 min after last sync | [08/01](evidence/08-self-heal-and-drift-drill/01-pr4-and-first-drift-drill.log) |
| ~19:21 | Refresh root app | Both ARC apps `selfHeal: true`; existing drift reverted (`maxRunners` 3) | [08/02](evidence/08-self-heal-and-drift-drill/02-refresh-and-second-drift-drill.log) |
| 19:22:43 | Drill 2: same patch | **Reverted within 30 s**; agent: both writes attributed, `self_healed: true`, no current drift | [08/02](evidence/08-self-heal-and-drift-drill/02-refresh-and-second-drift-drill.log) |
