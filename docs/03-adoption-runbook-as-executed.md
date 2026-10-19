# 3. Adoption runbook, as executed

The commands actually run on `[REDACTED_CLUSTER_NAME]`, in order, from the `arc-intel` repo root
(`[REDACTED_LOCAL_PATH] `S=demo/scripts/adopt-existing-eks.sh`. Deviations from the
plan are marked **⚠** and explained in [04-issues-and-resolutions.md](04-issues-and-resolutions.md).

## Phase 0: discover (read-only)

```bash
kubectl get ns
helm list -A
kubectl get autoscalingrunnersets -A -o custom-columns=...
aws eks describe-cluster --name [REDACTED_CLUSTER_NAME] --query 'cluster.{version,logging,oidc,auth}'
aws eks list-addons --cluster-name [REDACTED_CLUSTER_NAME]
$S discover
kubectl -n kagent get sa arc-readiness-agent -o jsonpath='{.metadata.annotations}'   # IRSA confirmed
```
Evidence: [00-discovery/](../evidence/00-discovery/)

## Phase 1: AWS resources

```bash
$S aws     # ECR image, IAM roles, Pod Identity, Secrets Manager
```
**⚠ Issue 1.** Pre-existing `[REDACTED_SECRET_NAME]` didn't match the cluster Secret, so a per-cluster secret was created:
```bash
aws secretsmanager create-secret --name arc/[REDACTED_CLUSTER_NAME]/github-app --secret-string "$K8S"
```
Evidence: [01-aws-and-generate/01–03](../evidence/01-aws-and-generate/)

## Phase 2: generate the cluster folder

```bash
export GITOPS_REPO=https://github.com/ajaychinthapalli/arc-intel.git
$S generate
sed -i '' 's#key: [REDACTED_SECRET_NAME]}#key: arc/[REDACTED_CLUSTER_NAME]/github-app}#' clusters/[REDACTED_CLUSTER_NAME]/manifests/platform-secrets/secrets.yaml
grep -rniE 'BEGIN (RSA )?PRIVATE KEY|ghp_|github_pat_' clusters/[REDACTED_CLUSTER_NAME]      # clean
```
Evidence: [01-aws-and-generate/03–04](../evidence/01-aws-and-generate/)

## Phase 3: Argo CD

```bash
read -rs GITOPS_TOKEN && export GITOPS_TOKEN GITOPS_USERNAME=ajaychinthapalli
$S argocd
```
**⚠ Issue 2.** The token step failed, so the arc-intel token was created by hand (`/api/v1/session`, then
`/api/v1/account/arc-intel/token`, piped to `aws secretsmanager create-secret --name arc/argocd-token`).
**⚠ Issue 3.** A stale port-forward was removed with `lsof -ti tcp:18443 | xargs kill`. The initial admin
secret was then saved and deleted.
**⚠ Issue 4.** Argo CD follows `main`; work was on `develop`. PR #2 had already merged it.
Evidence: [02-argocd/](../evidence/02-argocd/)

## Phase 4: bootstrap

```bash
$S bootstrap                     # kubectl apply -f clusters/[REDACTED_CLUSTER_NAME]/root-app.yaml
```
**⚠ Issue 5.** kube-prometheus-stack was rejected by the AppProject. Fixed in Git (`4e79346`), then:
```bash
brew install argocd                                     # ⚠ issue 6
kubectl -n argocd port-forward svc/argocd-server 8080:443 &
argocd login localhost:8080 --username admin --insecure # ⚠ issue 7 (password reset, then changed)
argocd app terminate-op kube-prometheus-stack
argocd app get kube-prometheus-stack --hard-refresh
argocd app sync kube-prometheus-stack
```
Evidence: [03-bootstrap/](../evidence/03-bootstrap/)

## Phase 5: adopt ARC (review each diff, then sync by hand)

```bash
argocd app diff arc-controller          # tracking annotations only
argocd app sync arc-controller
kubectl -n arc-systems get pods -l app.kubernetes.io/name=gha-rs-controller   # AGE 5d20h → no restart
```
**⚠ Issue 8.** Runner set ComparisonError, fixed in Git (`fbe7656`):
```bash
argocd app diff arc-runners-arc-runner-set   # tracking annotation + values-hash only
argocd app sync arc-runners-arc-runner-set
```
**⚠ Issue 9.** arc-intel pods refused. The CloudWatch add-on exclusion wasn't enough, so pod opt-out
annotations went in by commit (`f7fc69d`).
Evidence: [04-arc-adoption/](../evidence/04-arc-adoption/)

## Phase 5b: unplanned, GitHub App recovery

**⚠ Issue 10.** The listener restart exposed dead GitHub App credentials. A new App was created and stored:
```bash
jq -n --arg id 5374908 --arg inst 172872993 --rawfile key [REDACTED_PRIVATE_KEY_PATH] '{...}' \
 | aws secretsmanager put-secret-value --secret-id arc/[REDACTED_CLUSTER_NAME]/github-app --secret-string file:///dev/stdin
kubectl -n arc-runners annotate externalsecret arc-github-app force-sync="$(date +%s)" --overwrite
kubectl -n arc-systems delete pod -l app.kubernetes.io/component=runner-scale-set-listener
```
Evidence: [05-github-app-recovery/](../evidence/05-github-app-recovery/)

## Phase 6: verify

```bash
$S verify
# ⚠ issue 11: no `kagent invoke`; agent queried over A2A instead:
kubectl -n kagent port-forward svc/kagent-controller 8083:8083 &
ask "How compliant are our ARC runners? Worst issues first, and how do I fix each in Git?"
```
Evidence: [06-verify-and-agent/](../evidence/06-verify-and-agent/)

## Phase 7: fix findings by PR (Git → Argo CD)

PR #3. See [05-compliance-remediation.md](05-compliance-remediation.md).

## Phase 8: enable self-heal and run the drift drill

PR #4. See [06-drift-drill.md](06-drift-drill.md).
