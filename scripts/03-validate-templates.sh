#!/usr/bin/env bash
set -euo pipefail

PROFILE="${AWS_PROFILE:-default}"
REGION="${AWS_REGION:-us-west-1}"
WORKDIR="${PHASE10_WORKDIR:-/tmp/phase10-student-handoff}"

MAIN_TEMPLATE="$WORKDIR/production/iac/cloudformation/appointments-production.yaml"
CLOUDFRONT_TEMPLATE="$WORKDIR/production/iac/cloudformation/cloudfront-default-https.yaml"

if [[ ! -f "$MAIN_TEMPLATE" || ! -f "$CLOUDFRONT_TEMPLATE" ]]; then
  echo "Missing templates. Run scripts/01-extract-packages.sh first." >&2
  exit 1
fi

if command -v cfn-lint >/dev/null 2>&1; then
  echo "Running cfn-lint..."
  cfn-lint -i W1030 E3691 W1011 W3005 -- "$MAIN_TEMPLATE"
  cfn-lint "$CLOUDFRONT_TEMPLATE"
else
  echo "cfn-lint not installed; skipping local lint."
fi

echo "Running AWS validate-template for main stack..."
aws cloudformation validate-template \
  --template-body "file://$MAIN_TEMPLATE" \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query '{Capabilities:Capabilities,Description:Description}' \
  --output table

echo "Running AWS validate-template for CloudFront companion stack..."
aws cloudformation validate-template \
  --template-body "file://$CLOUDFRONT_TEMPLATE" \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query '{Capabilities:Capabilities,Description:Description}' \
  --output table
