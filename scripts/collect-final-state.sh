#!/usr/bin/env bash
# Read-only snapshot of [REDACTED_CLUSTER_NAME] for the evidence pack.
# Writes evidence/09-final-state/<UTC timestamp>/ : one file per check, plus SUMMARY.md.
#
# Never prints secret values: no `get secret -o yaml`, Secrets Manager is listed by name only.
# Needs: kubectl (context on the cluster), aws, jq; optional: gh (GitHub checks), argocd not required.
# Options (env):
#   CLUSTER_NAME (required)  AWS_REGION (us-east-2)  RUNNER_NS (arc-runners)  SCALE_SET (arc-runner-set)
#   GH_REPO (ajaychinthapalli/arc-intel)
#   ASK_AGENT=1   also ask the agent for the fleet grade over A2A (takes ~1 min)
#   MASK_IP=a.b.c.d   replace this IP in all output (e.g. your public IP)
set -uo pipefail
cd "$(dirname "$0")/.."

CLUSTER_NAME="${CLUSTER_NAME:?Set CLUSTER_NAME to the target cluster}"
AWS_REGION="${AWS_REGION:-us-east-2}"; export AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION"
RUNNER_NS="${RUNNER_NS:-arc-runners}"; SCALE_SET="${SCALE_SET:-arc-runner-set}"
GH_REPO="${GH_REPO:-ajaychinthapalli/arc-intel}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="evidence/09-final-state/${TS}"; mkdir -p "$OUT"
PIDS=()
cleanup() { for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null; done; }
trap cleanup EXIT

run() {  # run <file> <description> <command...>
  local f="$OUT/$1" d="$2"; shift 2
  { echo "# $d"; echo "# Captured: $(date -u +%FT%TZ)  Cluster: ${CLUSTER_NAME}"; echo "\$ $*"; echo
    bash -c "$*" 2>&1; local rc=$?; echo; echo "# exit: $rc"; } > "$f"
  [ -n "${MASK_IP:-}" ] && sed -i.bak "s/${MASK_IP//./\\.}/x.x.x.x/g" "$f" && rm -f "$f.bak"
  printf '  %-40s %s\n' "$1" "$d"
}

echo "Snapshot -> $OUT"

# Identity and cluster
run 01-caller-identity.txt   "Who is running this (ARN shows whether root is still used, finding S-01)" \
  "aws sts get-caller-identity --query Arn --output text; kubectl config current-context"
run 02-cluster.txt           "EKS version, audit logging, auth mode" \
  "aws eks describe-cluster --name $CLUSTER_NAME --query 'cluster.{version:version,logging:logging.clusterLogging[?enabled].types[],auth:accessConfig.authenticationMode}'"
run 03-access-entries.txt    "EKS access entries (named admin role instead of root, S-01)" \
  "aws eks list-access-entries --cluster-name $CLUSTER_NAME --output table"

# Argo CD
run 10-argocd-apps.txt       "Argo CD applications: sync, health, automated policy" \
  "kubectl -n argocd get applications -o custom-columns='APP:.metadata.name,PROJECT:.spec.project,SYNC:.status.sync.status,HEALTH:.status.health.status,AUTO:.spec.syncPolicy.automated'"
run 11-argocd-arc-revisions.txt "Revisions the ARC apps are synced to (multi-source: chart + Git)" \
  "for a in arc-controller arc-runners-${SCALE_SET}; do echo \"\$a: \$(kubectl -n argocd get application \$a -o jsonpath='{.status.sync.revisions}')  lastSync=\$(kubectl -n argocd get application \$a -o jsonpath='{.status.operationState.finishedAt}')\"; done"

# ARC
run 20-arc-scale-sets.txt    "AutoscalingRunnerSets and their Argo CD tracking" \
  "kubectl get autoscalingrunnersets -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,MIN:.spec.minRunners,MAX:.spec.maxRunners,VERSION:.metadata.labels.app\.kubernetes\.io/version,TRACKING:.metadata.annotations.argocd\.argoproj\.io/tracking-id'"
run 21-arc-runner-spec.txt   "Runner template: image, resources, securityContext, labels (compliance fixes from PR #3)" \
  "kubectl -n $RUNNER_NS get autoscalingrunnerset $SCALE_SET -o json | jq '{labels: .metadata.labels | with_entries(select(.key==\"owner\" or .key==\"cost-center\")), runner: (.spec.template.spec.containers[] | select(.name==\"runner\") | {image, resources, securityContext})}'"
run 22-arc-controller.txt    "Controller deployment and pod age" \
  "kubectl -n arc-systems get deploy,pods -o wide"
run 23-arc-listener.txt      "Listener status and recent log lines (GitHub connection)" \
  "kubectl -n arc-systems get pods -l app.kubernetes.io/component=runner-scale-set-listener; kubectl -n arc-systems logs -l app.kubernetes.io/component=runner-scale-set-listener --tail=8"
run 24-externalsecrets.txt   "ExternalSecrets status (values not shown)" \
  "kubectl get externalsecrets -A"

# arc-intel and agent
run 30-arc-intel.txt         "arc-intel deployment and pod" \
  "kubectl -n arc-intel get deploy,pods -o wide"
