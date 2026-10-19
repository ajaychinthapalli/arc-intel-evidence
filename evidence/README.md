# Raw evidence

Unedited terminal output from the operator's machine, one file per step, in the order run. Each file starts
with a header giving the capture time (America/Phoenix, UTC-7), the cluster and the source. The only edits
are the masked public IP (`[REDACTED_IP_ADDRESS]`) and one removed terminal escape sequence.

| Folder | Phase |
|---|---|
| `00-discovery/` | Read-only inventory of the existing cluster |
| `01-aws-and-generate/` | ECR, IAM, Pod Identity, Secrets Manager; rendering `clusters/[REDACTED_CLUSTER_NAME]/` |
| `02-argocd/` | Argo CD install, repo credentials, arc-intel token, branch/PR checks |
| `03-bootstrap/` | Root app, kube-prometheus-stack fix, Argo CD login |
| `04-arc-adoption/` | Adopting the ARC controller and runner set; starting arc-intel |
| `05-github-app-recovery/` | Diagnosing dead GitHub Apps; new App; listener recovery |
| `06-verify-and-agent/` | End-to-end verify; first agent answer |
| `07-compliance-remediation/` | PR #3 and the 78 → 100 rescore |
| `08-self-heal-and-drift-drill/` | PR #4 and both drift drills |
| `09-final-state/` | Created by `scripts/collect-final-state.sh` |

See [../TIMELINE.md](../TIMELINE.md) for what each file shows.
