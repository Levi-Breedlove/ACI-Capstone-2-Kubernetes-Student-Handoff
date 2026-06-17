#!/usr/bin/env bash
set -euo pipefail

echo "This creates/updates the Django Kubernetes Secret and enables ALB pod readiness gates for the default namespace."
read -r -p "Type CREATE_K8S_SECRET to continue: " confirm
if [[ "$confirm" != "CREATE_K8S_SECRET" ]]; then
  echo "Cancelled."
  exit 0
fi

DJANGO_SECRET_KEY="${DJANGO_SECRET_KEY:-}"
if [[ -z "$DJANGO_SECRET_KEY" ]]; then
  DJANGO_SECRET_KEY="$(openssl rand -hex 48)"
fi

kubectl create secret generic appointments-django \
  --from-literal=secret-key="$DJANGO_SECRET_KEY" \
  --dry-run=client \
  -o yaml | kubectl apply -f -

unset DJANGO_SECRET_KEY

kubectl label namespace default elbv2.k8s.aws/pod-readiness-gate-inject=enabled --overwrite
kubectl get namespace default --show-labels
kubectl get secret appointments-django
