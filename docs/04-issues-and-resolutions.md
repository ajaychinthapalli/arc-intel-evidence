# 4. Issues and resolutions

Thirteen problems came up during implementation. None caused a runner outage that wasn't already latent
(issue 10 predates this work). Each entry lists the symptom, root cause, fix, evidence and the change made so
the next cluster avoids it.

> "Prevention" changes were made in the arc-intel source package during the session. Fixes applied on the
> cluster itself were committed to `ajaychinthapalli/arc-intel` (see [07-git-history.md](07-git-history.md)); the
> template/script improvements still need to be copied into that repo (follow-up F-10).

| # | Issue | Severity | Status |
|---|---|---|---|
| 1 | Pre-existing Secrets Manager secret did not match the cluster | Medium | Resolved |
| 2 | `argocd` phase failed to store the arc-intel token | Low | Resolved, script fixed |
| 3 | Stale port-forward held port 18443 | Low | Resolved |
| 4 | Work was on `develop`; Argo CD follows `main` | Low | Resolved |
| 5 | kube-prometheus-stack blocked by the AppProject | Medium | Resolved, template fixed |
| 6 | argocd CLI not installed | Low | Resolved |
| 7 | Argo CD admin password reset to a placeholder | Medium (security) | Resolved within minutes |
| 8 | Runner set ComparisonError: chart cannot look up the controller | High (blocked adoption) | Resolved, generator fixed |
| 9 | arc-intel had no pods: CloudWatch auto-instrumentation vs Pod Security | High (blocked arc-intel) | Resolved, base manifest fixed |
| 10 | Runner listener 404 "Integration not found" | High (runners offline) | Resolved |
| 11 | Kagent CLI has no `invoke` | Low | Worked around (A2A) |
| 12 | Agent answer inaccuracies | Medium | **Open**: arc-intel 0.1.1 |
| 13 | First drift drill not reverted | Low | Resolved |

---

## 1. Pre-existing Secrets Manager secret did not match the cluster

- **Symptom:** the `aws` phase printed `[REDACTED_SECRET_NAME] already exists (not overwritten)`; a key-by-key
  comparison (values never printed) returned `DIFFERS` for all three keys.
- **Root cause:** an older secret named `[REDACTED_SECRET_NAME]` held credentials for a different GitHub App.
  External Secrets would have overwritten the working cluster Secret with them.
- **Fix:** left the old secret alone and created a per-cluster secret `arc/[REDACTED_CLUSTER_NAME]/github-app` from
  the working cluster Secret; pointed the ExternalSecret at it.
- **Prevention:** the script now defaults to `GITHUB_SM_SECRET=arc/<cluster>/github-app` (never shared) and
  warns to compare if it already exists.
- **Evidence:** [01/01](../evidence/01-aws-and-generate/01-aws-phase.log), [01/02](../evidence/01-aws-and-generate/02-secret-comparison.log), [01/03](../evidence/01-aws-and-generate/03-per-cluster-secret-and-generate.log)

## 2. `argocd` phase failed to store the arc-intel token

- **Symptom:** `jq: parse error: Invalid numeric literal at line 1, column 8`.
- **Root cause:** the session request to Argo CD's API had no `Content-Type: application/json` header and ran
  before the port-forward was ready, so the response wasn't JSON.
- **Fix:** ran the login and token requests by hand, printing only `ok`/error, and piped the token straight into Secrets Manager.
- **Prevention:** the script now sends the header, waits on `/healthz`, and prints Argo's error text (never a token).
- **Evidence:** [02/01](../evidence/02-argocd/01-argocd-phase.log), [02/02](../evidence/02-argocd/02-argocd-token-and-initial-secret.log)

## 3. Stale port-forward held port 18443

- **Symptom:** `[1]+ Exit 1 kubectl … port-forward …` and `kill: No such process`, even though login worked.
- **Root cause:** the failed script run left its port-forward alive; the manual requests went through it.
- **Fix:** `lsof -ti tcp:18443 | xargs kill`.
- **Evidence:** [02/02](../evidence/02-argocd/02-argocd-token-and-initial-secret.log)

## 4. Work was on `develop`; Argo CD follows `main`

- **Symptom:** `## develop...origin/develop`; `origin/main` contained none of the cluster files.
- **Root cause:** the generated root app targets `main`.
- **Fix:** `gh pr create` reported that PR #2 had already merged `develop` into `main`. Fast-forwarded
  (`0f35f14..1c7bb52`, 97 files), deleted `develop`. Keeping `main` as the deployed branch means changes
  reach the cluster only through reviewed PRs.
- **Evidence:** [02/03](../evidence/02-argocd/03-branch-check.log), [02/04](../evidence/02-argocd/04-pr2-merged-to-main.log)

## 5. kube-prometheus-stack blocked by the AppProject

- **Symptom:** `kube-prometheus-stack OutOfSync / Missing`; later sync waves (arc-intel, agent, digest) never
  created. Condition: `namespace kube-system is not permitted in project 'arc-platform'`.
