#!/usr/bin/env bash
set -euo pipefail

PROFILE="${AWS_PROFILE:-default}"
REGION="${AWS_REGION:-us-west-1}"

echo "This script is a teardown planning helper. It does not delete resources."
echo "Use it before running any destructive cleanup."
echo

echo "CloudFormation stacks:"
aws cloudformation describe-stacks \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query 'Stacks[].{Name:StackName,Status:StackStatus}' \
  --output table || true

echo
echo "EKS clusters:"
aws eks list-clusters \
  --region "$REGION" \
  --profile "$PROFILE" \
  --output table || true

echo
echo "Load balancers:"
aws elbv2 describe-load-balancers \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query 'LoadBalancers[].{Name:LoadBalancerName,Type:Type,State:State.Code}' \
  --output table || true

echo
echo "RDS instances:"
aws rds describe-db-instances \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query 'DBInstances[].{Id:DBInstanceIdentifier,Class:DBInstanceClass,Status:DBInstanceStatus}' \
  --output table || true

echo
echo "Recommended teardown order:"
echo "1. Delete Kubernetes app/Ingress resources first."
echo "2. Wait for the Kubernetes-managed ALB to disappear."
echo "3. Delete the CloudFront companion stack if it exists."
echo "4. Delete the SSM origin-header parameter if CloudFront hardening created one."
echo "5. Empty/delete ECR images and artifact bucket if CloudFormation cannot delete them."
echo "6. Delete the main CloudFormation stack."
echo "7. Confirm no RDS snapshots, NAT Gateways, EIPs/public IPv4s, ALBs, EKS clusters, EC2 nodes, or demo SSM parameters remain unless intentionally retained."
echo
echo "Destructive cleanup should require a separate explicit approval."
