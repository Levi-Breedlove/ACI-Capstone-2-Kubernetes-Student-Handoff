# Network Security Review

This document is a student-safe network security review checklist for the Phase 10 production handoff package.

It intentionally does not contain live account IDs, ARNs, live endpoints, secrets, kubeconfig contents, or raw CloudFront origin-header values. Replace placeholders with values from your own AWS account when running read-only checks.

## Intended Demo Architecture

The final controlled demo path is:

```text
Browser -> HTTPS -> CloudFront -> HTTP -> ALB -> HTTP -> Kubernetes pods
```

This is not end-to-end TLS. CloudFront handles public browser HTTPS. CloudFront forwards to the Application Load Balancer over HTTP. The ALB forwards to Kubernetes pod IP targets over HTTP on port `8080`.

That design is intentional for this student demo. It keeps the learning goal focused on EKS, AWS Load Balancer Controller, ALB Ingress, one target group, pod-IP targets, and CloudFront edge HTTPS without adding Route 53, custom certificates, pod TLS, service mesh, or mTLS.

## Expected Secure Shape

After CloudFront and ALB origin hardening are complete, your account should show:

- CloudFront HTTP requests redirect to HTTPS.
- CloudFront HTTPS `/healthz` returns `200`.
- CloudFront HTTPS `/` returns `200`.
- CloudFront origin protocol policy is HTTP only for this demo.
- CloudFront has one custom origin header configured. Do not print or commit the value.
- ALB is internet-facing because CloudFront needs to reach it.
- ALB listener forwards to the app only when the expected origin header is present.
- ALB listener default action denies requests, ideally with fixed-response `403`.
- ALB security group allows inbound listener traffic from the AWS-managed CloudFront origin-facing prefix list, not from the whole internet.
- Direct ALB access from a normal laptop times out, returns `403`, or returns a safe deny fallback. It must not return the application.
- Kubernetes Service is `ClusterIP`.
- Kubernetes Ingress uses ALB target type `ip`.
- Target group registers pod IPs, not public nodes.
- Worker nodes are private and have no external IPs.
- RDS is private and not publicly accessible.
- No secrets, passwords, kubeconfigs, or raw origin-header values are committed.

## Findings To Look For

| Area | Healthy demo result | If you see this instead |
| --- | --- | --- |
| CloudFront viewer policy | `redirect-to-https` or HTTPS only | Fix before presenting HTTPS as working. |
| CloudFront origin protocol | `http-only` for this demo | Document if changed; HTTPS origin needs certificate planning. |
| Direct ALB access | Timeout, `403`, or safe deny fallback | If the ALB returns the app, origin hardening is not complete. |
| ALB inbound security group | CloudFront prefix list only | If `0.0.0.0/0` reaches the listener, direct bypass may be possible. |
| ALB listener rules | Header-gated forward plus default deny | If there is only a public forward rule, direct ALB bypass is likely. |
| Kubernetes Service | `ClusterIP` | Do not switch to public `LoadBalancer` for this demo. |
| Worker nodes | Private internal IPs only | Public nodes expand the attack surface and cost story. |
| RDS | `PubliclyAccessible=false` | Public RDS is not acceptable for this handoff. |
| EKS API endpoint | Demo may start with public CIDR `0.0.0.0/0` | Restrict to admin CIDRs or private endpoint access after deploy workflow impact is understood. |
| NACLs and egress | Often broad in the demo | Document as production hardening, not a demo blocker by itself. |

## EKS API Endpoint Hardening

Restricting the EKS public API endpoint from `0.0.0.0/0` to known admin CIDRs changes Kubernetes control-plane access, not public app traffic.

What changes:

- `kubectl` works only from the approved admin public IP or CIDR.
- If your internet IP changes, `kubectl` can stop working until the CIDR is updated.
- CodeBuild `DeployPods` may fail if it reaches the EKS API from a network that is not allowed.
- A private-only EKS API endpoint requires the deploy runner to have private VPC network access.

For this reason, keep endpoint restriction as an approval-gated hardening step. First confirm how your deploy stage reaches the EKS API, then decide whether to allow known deployment CIDRs or move deployment into a VPC/private endpoint pattern.

## Read-Only Validation Commands

Run these after the main stack, Kubernetes app deploy, CloudFront companion stack, and ALB origin hardening are complete.

Do not print raw secret values. In particular, do not query or echo the CloudFront origin-header value.

```bash
aws cloudfront get-distribution-config \
  --id <cloudfront-distribution-id> \
  --query "DistributionConfig.{ViewerProtocolPolicy:DefaultCacheBehavior.ViewerProtocolPolicy,OriginProtocolPolicy:Origins.Items[0].CustomOriginConfig.OriginProtocolPolicy,CustomHeaderNames:Origins.Items[0].CustomHeaders.Items[].HeaderName}" \
  --output json

aws elbv2 describe-listeners \
  --load-balancer-arn <alb-arn> \
  --query "Listeners[].{Protocol:Protocol,Port:Port,DefaultActions:DefaultActions}" \
  --output json

aws elbv2 describe-rules \
  --listener-arn <listener-arn> \
  --query "Rules[].{Priority:Priority,ConditionFields:Conditions[].Field,Actions:Actions[].Type}" \
  --output json

aws ec2 describe-security-groups \
  --group-ids <alb-security-group-id> \
  --query "SecurityGroups[].IpPermissions" \
  --output json

aws eks describe-cluster \
  --name <eks-cluster-name> \
  --region <aws-region> \
  --query "cluster.resourcesVpcConfig.{EndpointPublicAccess:endpointPublicAccess,EndpointPrivateAccess:endpointPrivateAccess,PublicAccessCidrs:publicAccessCidrs}" \
  --output json

kubectl --kubeconfig <kubeconfig-path> get svc,ingress,deploy,pods -n default -o wide

curl -I http://<cloudfront-domain>/healthz
curl -I https://<cloudfront-domain>/healthz
curl -I https://<cloudfront-domain>/
curl -I --max-time 10 http://<alb-dns-name>/healthz
```

Do not use `kubectl describe ingress` or dump full Ingress annotations for the hardened Ingress. The ALB condition annotation can include the origin-header value.

Expected results:

- CloudFront HTTP redirects to HTTPS.
- CloudFront HTTPS `/healthz` returns `200`.
- CloudFront HTTPS `/` returns `200`.
- Direct ALB access does not return the app.
- The app Service remains `ClusterIP`.
- ALB target health is healthy.
- EKS API public access may still show `0.0.0.0/0` until you intentionally complete endpoint hardening.

## Cost Notes

The expected running demo includes cost-bearing network resources:

- One NAT Gateway.
- One public Application Load Balancer.
- Public IPv4 addresses attached to the NAT Gateway and ALB nodes.
- CloudFront request/data charges, usually small for a short low-traffic demo.

Tear down promptly after class or testing. Do not leave idle Elastic IPs, NAT Gateways, ALBs, EKS nodes, or RDS instances running.

## Production Upgrade Path

For a stronger production design, consider these only after the demo is stable:

- Restrict EKS public API CIDRs or use private endpoint access with a VPC-connected deploy runner.
- Add HTTPS from CloudFront to the ALB with ACM.
- Add AWS WAF on CloudFront with managed rules and rate limiting.
- Add cost-aware CloudFront, ALB, and app log retention.
- Tighten security group egress after dependency mapping.
- Replace wildcard allowed hosts with explicit hostnames.
- Evaluate pod-level TLS, mTLS, cert-manager, or service mesh only when the learning goal requires it.
