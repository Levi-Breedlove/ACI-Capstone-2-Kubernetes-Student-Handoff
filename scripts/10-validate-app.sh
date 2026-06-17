#!/usr/bin/env bash
set -euo pipefail

PROFILE="${AWS_PROFILE:-default}"
REGION="${AWS_REGION:-us-west-1}"
MAIN_STACK="${PHASE10_STACK_NAME:-appointments-prod}"
CLOUDFRONT_STACK="${PHASE10_CLOUDFRONT_STACK_NAME:-appointments-prod-cloudfront-https}"

kubectl get deploy,pods,job,svc,ingress,targetgroupbindings -n default

ALB_DNS="$(kubectl get ingress appointments-ingress -n default -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
TG_ARN="$(kubectl get targetgroupbinding -n default -o jsonpath='{.items[0].spec.targetGroupARN}' 2>/dev/null || true)"
if [[ -n "$TG_ARN" ]]; then
  aws elbv2 describe-target-health \
    --target-group-arn "$TG_ARN" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'TargetHealthDescriptions[].{Target:Target.Id,Port:Target.Port,State:TargetHealth.State,Reason:TargetHealth.Reason}' \
    --output table
fi

CF_DOMAIN="$(aws cloudformation describe-stacks \
  --stack-name "$CLOUDFRONT_STACK" \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query "Stacks[0].Outputs[?OutputKey=='CloudFrontDefaultHttpsDomainName'].OutputValue | [0]" \
  --output text 2>/dev/null || true)"

ALB_PREFIX_LISTS="$(aws cloudformation describe-stacks \
  --stack-name "$MAIN_STACK" \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query "Stacks[0].Parameters[?ParameterKey=='AlbSecurityGroupPrefixLists'].ParameterValue | [0]" \
  --output text 2>/dev/null || true)"

origin_hardening_enabled=false
if [[ -n "$ALB_PREFIX_LISTS" && "$ALB_PREFIX_LISTS" != "None" ]]; then
  origin_hardening_enabled=true
fi

if [[ -n "$ALB_DNS" ]]; then
  if [[ -n "$CF_DOMAIN" && "$CF_DOMAIN" != "None" ]]; then
    echo "Direct ALB /healthz bypass check:"
    alb_code="$(curl -sS --max-time 8 -o /dev/null -w '%{http_code}' "http://$ALB_DNS/healthz" || true)"
    echo "HTTP ${alb_code:-000}"
    if [[ "$origin_hardening_enabled" == "true" ]]; then
      case "${alb_code:-000}" in
        000|403|404)
          echo "Expected: direct ALB did not return the app."
          ;;
        *)
          echo "Unexpected: direct ALB reached the app or another public response. Review CloudFront origin header and ALB security-group restrictions." >&2
          exit 1
          ;;
      esac
    else
      echo "Learning checkpoint: CloudFront exists, but ALB origin hardening is not enabled yet. Direct ALB may still return the app."
    fi
  else
    echo "ALB /healthz before CloudFront hardening:"
    curl -sS -o /dev/null -w 'HTTP %{http_code}\n' "http://$ALB_DNS/healthz" || true
  fi
fi

if [[ -n "$CF_DOMAIN" && "$CF_DOMAIN" != "None" ]]; then
  echo "CloudFront HTTP redirect:"
  curl -sS -o /dev/null -w 'HTTP %{http_code} -> %{redirect_url}\n' "http://$CF_DOMAIN/healthz" || true
  echo "CloudFront HTTPS /healthz:"
  curl -sS -o /dev/null -w 'HTTPS %{http_code}\n' "https://$CF_DOMAIN/healthz" || true
  echo "CloudFront HTTPS root:"
  curl -sS -o /dev/null -w 'HTTPS %{http_code}\n' "https://$CF_DOMAIN/" || true
fi
