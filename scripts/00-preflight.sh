#!/usr/bin/env bash
set -euo pipefail

PROFILE="${AWS_PROFILE:-default}"
REGION="${AWS_REGION:-us-west-1}"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

for cmd in aws git jq unzip kubectl helm openssl; do
  need "$cmd"
done

echo "Profile: $PROFILE"
echo "Region:  $REGION"
echo

aws --version
git --version
kubectl version --client=true
helm version --short
jq --version
unzip -v | head -n 2
openssl version

echo
echo "AWS identity:"
aws sts get-caller-identity \
  --profile "$PROFILE" \
  --query '{Account:Account,Arn:Arn}' \
  --output table

echo
echo "Configured profile region:"
aws configure get region --profile "$PROFILE" || true

echo
echo "Preflight complete. Confirm this is not the AWS root user before continuing."
