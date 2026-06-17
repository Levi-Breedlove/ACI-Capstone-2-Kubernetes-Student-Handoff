#!/usr/bin/env bash
set -euo pipefail

PROFILE="${AWS_PROFILE:-default}"
REGION="${AWS_REGION:-us-west-1}"
WORKDIR="${PHASE10_WORKDIR:-/tmp/phase10-student-handoff}"
MAIN_STACK="${PHASE10_STACK_NAME:-appointments-prod}"
CLOUDFRONT_STACK="${PHASE10_CLOUDFRONT_STACK_NAME:-appointments-prod-cloudfront-https}"
MAIN_TEMPLATE="$WORKDIR/production/iac/cloudformation/appointments-production.yaml"
CLOUDFRONT_TEMPLATE="$WORKDIR/production/iac/cloudformation/cloudfront-default-https.yaml"
OWNER_TAG="${OWNER_TAG_VALUE:-${USER:-student}}"
REPO_TAG="${REPO_TAG_VALUE:-student-phase-10-handoff}"
ORIGIN_HEADER_NAME="${CLOUDFRONT_ORIGIN_HEADER_NAME:-X-Origin-Verify}"
ORIGIN_HEADER_VALUE="${CLOUDFRONT_ORIGIN_HEADER_VALUE:-}"
ORIGIN_HEADER_SSM_PARAMETER="${CLOUDFRONT_ORIGIN_HEADER_SSM_PARAMETER:-/appointments/prod/cloudfront-origin-header-value}"
EDGE_MODE="${PHASE10_EDGE_MODE:-full}"
SECRET_STATE_DIR="${PHASE10_SECRET_STATE_DIR:-$WORKDIR/secrets}"
HEADER_STATE_FILE="${PHASE10_ORIGIN_HEADER_FILE:-$SECRET_STATE_DIR/cloudfront-origin-header.env}"

case "$EDGE_MODE" in
  cloudfront-only|harden-origin|full)
    ;;
  *)
    echo "PHASE10_EDGE_MODE must be cloudfront-only, harden-origin, or full." >&2
    exit 1
    ;;
esac

if [[ ! -f "$MAIN_TEMPLATE" || ! -f "$CLOUDFRONT_TEMPLATE" ]]; then
  echo "Missing CloudFormation templates. Run scripts/01-extract-packages.sh first." >&2
  exit 1
fi

ALB_DNS="$(kubectl get ingress appointments-ingress -n default -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
if [[ -z "$ALB_DNS" ]]; then
  echo "Ingress does not have an ALB DNS name yet." >&2
  exit 1
fi

echo "This creates or validates one CloudFront distribution in front of the existing ALB."
echo "It does not create Route 53, ACM, WAF, a second ALB, or a second target group."
echo "Mode: $EDGE_MODE"
if [[ "$EDGE_MODE" == "cloudfront-only" ]]; then
  echo "This checkpoint adds CloudFront HTTPS first and intentionally leaves direct ALB access unchanged."
else
  echo "This also restricts ALB listener access to CloudFront origin-facing traffic and requires a CloudFront origin header before forwarding to the app."
fi
echo "For an existing deployment, refresh CodeCommit from the current package before starting the pipeline so DeployPods has the hardened buildspec and Ingress."
read -r -p "Type ENABLE_CLOUDFRONT to continue: " confirm
if [[ "$confirm" != "ENABLE_CLOUDFRONT" ]]; then
  echo "Cancelled."
  exit 0
fi

if [[ -z "$ORIGIN_HEADER_VALUE" && -f "$HEADER_STATE_FILE" ]]; then
  stored_header_name="$(sed -n 's/^CLOUDFRONT_ORIGIN_HEADER_NAME=//p' "$HEADER_STATE_FILE" | head -n 1)"
  stored_header_value="$(sed -n 's/^CLOUDFRONT_ORIGIN_HEADER_VALUE=//p' "$HEADER_STATE_FILE" | head -n 1)"
  if [[ -n "$stored_header_name" ]]; then
    ORIGIN_HEADER_NAME="$stored_header_name"
  fi
  ORIGIN_HEADER_VALUE="$stored_header_value"
