#!/usr/bin/env bash
set -euo pipefail

PROFILE="${AWS_PROFILE:-default}"
REGION="${AWS_REGION:-us-west-1}"
PIPELINE_NAME="${PHASE10_PIPELINE_NAME:-appointments-prod-ApplicationPipeline}"

aws codepipeline get-pipeline-state \
  --name "$PIPELINE_NAME" \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query 'stageStates[].{stage:stageName,status:latestExecution.status}' \
  --output table

TOKEN="$(aws codepipeline get-pipeline-state \
  --name "$PIPELINE_NAME" \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query "stageStates[?stageName=='ApproveDeploy'].actionStates[?actionName=='ApproveDeploy'].latestExecution.token | [0]" \
  --output text)"

if [[ "$TOKEN" == "None" || -z "$TOKEN" ]]; then
  echo "No active ApproveDeploy token found."
  exit 0
fi

echo "ApproveDeploy is waiting."
read -r -p "Type APPROVE_DEPLOY to approve this pipeline gate: " confirm
if [[ "$confirm" != "APPROVE_DEPLOY" ]]; then
  echo "Cancelled."
  exit 0
fi

aws codepipeline put-approval-result \
  --pipeline-name "$PIPELINE_NAME" \
  --stage-name ApproveDeploy \
  --action-name ApproveDeploy \
  --result summary='Approved by student handoff script',status=Approved \
  --token "$TOKEN" \
  --region "$REGION" \
  --profile "$PROFILE"

echo "Approval submitted."