kubectl -n arc-intel port-forward svc/arc-intel-mcp 18080:8080 >/dev/null 2>&1 & PIDS+=($!)
for _ in $(seq 20); do curl -s -o /dev/null localhost:18080/healthz && break; sleep 1; done
mcp() {
  curl -s localhost:18080/mcp -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
    -H 'MCP-Protocol-Version: 2025-06-18' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":$2}}"
}
export -f mcp
run 31-fleet-report.json     "arc-intel fleet report (grade, score, postures)" \
  "mcp arc_fleet_report '{}' | jq '.result.structuredContent | {fleet_grade, fleet_score, postures, controllers: [.controllers[]? | {name, version}]}'"
run 32-drift.json            "arc-intel drift check: source of truth, identity source, GitOps context" \
  "mcp arc_detect_drift '{\"namespace\":\"$RUNNER_NS\",\"name\":\"$SCALE_SET\"}' | jq '.result.structuredContent | {baseline_source, drifted, identity_source, gitops, summary}'"
run 33-compliance.json       "arc-intel compliance check" \
  "mcp arc_check_compliance '{\"namespace\":\"$RUNNER_NS\",\"name\":\"$SCALE_SET\"}' | jq '.result.structuredContent'"
run 34-kagent.txt            "Kagent agents, tool servers, model configs" \
  "kubectl -n kagent get agents,remotemcpservers,modelconfigs"
if [ "${ASK_AGENT:-0}" = 1 ]; then
  kubectl -n kagent port-forward svc/kagent-controller 8083:8083 >/dev/null 2>&1 & PIDS+=($!); sleep 3
  run 35-agent-fleet-grade.md "Agent answer over A2A: fleet grade" \
    "curl -s --max-time 180 http://localhost:8083/api/a2a/kagent/arc-compliance-agent/ -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"message/send\",\"params\":{\"message\":{\"role\":\"user\",\"messageId\":\"m-$TS\",\"parts\":[{\"kind\":\"text\",\"text\":\"What is our fleet grade now? Any drift or out-of-band changes in the last 24 hours?\"}]}}}' | jq -r '[.. | objects | select(.kind? == \"text\") | .text] | last'"
fi

# AWS
run 40-pod-identity.txt      "Pod Identity associations" \
  "aws eks list-pod-identity-associations --cluster-name $CLUSTER_NAME --query 'associations[].{ns:namespace,sa:serviceAccount}' --output table"
run 41-secrets-manager.txt   "Secrets Manager arc/* (names and dates only, finding S-07)" \
  "aws secretsmanager list-secrets --include-planned-deletion --filters Key=name,Values=arc/ --query 'SecretList[].{name:Name,changed:LastChangedDate,deletion:DeletedDate}' --output table"
run 42-ecr.txt               "arc-intel image in ECR" \
  "aws ecr describe-images --repository-name arc-intel-mcp --query 'imageDetails[].{tags:imageTags,digest:imageDigest,pushed:imagePushedAt,scan:imageScanStatus.status}' --output table"

# GitHub
if command -v gh >/dev/null; then
  run 50-git-main.txt        "Latest commits on main (what Argo CD deploys)" \
    "gh api 'repos/$GH_REPO/commits?sha=main&per_page=12' --jq '.[] | \"\(.sha[0:7])  \(.commit.author.date)  \(.commit.message | split(\"\n\")[0])\"'"
  run 51-prs.txt             "Merged pull requests" \
    "gh pr list -R $GH_REPO --state merged --limit 20"
  run 52-branch-protection.txt "Branch protection on main (follow-up F-06)" \
    "gh api repos/$GH_REPO/branches/main/protection --jq '{required_reviews: .required_pull_request_reviews.required_approving_review_count, enforce_admins: .enforce_admins.enabled}' 2>&1 || true"
  run 53-app-installations.txt "GitHub App installations and repository selection (finding S-02)" \
    "gh api user/installations --jq '.installations[] | \"\(.app_slug)  installation=\(.id)  repos=\(.repository_selection)\"'"
fi

# Summary
body() { sed -n '5,$p' "$OUT/$1" | sed '/^# exit:/d'; }
{
  echo "# Final-state snapshot ${TS}"; echo
  echo "| Check | Value |"; echo "|---|---|"
  echo "| Caller | \`$(sed -n 5p "$OUT/01-caller-identity.txt")\` |"
  echo "| Argo CD apps Synced+Healthy | $(grep -cE ' Synced +Healthy ' "$OUT/10-argocd-apps.txt") of $(grep -cE '^[a-z]' "$OUT/10-argocd-apps.txt") |"
  echo "| Fleet | \`$(body 31-fleet-report.json | jq -c '{fleet_grade,fleet_score,postures}' 2>/dev/null || echo unavailable)\` |"
  echo "| Drift | \`$(body 32-drift.json | jq -c '{baseline_source,drifted,identity_source}' 2>/dev/null || echo unavailable)\` |"
  echo "| Listener | $(awk '$1 ~ /-listener$/ {print $3; exit}' "$OUT/23-arc-listener.txt") |"
  [ -f "$OUT/53-app-installations.txt" ] && echo "| GitHub App installs | $(body 53-app-installations.txt | grep -E '^[^$#].*installation=' | tr '\n' ';') |"
  echo; echo "Files:"; ls "$OUT" | sed 's/^/- /'
} > "$OUT/SUMMARY.md"

echo; cat "$OUT/SUMMARY.md"
echo; echo "Review, then: git add $OUT && git commit -m \"Final-state snapshot $TS\" && git push"
