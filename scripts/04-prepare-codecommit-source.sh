#!/usr/bin/env bash
set -euo pipefail

PROFILE="${AWS_PROFILE:-default}"
REGION="${AWS_REGION:-us-west-1}"
WORKDIR="${PHASE10_WORKDIR:-/tmp/phase10-student-handoff}"
APP_DIR="$WORKDIR/production/appointments-app"
REPO_NAME="${CODECOMMIT_REPO_NAME:-appointments-app}"

if [[ ! -d "$APP_DIR" ]]; then
  echo "Missing $APP_DIR. Run scripts/01-extract-packages.sh first." >&2
  exit 1
fi

echo "This creates or updates CodeCommit repository '$REPO_NAME' in $REGION."
echo "It mutates AWS source state and may trigger a pipeline if one already points at this repo."
read -r -p "Type CREATE_CODECOMMIT to continue: " confirm
if [[ "$confirm" != "CREATE_CODECOMMIT" ]]; then
  echo "Cancelled."
  exit 0
fi

if aws codecommit get-repository \
  --repository-name "$REPO_NAME" \
  --region "$REGION" \
  --profile "$PROFILE" >/dev/null 2>&1; then
  echo "CodeCommit repository already exists: $REPO_NAME"
else
  aws codecommit create-repository \
    --repository-name "$REPO_NAME" \
    --repository-description "Phase 10 appointments app source" \
    --tags Project=appointments,Phase=10,Environment=prod,ManagedBy=student-handoff \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'repositoryMetadata.repositoryName' \
    --output text
fi

cd "$APP_DIR"
git init
git checkout -B main
git config user.name "Phase 10 Student"
git config user.email "student@example.local"
git config credential.helper "!aws --profile $PROFILE codecommit credential-helper \$@"
git config credential.UseHttpPath true
git add .
if git diff --cached --quiet; then
  echo "No source changes to commit locally."
else
  git commit -m "Initial Phase 10 production source"
fi

git remote remove origin >/dev/null 2>&1 || true
git remote add origin "https://git-codecommit.${REGION}.amazonaws.com/v1/repos/${REPO_NAME}"
git push -u origin main

echo "CodeCommit source prepared. Repository root is appointments-app/."