- **Root cause:** the chart creates Services in `kube-system` to scrape the controller manager, scheduler,
  etcd, kube-proxy and CoreDNS. EKS's control plane is AWS-managed and not scrapeable anyway, and the
  AppProject deliberately doesn't allow `kube-system`.
- **Fix:** disabled those five components in values (`4e79346`), then `terminate-op`, hard refresh and sync.
  The project stays strict.
- **Prevention:** `clusters/_template/values/kube-prometheus-stack.yaml` now ships with them disabled.
- **Evidence:** [03/02](../evidence/03-bootstrap/02-bootstrap.log), [03/03](../evidence/03-bootstrap/03-kube-prometheus-stack-sync-error.log), [03/04](../evidence/03-bootstrap/04-kps-fix-commit-and-missing-cli.log), [03/07](../evidence/03-bootstrap/07-password-change-and-kps-sync.log)

## 6. argocd CLI not installed

- **Fix:** `brew install argocd`, port-forward to `argocd-server`, `argocd login --insecure` (self-signed dev certificate).
- **Evidence:** [03/04](../evidence/03-bootstrap/04-kps-fix-commit-and-missing-cli.log), [03/05](../evidence/03-bootstrap/05-argocd-login-prompt.log)

## 7. Argo CD admin password reset to a placeholder

- **Symptom:** the initial admin secret had been deleted and the saved password wasn't at hand.
- **What happened:** the reset command (bcrypt hash into `argocd-secret`) was run with the example value
  `choose-a-strong-password` from the instructions, so the admin password briefly equalled a published string.
- **Fix:** changed at once with `argocd account update-password` (hidden prompts). The window was about
  18:16–18:17, with Argo CD reachable only through a local port-forward.
- **Lesson:** never put a placeholder password inline in a command; prompt with `read -rs`. See the follow-up on SSO / disabling local admin.
- **Evidence:** [03/06](../evidence/03-bootstrap/06-admin-password-reset.log), [03/07](../evidence/03-bootstrap/07-password-change-and-kps-sync.log) (first lines)

## 8. Runner set ComparisonError: chart cannot look up the controller

- **Symptom:** `arc-runners-arc-runner-set` Sync Status `Unknown`; `helm template` failed with
  `No gha-rs-controller deployment found using label (app.kubernetes.io/part-of=gha-rs-controller)`.
- **Root cause:** the `gha-runner-scale-set` chart uses Helm `lookup` to find the controller ServiceAccount
  in the live cluster. Argo CD renders charts without cluster access, so `lookup` returns nothing.
  (The controller also carries `app.kubernetes.io/name`, not `part-of`.)
- **Fix:** set `controllerServiceAccount: {namespace: arc-systems, name: arc-gha-rs-controller}` in the
  values file. The first attempt was committed locally but not pushed (still `4e79346` at 18:35); pushed as
  `fbe7656` at 18:36. The resulting diff was the tracking annotation plus the chart's values-hash only.
- **Prevention:** `clusters/render.py` now writes `controllerServiceAccount` automatically. arc-intel's
  controller discovery accepts both labels.
- **Evidence:** [04/01](../evidence/04-arc-adoption/01-diagnostics-and-arc-controller-diff.log), [04/05](../evidence/04-arc-adoption/05-arc-intel-retry-and-runner-set-comparison-error.log), [04/06](../evidence/04-arc-adoption/06-runner-set-controller-sa-fix-and-diff.log)

## 9. arc-intel had no pods: CloudWatch auto-instrumentation vs Pod Security

- **Symptom:** Deployment `0/1`, ReplicaSet `FailedCreate`:
  `violates PodSecurity "restricted:latest": … container "opentelemetry-auto-instrumentation-java" must set …`.
- **Root cause:** the `amazon-cloudwatch-observability` add-on runs Application Signals with
  `monitorAllServices: true`. Its mutating webhook injected a Java agent init container into the (Python)
  arc-intel pod. That container doesn't meet the namespace's `restricted` Pod Security level.
- **Fix, attempt 1:** added `arc-intel` to the add-on's `autoMonitor.exclude` for all four languages,
  keeping existing exclusions (`kagent`, `agentgateway-system`, `agentregistry`). Pods were still refused.
- **Fix, attempt 2:** pod annotations `instrumentation.opentelemetry.io/inject-{java,python,nodejs,dotnet}: "false"`
  via a Kustomize patch in Git (`f7fc69d`). Argo CD auto-synced; the rollout succeeded.
- **Decision:** kept Pod Security `restricted` rather than weakening it for an agent arc-intel doesn't need.
- **Prevention:** the base `deploy/mcp-server/deployment.yaml` now carries the opt-out annotations.
- **Evidence:** [04/03](../evidence/04-arc-adoption/03-controller-pod-age-and-arc-intel-podsecurity.log), [04/04](../evidence/04-arc-adoption/04-cloudwatch-addon-exclusion.log), [04/07](../evidence/04-arc-adoption/07-runner-set-sync-and-listener-error.log), [04/08](../evidence/04-arc-adoption/08-listener-404-and-otel-optout-fix.log)

