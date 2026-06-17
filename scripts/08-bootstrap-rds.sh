#!/usr/bin/env bash
set -euo pipefail

PROFILE="${AWS_PROFILE:-default}"
REGION="${AWS_REGION:-us-west-1}"
STACK_NAME="${PHASE10_STACK_NAME:-appointments-prod}"
WORKDIR="${PHASE10_WORKDIR:-/tmp/phase10-student-handoff}"

SQL_TEMPLATE="$WORKDIR/production/iac/cloudformation/db-bootstrap.sql"
JOB_TEMPLATE="$WORKDIR/production/iac/cloudformation/db-bootstrap-job.yml"
SQL_RENDERED="/tmp/appointments-db-bootstrap.sql"
JOB_RENDERED="/tmp/appointments-db-bootstrap-job.yml"

get_output() {
  aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue | [0]" \
    --output text
}

if [[ ! -f "$SQL_TEMPLATE" || ! -f "$JOB_TEMPLATE" ]]; then
  echo "Missing RDS bootstrap templates. Run scripts/01-extract-packages.sh first." >&2
  exit 1
fi

DB_NAME="$(get_output DatabaseName)"
DB_IAM_USER="$(get_output DatabaseIamUser)"
RDS_ENDPOINT="$(get_output RdsEndpoint)"

echo "This runs a temporary privileged RDS bootstrap job inside Kubernetes."
echo "Temporary Kubernetes Secret and ConfigMap will be deleted after completion."
read -r -p "Type BOOTSTRAP_RDS to continue: " confirm
if [[ "$confirm" != "BOOTSTRAP_RDS" ]]; then
  echo "Cancelled."
  exit 0
fi

read -r -p "RDS master username: " DB_MASTER_USER
read -r -s -p "RDS master password (hidden): " DB_MASTER_PASSWORD
echo
if [[ -z "$DB_MASTER_USER" || -z "$DB_MASTER_PASSWORD" ]]; then
  echo "RDS master username and password are required." >&2
  exit 1
fi

cp "$SQL_TEMPLATE" "$SQL_RENDERED"
sed -i "s/DB_NAME/$DB_NAME/g" "$SQL_RENDERED"
sed -i "s/DB_IAM_USER/$DB_IAM_USER/g" "$SQL_RENDERED"

cp "$JOB_TEMPLATE" "$JOB_RENDERED"
sed -i "s|RDS_ENDPOINT|$RDS_ENDPOINT|g" "$JOB_RENDERED"

kubectl create secret generic appointments-db-admin \
  --from-literal=username="$DB_MASTER_USER" \
  --from-literal=password="$DB_MASTER_PASSWORD" \
  --dry-run=client \
  -o yaml | kubectl apply -f -

unset DB_MASTER_PASSWORD

kubectl create configmap appointments-db-bootstrap-sql \
  --from-file=db-bootstrap.sql="$SQL_RENDERED" \
  --dry-run=client \
  -o yaml | kubectl apply -f -

kubectl delete job appointments-db-bootstrap --ignore-not-found
kubectl apply -f "$JOB_RENDERED"
kubectl wait --for=condition=complete --timeout=300s job/appointments-db-bootstrap
kubectl logs job/appointments-db-bootstrap

kubectl delete job appointments-db-bootstrap --ignore-not-found
kubectl delete secret appointments-db-admin --ignore-not-found
kubectl delete configmap appointments-db-bootstrap-sql --ignore-not-found
rm -f "$SQL_RENDERED" "$JOB_RENDERED"

echo "RDS bootstrap complete and temporary privileged materials removed."
