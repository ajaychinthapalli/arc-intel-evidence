# 2. Environment and inventory

## Cluster before the work (15:19, [evidence](../evidence/00-discovery/02-cluster-inventory.log))

| Item | Value |
|---|---|
| Cluster | `[REDACTED_CLUSTER_NAME]`, EKS 1.36, us-east-2, auth mode `API_AND_CONFIG_MAP` |
| Control-plane logging | `api`, `audit`, `authenticator` enabled |
| Add-ons | amazon-cloudwatch-observability, aws-ebs-csi-driver, coredns, eks-pod-identity-agent, kube-proxy, vpc-cni |
| Nodes | 5 × amd64, v1.36.4 (3 default, 2 in node group `agents`) |
| Helm releases | `arc` 0.14.2, `arc-runner-set` 0.14.2, aws-load-balancer-controller 3.5.0, kagent 0.10.3 (+ crds), karpenter 1.14.1, radar 1.15.0 |
| Scale sets | `arc-runners/arc-runner-set`, min 0, max 3, Helm-owned |
| Kagent | ModelConfigs `bedrock-native` (Bedrock, `us.anthropic.claude-sonnet-4-6`) and `default-model-config`; agent `arc-upgrade-readiness` |
| Not present | Argo CD, External Secrets, Prometheus Operator |
| NetworkPolicy enforcement | VPC CNI, enabled |

## Created in AWS

| Resource | Name / ID | Purpose | Evidence |
|---|---|---|---|
| ECR image | `[REDACTED_ECR_URI]` (manifest list `sha256:29a5512a…7d66`) | arc-intel MCP server | [01/01](../evidence/01-aws-and-generate/01-aws-phase.log) |
| IAM role | `[REDACTED_CLUSTER_NAME]-arc-intel-audit` | Logs Insights on `/aws/eks/[REDACTED_CLUSTER_NAME]/cluster` only | [01/01](../evidence/01-aws-and-generate/01-aws-phase.log) |
| IAM role | `[REDACTED_CLUSTER_NAME]-external-secrets` | Read Secrets Manager `arc/*` | [01/01](../evidence/01-aws-and-generate/01-aws-phase.log) |
| Pod Identity | `arc-intel/arc-intel`, `external-secrets/external-secrets` | Bind the roles above | [01/01](../evidence/01-aws-and-generate/01-aws-phase.log) |
| Secret | `arc/[REDACTED_CLUSTER_NAME]/github-app` (v`3101423e` copy of cluster Secret; v`7a367364` new App) | ARC GitHub App credentials, per cluster | [01/03](../evidence/01-aws-and-generate/03-per-cluster-secret-and-generate.log), [05/04](../evidence/05-github-app-recovery/04-new-app-and-listener-recovery.log) |
| Secret | `arc/argocd-token` | arc-intel read-only Argo CD API token | [02/02](../evidence/02-argocd/02-argocd-token-and-initial-secret.log) |
| Secret (pre-existing) | `[REDACTED_SECRET_NAME]` | Dead credentials; restored for comparison, **to be deleted** | [05/02](../evidence/05-github-app-recovery/02-restore-old-secret.log) |
| Add-on config | amazon-cloudwatch-observability: `arc-intel` added to Application Signals exclusions (update `2395b293…`) | Stop Java agent injection | [04/04](../evidence/04-arc-adoption/04-cloudwatch-addon-exclusion.log) |

Reused, not created: IRSA role `eksctl-[REDACTED_CLUSTER_NAME]-addon-iamserviceaccount-Role1-…` on ServiceAccount
`kagent/arc-readiness-agent` for Bedrock access ([00/04](../evidence/00-discovery/04-agent-irsa-check.log)).

## Created in GitHub

| Resource | Detail |
|---|---|
| Repo `ajaychinthapalli/arc-intel` | Platform code + `clusters/[REDACTED_CLUSTER_NAME]/`; Argo CD follows `main` |
| Fine-grained PAT `argocd-…` | Contents read-only on `arc-intel` only, 90-day expiry; stored only as Argo CD Secret `repo-gitops` |
| GitHub App `[REDACTED_GITHUB_APP_NAME]` | App ID [REDACTED_GITHUB_APP_ID], installation [REDACTED_GITHUB_INSTALLATION_ID]; Administration RW. **Currently installed on all repositories** (see follow-ups) |

## Kubernetes: Argo CD applications (final, [evidence](../evidence/06-verify-and-agent/01-verify.log))

| Application | Project | Contents | Sync policy |
|---|---|---|---|
| `[REDACTED_CLUSTER_NAME]-root` | default | App of apps (`clusters/[REDACTED_CLUSTER_NAME]/apps`) | automated, prune, self-heal |
| `external-secrets` | arc-platform | ESO chart | automated, prune, self-heal |
| `platform-secrets` | arc-platform | ClusterSecretStore, `arc-github-app` ExternalSecret (Merge), runner egress NetworkPolicy | automated, prune, self-heal |
| `kube-prometheus-stack` | arc-platform | Prometheus, Grafana, Alertmanager | automated, prune, self-heal |
| `arc-intel` | arc-platform | MCP server, RBAC, policy, Argo CD token ExternalSecret | automated, prune, self-heal |
| `arc-intel-monitoring` | arc-platform | ServiceMonitor, PrometheusRule (5 alerts) | automated, prune, self-heal |
| `arc-compliance-agent` | arc-platform | Kagent Agent + RemoteMCPServer | automated, prune, self-heal |
| `arc-intel-digest` | arc-platform | Daily digest CronJob | automated, prune, self-heal |
| `arc-controller` | arc-platform | Adopted Helm release `arc` (chart 0.14.2) | manual → **automated, self-heal, no prune** (PR #4) |
| `arc-runners-arc-runner-set` | arc-runners | Adopted Helm release via ApplicationSet (git directory generator) | manual → **automated, self-heal, no prune** (PR #4) |

Adopted ARC apps have no resources finalizer and the ApplicationSet uses `preserveResourcesOnDeletion`, so
deleting an Application never deletes runners.

## Versions

| Component | Version |
|---|---|
| EKS / Kubernetes | 1.36 (nodes v1.36.4) |
| Argo CD Helm chart | 10.10.5 |
| ARC charts / controller | 0.14.2 |
| Actions runner image | `ghcr.io/actions/actions-runner:2.338.0` (was `latest`) |
| Kagent | 0.10.3 |
| arc-intel | 0.1.0 |
| kubectl (operator) | 1.37.0 |
| Helm (operator) | 4.2.4 |
