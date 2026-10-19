# 7. Git history: ajaychinthapalli/arc-intel

Every commit to `main` that changed the cluster, in order. Argo CD follows `main`.

| Commit | When | How | Change | Effect on cluster | Evidence |
|---|---|---|---|---|---|
| `0f35f14` | before 16:59 | GitHub "Initial commit" | Repo created | none | [02/02](../evidence/02-argocd/02-argocd-token-and-initial-secret.log) |
| `1c7bb52` | by 17:01 | **PR #2** (`develop` → `main`) | arc-intel platform, Argo CD apps, `clusters/[REDACTED_CLUSTER_NAME]/` (97 files, +6502) | Source of truth for bootstrap | [02/04](../evidence/02-argocd/04-pr2-merged-to-main.log) |
| `4e79346` | 18:13 | direct push | kube-prometheus-stack: disable EKS control-plane scrapers | Prometheus could sync; later waves deployed | [03/04](../evidence/03-bootstrap/04-kps-fix-commit-and-missing-cli.log) |
| `fbe7656` | 18:36 | direct push | arc-runner-set: explicit `controllerServiceAccount` | Runner-set app could render; adopted | [04/06](../evidence/04-arc-adoption/06-runner-set-controller-sa-fix-and-diff.log) |
| `f7fc69d` | 18:38 | direct push | arc-intel: OpenTelemetry injection opt-out annotations | arc-intel pod admitted | [04/08](../evidence/04-arc-adoption/08-listener-404-and-otel-optout-fix.log) |
| `8a3c206` → `2207959` | ~19:05 | **PR #3** | arc-runner-set: pin 2.338.0, CPU limit, no privilege escalation, labels | Score 78 → 100 | [07/01](../evidence/07-compliance-remediation/01-pr3-sync-and-grade-a.log) |
| `6a4cc86` → `2a8b39f` | ~19:15 | **PR #4** | ARC apps: automated sync, self-heal, prune off | Manual changes reverted automatically | [08/01](../evidence/08-self-heal-and-drift-drill/01-pr4-and-first-drift-drill.log) |

## Observations

- Three fixes (`4e79346`, `fbe7656`, `f7fc69d`) went straight to `main` during bring-up. From PR #3 onward,
  every change went through a pull request.
- **Recommended:** enable branch protection on `main` (require a PR and one approval, no direct pushes) now
  that bring-up is complete. `CODEOWNERS` already exists in the repo.
- Repository guidance is in `CODEOWNERS` and `CONTRIBUTING.md`; local files and credential files are excluded
  by `.gitignore`.
