#!/usr/bin/env bash
set -euo pipefail

PROFILE="${AWS_PROFILE:-default}"
REGION="${AWS_REGION:-us-west-1}"
STACK_NAME="${PHASE10_STACK_NAME:-appointments-prod}"

get_output() {
  aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue | [0]" \
    --output text
}

CLUSTER_NAME="$(get_output EksClusterName)"
VPC_ID="$(get_output VpcId)"

echo "This updates kubeconfig and installs/updates AWS Load Balancer Controller into the cluster."
echo "Cluster: $CLUSTER_NAME"
read -r -p "Type INSTALL_CONTROLLER to continue: " confirm
if [[ "$confirm" != "INSTALL_CONTROLLER" ]]; then
  echo "Cancelled."
  exit 0
fi

aws eks update-kubeconfig \
  --name "$CLUSTER_NAME" \
  --region "$REGION" \
  --profile "$PROFILE"

helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo update

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set region="$REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller

kubectl -n kube-system rollout status deployment/aws-load-balancer-controller --timeout=300s
kubectl get ingressclass
