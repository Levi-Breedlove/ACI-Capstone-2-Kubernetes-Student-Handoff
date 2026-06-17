#!/usr/bin/env bash
set -euo pipefail

PROFILE="${AWS_PROFILE:-default}"
REGION="${AWS_REGION:-us-west-1}"
WORKDIR="${PHASE10_WORKDIR:-/tmp/phase10-student-handoff}"
PARAM_FILE="${PHASE10_PARAM_FILE:-/tmp/appointments-prod-parameters.json}"
STACK_NAME="${PHASE10_STACK_NAME:-appointments-prod}"
TEMPLATE="$WORKDIR/production/iac/cloudformation/appointments-production.yaml"

if [[ ! -f "$TEMPLATE" ]]; then
  echo "Missing $TEMPLATE. Run scripts/01-extract-packages.sh first." >&2
  exit 1
fi
if [[ ! -f "$PARAM_FILE" ]]; then
  echo "Missing $PARAM_FILE. Run scripts/02-create-parameters.sh first." >&2
  exit 1
fi

if aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --profile "$PROFILE" >/dev/null 2>&1; then
  echo "Stack already exists: $STACK_NAME"
  exit 1
fi

OWNER_TAG="$(jq -r '.[] | select(.ParameterKey=="OwnerTagValue") | .ParameterValue // "student"' "$PARAM_FILE")"
REPO_TAG="$(jq -r '.[] | select(.ParameterKey=="RepoTagValue") | .ParameterValue // "student-phase-10-handoff"' "$PARAM_FILE")"

echo "This creates billable AWS resources under CloudFormation stack '$STACK_NAME'."
echo "Expected services include EKS, EC2, NAT Gateway, RDS, ALB after Ingress, ECR, DynamoDB, CodePipeline, CodeBuild, S3, and CloudWatch Logs."
read -r -p "Type CREATE_STACK to continue: " confirm
if [[ "$confirm" != "CREATE_STACK" ]]; then
  echo "Cancelled."
  exit 0
fi

aws cloudformation create-stack \
  --stack-name "$STACK_NAME" \
  --template-body "file://$TEMPLATE" \
  --parameters "file://$PARAM_FILE" \
  --capabilities CAPABILITY_IAM \
  --tags \
    Key=Project,Value=appointments \
    Key=Phase,Value=10 \
    Key=Environment,Value=prod \
    Key=Owner,Value="$OWNER_TAG" \
    Key=Repo,Value="$REPO_TAG" \
    Key=ManagedBy,Value=student-handoff \
  --region "$REGION" \
  --profile "$PROFILE"

echo "Waiting for stack-create-complete..."
aws cloudformation wait stack-create-complete \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --profile "$PROFILE"

echo "Stack created."
aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query 'Stacks[0].Outputs[].{Key:OutputKey,Value:OutputValue}' \
  --output table
