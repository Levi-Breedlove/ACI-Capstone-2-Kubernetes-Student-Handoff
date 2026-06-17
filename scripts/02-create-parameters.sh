#!/usr/bin/env bash
set -euo pipefail

WORKDIR="${PHASE10_WORKDIR:-/tmp/phase10-student-handoff}"
EXAMPLE="$WORKDIR/production/iac/cloudformation/parameters.example.json"
PARAM_FILE="${PHASE10_PARAM_FILE:-/tmp/appointments-prod-parameters.json}"

if [[ ! -f "$EXAMPLE" ]]; then
  echo "Missing $EXAMPLE. Run scripts/01-extract-packages.sh first." >&2
  exit 1
fi

cp "$EXAMPLE" "$PARAM_FILE"
chmod 600 "$PARAM_FILE"

set_param() {
  local key="$1"
  local value="$2"
  local tmp
  tmp="$(mktemp)"
  jq --arg key "$key" --arg value "$value" \
    'map(if .ParameterKey == $key then .ParameterValue = $value else . end)' \
    "$PARAM_FILE" > "$tmp"
  mv "$tmp" "$PARAM_FILE"
  chmod 600 "$PARAM_FILE"
}

prompt_default() {
  local label="$1"
  local default="$2"
  local value
  read -r -p "$label [$default]: " value
  printf '%s' "${value:-$default}"
}

echo "Creating local parameter file at $PARAM_FILE"
echo "This file can contain secrets. Do not commit it."
echo

source_provider="$(prompt_default 'SourceProvider: CodeCommit or GitHub' 'CodeCommit')"
pipeline_mode="$(prompt_default 'PipelineDeployMode for first launch' 'ManualApproval')"
repo_name="$(prompt_default 'CodeCommitRepositoryName' 'appointments-app')"
branch_name="$(prompt_default 'SourceBranchName' 'main')"
owner_tag="$(prompt_default 'OwnerTagValue' "$USER")"
repo_tag="$(prompt_default 'RepoTagValue' 'student-phase-10-handoff')"
allowed_hosts="$(prompt_default 'DjangoAllowedHosts for first ALB discovery' '*')"
csrf_origins="$(prompt_default 'DjangoCsrfTrustedOrigins for first launch' 'https://*.amazonaws.com')"

read -r -s -p "DatabaseMasterPassword (hidden): " db_password
echo
if [[ -z "$db_password" ]]; then
  echo "DatabaseMasterPassword cannot be empty." >&2
  exit 1
fi

set_param SourceProvider "$source_provider"
set_param PipelineDeployMode "$pipeline_mode"
set_param CodeCommitRepositoryName "$repo_name"
set_param SourceBranchName "$branch_name"
set_param OwnerTagValue "$owner_tag"
set_param RepoTagValue "$repo_tag"
set_param DjangoAllowedHosts "$allowed_hosts"
set_param DjangoCsrfTrustedOrigins "$csrf_origins"
set_param DatabaseMasterPassword "$db_password"

if [[ "$source_provider" == "GitHub" ]]; then
  github_repo="$(prompt_default 'GitHubFullRepositoryId, for example owner/repo' 'TBD_GITHUB_REPOSITORY')"
  codestar_arn="$(prompt_default 'CodeStarConnectionArn' 'TBD_CODESTAR_CONNECTION_ARN')"
  set_param GitHubFullRepositoryId "$github_repo"
  set_param CodeStarConnectionArn "$codestar_arn"
fi

echo
echo "Parameter file created: $PARAM_FILE"
echo "Permissions:"
ls -l "$PARAM_FILE"
echo
echo "Review parameter keys without printing secret values:"
jq -r '.[].ParameterKey' "$PARAM_FILE"