## 10. Runner listener 404 "Integration not found"

- **Symptom:** after the runner-set sync restarted the listener: `POST https://api.github.com/app/installations/[REDACTED_GITHUB_INSTALLATION_ID]/access_tokens failed (404 Not Found): Integration not found`; listener in `Error`.
- **Investigation:**
  - Cluster Secret: App [REDACTED_GITHUB_APP_ID] / installation [REDACTED_GITHUB_INSTALLATION_ID]. Old `[REDACTED_SECRET_NAME]`: App [REDACTED_GITHUB_APP_ID] / installation [REDACTED_GITHUB_INSTALLATION_ID].
  - Tested both by signing a JWT with each private key locally and calling `GET /app` and
    `GET /app/installations`. Both returned `Integration not found`, so **both Apps had been deleted**.
- **Root cause:** latent, pre-existing. The old listener kept running on a session opened days earlier; any
  restart (node rotation, Helm upgrade) would have taken runners offline. The adoption sync was simply the
  first restart.
- **Fix:** created GitHub App `[REDACTED_GITHUB_APP_NAME]` (App [REDACTED_GITHUB_APP_ID], installation [REDACTED_GITHUB_INSTALLATION_ID], Administration RW,
  webhook off). Stored it in `arc/[REDACTED_CLUSTER_NAME]/github-app`, verified with the JWT test, force-synced the
  ExternalSecret and restarted the listener. Listener `Running`, polling `broker.actions.githubusercontent.com`.
- **Follow-ups:** restrict the installation from "all" to `arc-runners-sandbox`; move the PEM out of
  `[REDACTED_LOCAL_PATH] delete `[REDACTED_SECRET_NAME]` again; add a credential-validity check to ARC-001.
- **Evidence:** [04/07](../evidence/04-arc-adoption/07-runner-set-sync-and-listener-error.log), [04/08](../evidence/04-arc-adoption/08-listener-404-and-otel-optout-fix.log), [05-github-app-recovery/](../evidence/05-github-app-recovery/)

## 11. Kagent CLI has no `invoke`

- **Symptom:** `Error: unknown command "invoke" for "kagent"`.
- **Workaround:** the A2A JSON-RPC endpoint (`message/send`) on `svc/kagent-controller:8083`, wrapped in a
  shell function `ask`. It's the same path the daily digest uses.
- **Evidence:** [06/02](../evidence/06-verify-and-agent/02-kagent-cli-invoke.log), [06/03](../evidence/06-verify-and-agent/03-agent-first-answer-a2a.log)

## 12. Agent answer inaccuracies

| Answer said | Reality | Cause |
|---|---|---|
| Example pin `actions-runner:2.323.0` | Latest was 2.338.0 | Model filled in a version from memory |
| "Merge & Helm upgrade" | Fix = PR to the values file + Argo CD sync; `helm upgrade` would fight Argo CD | `arc_check_compliance` output lacks the Argo CD context (only drift/remediation tools include it) |
| Chart registry called "the Argo CD repo" | Values live in `clusters/[REDACTED_CLUSTER_NAME]/runner-scale-sets/arc-runner-set/values.yaml` | Same |
| Listed pre-adoption `helm upgrade` events alongside drift | Those were real Helm upgrades from before adoption | Audit trail isn't split at the adoption time |

- **Status:** open. arc-intel 0.1.1 should add the Argo CD application and values-file path to every
  compliance/fleet result, mark events before adoption, and tell the agent never to suggest Helm or kubectl
  for Argo-managed scale sets.
- **Evidence:** [06/03](../evidence/06-verify-and-agent/03-agent-first-answer-a2a.log), [08/01](../evidence/08-self-heal-and-drift-drill/01-pr4-and-first-drift-drill.log)

## 13. First drift drill not reverted

- **Symptom:** after PR #4 (self-heal) merged, `maxRunners` was patched to 10 and was still 10 three minutes
  later. The agent correctly reported "self-heal is off".
- **Root cause:** Argo CD polls Git about every 3 minutes and no GitHub webhook is configured. The patch
  landed seconds after the merge, before the root app had applied the new Application spec.
- **Fix:** `argocd app get [REDACTED_CLUSTER_NAME]-root --refresh`. Both ARC apps showed `selfHeal: true` and the
  existing drift was reverted. Drill 2 then reverted within 30 seconds.
- **Prevention:** add a GitHub webhook to Argo CD (`/api/webhook`) so merges apply within seconds.
- **Evidence:** [08/01](../evidence/08-self-heal-and-drift-drill/01-pr4-and-first-drift-drill.log), [08/02](../evidence/08-self-heal-and-drift-drill/02-refresh-and-second-drift-drill.log)
