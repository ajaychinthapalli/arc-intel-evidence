# 8. Security findings and follow-ups

## Security findings

| ID | Finding | Risk | Evidence | Action |
|---|---|---|---|---|
| S-01 | `kubectl` runs as the **AWS account root user** (`[REDACTED_AWS_ARN]`); every cluster write, including both drift-drill patches and the earlier Helm upgrades, is attributed to root | **High** | [08/01](../evidence/08-self-heal-and-drift-drill/01-pr4-and-first-drift-drill.log), [08/02](../evidence/08-self-heal-and-drift-drill/02-refresh-and-second-drift-drill.log) | Create an admin IAM role or IAM Identity Center permission set; give it an EKS access entry with `AmazonEKSClusterAdminPolicy`; `aws eks update-kubeconfig --role-arn …`; enable MFA on root and stop using it day to day |
| S-02 | GitHub App `[REDACTED_GITHUB_APP_NAME]` installed on **all** repositories with Administration read/write | **High** | [05/04](../evidence/05-github-app-recovery/04-new-app-and-listener-recovery.log) (`installation [REDACTED_GITHUB_INSTALLATION_ID] on ajaychinthapalli (all)`) | Settings → Installations → 172872993 → *Only select repositories* → `arc-runners-sandbox`. Installation ID unchanged, no cluster change |
| S-03 | GitHub App private key still in `[REDACTED_PRIVATE_KEY_PATH]` | Medium | [05/04](../evidence/05-github-app-recovery/04-new-app-and-listener-recovery.log) | Move to a password manager and delete the file; the copy in Secrets Manager is the one in use |
| S-04 | Argo CD local `admin` account in use; password was briefly a published placeholder | Medium | [03/06](../evidence/03-bootstrap/06-admin-password-reset.log) | Changed already. Next: SSO (Dex/OIDC with GitHub or IAM Identity Center), then `admin.enabled: false` |
| S-05 | Argo CD served with a self-signed certificate; arc-intel uses `ARGOCD_INSECURE=true`; access by port-forward | Medium (dev OK) | [03/04](../evidence/03-bootstrap/04-kps-fix-commit-and-missing-cli.log) | For production: internal ALB/Ingress with an ACM certificate, then remove `ARGOCD_INSECURE` |
| S-06 | Argo CD reads the repo with a personal fine-grained PAT (90-day expiry, ~2027-01-16) | Low | — | Replace with a GitHub App or read-only deploy key; until then, put the expiry in a calendar |
| S-07 | Dead secret `[REDACTED_SECRET_NAME]` restored during investigation | Low | [05/02](../evidence/05-github-app-recovery/02-restore-old-secret.log) | `aws secretsmanager delete-secret --secret-id [REDACTED_SECRET_NAME] --recovery-window-in-days 7` |
| S-08 | Docker on the operator Mac stores ECR credentials unencrypted (`[REDACTED_LOCAL_PATH] | Low | [01/01](../evidence/01-aws-and-generate/01-aws-phase.log) | Install `docker-credential-osxkeychain` or `amazon-ecr-credential-helper` |
| S-09 | Runner image pinned by tag, not digest; runner egress NetworkPolicy allows all egress | Low | [07/01](../evidence/07-compliance-remediation/01-pr3-sync-and-grade-a.log) | Pin `@sha256:`; restrict egress to GitHub, registries and required endpoints |
| S-10 | ARC-001 checks that a GitHub App is used, not that its credentials still work; dead Apps went unnoticed for days (issue 10) | Medium | [05/03](../evidence/05-github-app-recovery/03-jwt-credential-test.log) | Add a credential-validity check to arc-intel (JWT → `GET /app/installations`) with an alert |

## Follow-ups

| ID | Item | Priority | Notes |
|---|---|---|---|
| F-01 | Fix S-01 (stop using root) | P1 | Attribution then shows a named person/role instead of "root" |
| F-02 | Fix S-02 and S-03 | P1 | Five minutes in GitHub settings |
| F-03 | Run the smoke workflow `arc-smoke.yml` (`runs-on: arc-runner-set`) in `arc-runners-sandbox` | P1 | Proves a real job runs on the new App and pinned runner 2.338.0; not yet done |
| F-04 | arc-intel 0.1.1: Argo CD app + values path in compliance/fleet output; agent never suggests Helm/kubectl for Argo-managed sets; mark pre-adoption audit events | P2 | Fixes [issue 12](04-issues-and-resolutions.md#12-agent-answer-inaccuracies) |
| F-05 | GitHub webhook → Argo CD `/api/webhook` | P2 | Removes the 3-minute polling gap ([issue 13](04-issues-and-resolutions.md#13-first-drift-drill-not-reverted)) |
| F-06 | Branch protection on `main` (PR + 1 approval, no direct push) | P2 | See [07-git-history.md](07-git-history.md) |
| F-07 | Alertmanager receiver (Slack/PagerDuty) | P2 | Alerts currently go nowhere |
| F-08 | Alert on self-healed out-of-band writes | P2 | Gap: `ArcManualDrift` needs 30 min of persisting drift. Use a CloudWatch metric filter or an arc-intel counter |
| F-09 | Admission policy (Kyverno/OPA) on AutoscalingRunnerSet writes | P3 | Allow Argo CD + ARC controller + break-glass group only |
| F-10 | Copy session template/script fixes into `ajaychinthapalli/arc-intel` | P3 | `render.py` `controllerServiceAccount`, per-cluster secret name, `argocd` phase fixes, base OTel opt-out annotations, kube-prometheus-stack template |
| F-11 | S-04, S-05, S-06 hardening before any production use | P3 | |
| F-12 | Remove old Helm release history secrets (`sh.helm.release.v1.arc*`) after a stable period | P3 | Argo CD owns the releases now; don't run `helm upgrade` against them |
| F-13 | Credential-validity check (S-10) | P3 | |
| F-14 | Rename `CONTRIBUTING.mg` → `CONTRIBUTING.md`; consider `brew uninstall httpd` (installed only for `htpasswd`) | P4 | Housekeeping |
| F-15 | Run `scripts/collect-final-state.sh` and commit the snapshot | P2 | Closes this evidence pack with current-state proof |