fi

case "$ORIGIN_HEADER_NAME" in
  *[!A-Za-z0-9-]*|"")
    echo "CLOUDFRONT_ORIGIN_HEADER_NAME must contain only letters, numbers, and hyphens." >&2
    exit 1
    ;;
esac

generated_origin_header=false
if [[ -z "$ORIGIN_HEADER_VALUE" ]]; then
  ORIGIN_HEADER_VALUE="$(openssl rand -hex 32)"
  generated_origin_header=true
fi

case "$ORIGIN_HEADER_VALUE" in
  *[!A-Za-z0-9._~-]*)
    echo "CLOUDFRONT_ORIGIN_HEADER_VALUE contains unsupported characters. Use a generated hex or URL-safe value." >&2
    exit 1
    ;;
esac

case "$ORIGIN_HEADER_SSM_PARAMETER" in
  /*)
    ;;
  *)
    echo "CLOUDFRONT_ORIGIN_HEADER_SSM_PARAMETER must be an absolute SSM parameter path such as /appointments/prod/cloudfront-origin-header-value." >&2
    exit 1
    ;;
esac

if [[ "$generated_origin_header" == "true" || ! -f "$HEADER_STATE_FILE" ]]; then
  mkdir -p "$SECRET_STATE_DIR"
  chmod 700 "$SECRET_STATE_DIR"
  {
    printf 'CLOUDFRONT_ORIGIN_HEADER_NAME=%s\n' "$ORIGIN_HEADER_NAME"
    printf 'CLOUDFRONT_ORIGIN_HEADER_VALUE=%s\n' "$ORIGIN_HEADER_VALUE"
  } > "$HEADER_STATE_FILE"
  chmod 600 "$HEADER_STATE_FILE"
  echo "Generated and stored the CloudFront origin header in $HEADER_STATE_FILE. The value is not printed."
fi

CLOUDFRONT_PREFIX_LIST_ID=""
if [[ "$EDGE_MODE" != "cloudfront-only" ]]; then
  echo "Storing the CloudFront origin header in SSM Parameter Store SecureString: $ORIGIN_HEADER_SSM_PARAMETER"
  aws ssm put-parameter \
    --name "$ORIGIN_HEADER_SSM_PARAMETER" \
    --type SecureString \
    --value "$ORIGIN_HEADER_VALUE" \
    --overwrite \
    --region "$REGION" \
    --profile "$PROFILE" >/dev/null

  CLOUDFRONT_PREFIX_LIST_ID="${ALB_SECURITY_GROUP_PREFIX_LISTS:-}"
  if [[ -z "$CLOUDFRONT_PREFIX_LIST_ID" ]]; then
    CLOUDFRONT_PREFIX_LIST_ID="$(aws ec2 describe-managed-prefix-lists \
      --region "$REGION" \
      --profile "$PROFILE" \
      --filters Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing \
      --query 'PrefixLists[0].PrefixListId' \
      --output text)"
  fi

  if [[ -z "$CLOUDFRONT_PREFIX_LIST_ID" || "$CLOUDFRONT_PREFIX_LIST_ID" == "None" ]]; then
    echo "Could not find the AWS-managed CloudFront origin-facing prefix list in $REGION." >&2
    exit 1
  fi

  ALB_CERT_ARN="$(aws cloudformation describe-stacks \
    --stack-name "$MAIN_STACK" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "Stacks[0].Parameters[?ParameterKey=='AlbCertificateArn'].ParameterValue | [0]" \
    --output text 2>/dev/null || true)"

  required_prefix_weight=55
  if [[ -n "$ALB_CERT_ARN" && "$ALB_CERT_ARN" != "None" ]]; then
    required_prefix_weight=110
  fi

  sg_rule_quota="$(aws service-quotas list-service-quotas \
    --service-code vpc \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "Quotas[?QuotaCode=='L-0EA8095F'].Value | [0]" \
    --output text)"
  sg_rule_quota_int="${sg_rule_quota%.*}"

  if ! [[ "$sg_rule_quota_int" =~ ^[0-9]+$ ]]; then
    echo "Could not determine security-group rule quota. Stop here instead of applying a broader ALB rule." >&2
    exit 1
  fi

  if (( sg_rule_quota_int < required_prefix_weight )); then
    echo "Security-group rule quota is $sg_rule_quota_int, but the CloudFront prefix-list path needs at least $required_prefix_weight rule weight." >&2
    echo "Request a quota increase or keep the stack undeployed; do not fall back to 0.0.0.0/0 for this hardened demo." >&2
    exit 1
  fi
fi

CF_PARAMS="$(mktemp)"
PARAM_UPDATE="$(mktemp)"
chmod 600 "$CF_PARAMS" "$PARAM_UPDATE"
trap 'rm -f "$CF_PARAMS" "$PARAM_UPDATE"' EXIT

jq -n \
  --arg origin "$ALB_DNS" \
  --arg headerName "$ORIGIN_HEADER_NAME" \
  --arg headerValue "$ORIGIN_HEADER_VALUE" \
  --arg owner "$OWNER_TAG" \
  --arg repo "$REPO_TAG" \
  '[
    {ParameterKey:"OriginDnsName",ParameterValue:$origin},
    {ParameterKey:"OriginAccessHeaderName",ParameterValue:$headerName},
    {ParameterKey:"OriginAccessHeaderValue",ParameterValue:$headerValue},
    {ParameterKey:"PriceClass",ParameterValue:"PriceClass_100"},
    {ParameterKey:"ProjectName",ParameterValue:"appointments"},
    {ParameterKey:"EnvironmentName",ParameterValue:"prod"},
    {ParameterKey:"PhaseTagValue",ParameterValue:"10"},
    {ParameterKey:"OwnerTagValue",ParameterValue:$owner},
    {ParameterKey:"RepoTagValue",ParameterValue:$repo},
    {ParameterKey:"ManagedByTagValue",ParameterValue:"student-handoff"}
  ]' > "$CF_PARAMS"

if aws cloudformation describe-stacks \
  --stack-name "$CLOUDFRONT_STACK" \
  --region "$REGION" \
  --profile "$PROFILE" >/dev/null 2>&1; then
  echo "Updating CloudFront companion stack: $CLOUDFRONT_STACK"
  set +e
  update_output="$(aws cloudformation update-stack \
    --stack-name "$CLOUDFRONT_STACK" \
    --template-body "file://$CLOUDFRONT_TEMPLATE" \
    --parameters "file://$CF_PARAMS" \
    --region "$REGION" \
    --profile "$PROFILE" 2>&1)"
  update_status=$?
  set -e
  if [[ "$update_status" -eq 0 ]]; then
    aws cloudformation wait stack-update-complete \
      --stack-name "$CLOUDFRONT_STACK" \
      --region "$REGION" \
      --profile "$PROFILE"
  elif [[ "$update_output" == *"No updates are to be performed"* ]]; then
    echo "CloudFront companion stack already matched the requested template and parameters."
  else
    echo "CloudFront stack update failed." >&2
    exit "$update_status"
  fi
else
  aws cloudformation create-stack \
    --stack-name "$CLOUDFRONT_STACK" \
    --template-body "file://$CLOUDFRONT_TEMPLATE" \
    --parameters "file://$CF_PARAMS" \
    --tags Key=Project,Value=appointments Key=Phase,Value=10 Key=Environment,Value=prod Key=Owner,Value="$OWNER_TAG" Key=Repo,Value="$REPO_TAG" Key=ManagedBy,Value=student-handoff \
    --region "$REGION" \
    --profile "$PROFILE"

  aws cloudformation wait stack-create-complete \
    --stack-name "$CLOUDFRONT_STACK" \
    --region "$REGION" \
    --profile "$PROFILE"
fi

aws cloudformation describe-stacks \
  --stack-name "$CLOUDFRONT_STACK" \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query 'Stacks[0].Outputs' \
  --output table

if [[ "$EDGE_MODE" == "cloudfront-only" ]]; then
  echo
  echo "CloudFront-only checkpoint is ready."
  echo "Validate the CloudFront HTTPS URL, then confirm direct ALB access still returns the app before the hardening step."
  echo "Next step: PHASE10_EDGE_MODE=harden-origin ./scripts/11-enable-cloudfront-https.sh"
  exit 0
fi

aws cloudformation describe-stacks \
  --stack-name "$MAIN_STACK" \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query 'Stacks[0].Parameters[].ParameterKey' \
  --output json | jq \
    --arg headerName "$ORIGIN_HEADER_NAME" \
    --arg ssmParameterName "$ORIGIN_HEADER_SSM_PARAMETER" \
    --arg prefixListId "$CLOUDFRONT_PREFIX_LIST_ID" \
    '
      def param($key; $value): {ParameterKey:$key, ParameterValue:$value};
      (map(
        if . == "DjangoCsrfTrustedOrigins" then param(.; "https://*.amazonaws.com,https://*.cloudfront.net")
        elif . == "CloudFrontOriginHeaderName" then param(.; $headerName)
        elif . == "CloudFrontOriginHeaderValue" then param(.; $ssmParameterName)
        elif . == "AlbSecurityGroupPrefixLists" then param(.; $prefixListId)
        else {ParameterKey: ., UsePreviousValue: true}
        end
      )) as $existing
      | $existing
        + (if $existing | map(.ParameterKey) | index("CloudFrontOriginHeaderName") then [] else [param("CloudFrontOriginHeaderName"; $headerName)] end)
        + (if $existing | map(.ParameterKey) | index("CloudFrontOriginHeaderValue") then [] else [param("CloudFrontOriginHeaderValue"; $ssmParameterName)] end)
        + (if $existing | map(.ParameterKey) | index("AlbSecurityGroupPrefixLists") then [] else [param("AlbSecurityGroupPrefixLists"; $prefixListId)] end)
    ' \
    > "$PARAM_UPDATE"

set +e
main_update_output="$(aws cloudformation update-stack \
  --stack-name "$MAIN_STACK" \
  --template-body "file://$MAIN_TEMPLATE" \
  --parameters "file://$PARAM_UPDATE" \
  --capabilities CAPABILITY_IAM \
  --region "$REGION" \
  --profile "$PROFILE" 2>&1)"
main_update_status=$?
set -e

if [[ "$main_update_status" -eq 0 ]]; then
  aws cloudformation wait stack-update-complete \
    --stack-name "$MAIN_STACK" \
    --region "$REGION" \
    --profile "$PROFILE"
elif [[ "$main_update_output" == *"No updates are to be performed"* ]]; then
  echo "Main stack already matched the requested CloudFront origin-hardening parameters."
else
  echo "Main stack update failed." >&2
  exit "$main_update_status"
fi

echo
echo "CloudFront origin hardening is ready. Rerun or approve DeployPods so pods receive CloudFront CSRF trust, secure-cookie settings, and the ALB header gate."
read -r -p "Type START_PIPELINE to start the application pipeline now, or press Enter to skip: " start_pipeline
if [[ "$start_pipeline" == "START_PIPELINE" ]]; then
  aws codepipeline start-pipeline-execution \
    --name appointments-prod-ApplicationPipeline \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'pipelineExecutionId' \
    --output text
fi
