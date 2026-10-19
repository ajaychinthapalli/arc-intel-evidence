# 6. Self-heal and drift drill

## Enabling self-heal: PR #4

[ajaychinthapalli/arc-intel#4](https://github.com/ajaychinthapalli/arc-intel/pull/4), commit `6a4cc86`, merged
as `2a8b39f`. In `clusters/[REDACTED_CLUSTER_NAME]/apps/20-arc.yaml`, `automated: {prune: false, selfHeal: true}`
was added to the `arc-controller` Application (line 28) and the runner-set ApplicationSet template (line 68).

- `selfHeal: true`: Argo CD reverts any live change that differs from Git.
- `prune: false`: Argo CD never deletes ARC resources automatically (safety net while the setup is new).

## Drill 1, 19:16:02: change not reverted (expected after diagnosis)

```bash
kubectl -n arc-runners patch autoscalingrunnerset arc-runner-set --type=merge -p '{"spec":{"maxRunners":10}}'
sleep 180   # → maxRunners still 10
```

Why: the patch landed seconds after PR #4 merged. Argo CD polls Git about every 3 minutes (no webhook), so
the root app hadn't yet applied the new sync policy ([issue 13](04-issues-and-resolutions.md#13-first-drift-drill-not-reverted)).

The agent's answer was nonetheless accurate:

| Field | Agent output |
|---|---|
| Posture | DRIFTED, OutOfSync, one confirmed out-of-band write |
| Who | `[REDACTED_AWS_ARN]`, from the operator's IP, `kubectl` on darwin/arm64 |
| What | `spec.maxRunners` 3 → 10 |
| When | 2026-10-19 02:16:02 UTC, 7 min 30 s after the last legitimate Argo CD sync (02:08:32 UTC, PR #3) |
| Self-heal | "off", which was correct at that moment |
| Identity source | `eks_audit_log` |

Evidence: [08/01](../evidence/08-self-heal-and-drift-drill/01-pr4-and-first-drift-drill.log)

## Refresh, ~19:21

```bash
argocd app get [REDACTED_CLUSTER_NAME]-root --refresh
kubectl -n argocd get applications arc-controller arc-runners-arc-runner-set -o custom-columns=...AUTO:.spec.syncPolicy.automated...
# arc-controller               map[prune:false selfHeal:true]   Synced
# arc-runners-arc-runner-set   map[prune:false selfHeal:true]   Synced
kubectl -n arc-runners get autoscalingrunnerset arc-runner-set -o jsonpath='{.spec.maxRunners}'   # 3
```

Once self-heal was active, Argo CD reverted drill 1's change on its own. (`REV <none>` is expected: multi-source
applications report revisions in `.status.sync.revisions`.)

## Drill 2, 19:22:43: reverted within 30 seconds

```bash
kubectl -n arc-runners patch autoscalingrunnerset arc-runner-set --type=merge -p '{"spec":{"maxRunners":10}}'
sleep 30    # → maxRunners 3
sleep 120   # CloudWatch indexing
ask "Has anyone changed arc-runners/arc-runner-set outside Git recently? Who, when, and what happened to the change?"
```

Agent answer, summarised:

| Field | Agent output |
|---|---|
| Verdict | Currently healthy and Synced; two out-of-band `kubectl patch` writes on 2026-10-19, both reverted by self-heal |
| Writes | 02:16:02 UTC and 02:22:43 UTC, both `[REDACTED_AWS_ARN]`, same source IP, kubectl v1.37.0 macOS/arm64 |
| Outcome | `self_healed: true`, zero drifted fields; automated sync completed at 02:22:43 UTC |
| Identity source | `eks_audit_log` |
| Recommendations | Stop root use for kubectl; admission policy limiting ARS writers; route changes via PR; alert on out-of-band writes |

Evidence: [08/02](../evidence/08-self-heal-and-drift-drill/02-refresh-and-second-drift-drill.log)

## What this proves

| Diagram capability | Demonstrated by |
|---|---|
| Detect drift from Git | Drill 1: DRIFTED with the exact field |
| Attribute to a person/identity | IAM principal, IP, client, time from the EKS audit log, both drills |
| Correct automatically | Drill 2: reverted in under 30 s |
| Keep evidence | Agent reports both writes after the revert (`self_healed: true`) |

## Notes on the agent's recommendations

- **Admission policy (Kyverno/OPA) on AutoscalingRunnerSet:** worth adding, but allow the Argo CD
  application controller and the ARC controller ServiceAccounts, plus a break-glass group.
- **Alert on out-of-band writes:** valid, and currently a **gap**. arc-intel's `ArcManualDrift` rule fires only
  when drift persists for 30 minutes (`arc_intel_manual_changes > 0 for 30m`), so it never fires for a write
  that self-heal reverts in seconds. Options: a CloudWatch Logs metric filter and alarm on the audit log
  (writes to `autoscalingrunnersets` by anyone other than the Argo CD and ARC controller identities), or a
  counter `arc_intel_out_of_band_writes_total` in arc-intel with a Prometheus alert (follow-up F-08). Either
  way, Alertmanager also needs a receiver (Slack/PagerDuty).
- **Root account:** a genuine finding. See [08-security-findings-and-follow-ups.md](08-security-findings-and-follow-ups.md).
