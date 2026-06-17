# Student Deployment Checklist

Use this checklist with `WALKTHROUGH.md` when an AI assistant and a student are booting the production package in the student's own AWS account.

This file is intentionally written so the deployment can be explained and performed without relying on the helper shell scripts. The scripts in `scripts/` are optional accelerators only. The AI assistant should use this checklist as the control flow, explain each gate, run read-only checks before mutations, and stop for explicit student approval before creating, updating, deploying, approving, or deleting AWS resources.

## 0. Assistant Rules

- [ ] Confirm the student is using their own AWS account or an approved sandbox.
- [ ] Confirm the student is not using AWS root credentials.
- [ ] Do not ask the student to paste secrets into chat.
- [ ] Do not print passwords, kubeconfig contents, generated secret values, AWS access keys, session tokens, or raw CloudFront origin-header values.
- [ ] Keep local secret-bearing files outside the repo, preferably under `/tmp`.
- [ ] Use placeholders in notes and docs, not real account IDs, ARNs, endpoints, or secret values.
- [ ] Before any AWS mutation, state the AWS profile, Region, resource names, billing impact, and rollback/teardown path.
- [ ] Treat helper scripts as optional references. If using one, explain what it does before running it.

## 1. Handoff Package Selection

- [ ] Confirm the working folder is the root of this student handoff repository.
- [ ] Confirm the deployable production package exists:

```text
packages/phase-10-appointments-app.zip
```

- [ ] Confirm the lab package exists only for comparison:

```text
packages/phase-10-appointments-app-lab.zip
```

- [ ] Explain that students deploy the production zip, not the lab zip.
- [ ] Explain the learning path:

```text
lab package comparison
-> production package deploy
-> ALB/Kubernetes validation
-> CloudFront HTTPS
-> ALB origin hardening
-> network security review
-> teardown
```

- [ ] Explain the architectural takeaway: this small scheduling app does not need Kubernetes because of app complexity; Kubernetes is used here to teach pod recovery, node recovery, target health routing, rolling deploys, scaling, private workloads, and teardown.
- [ ] Confirm the student understands the security boundary: `Browser -> HTTPS -> CloudFront -> HTTP -> ALB -> HTTP -> pods`, not end-to-end TLS.
- [ ] Confirm the student understands Kubernetes does not replace database continuity, backups, monitoring, DNS/failover planning, incident runbooks, or cost controls.

Optional helper reference: `scripts/01-extract-packages.sh`.

## 2. Account And Cost Gate

- [ ] Confirm AWS CLI profile name.
- [ ] Confirm Region, recommended `us-west-1` for this package unless the class/demo owner intentionally changes it.
- [ ] Confirm a budget or billing alarm exists.
- [ ] Review `CURRENT-COST-ESTIMATE.md`.
- [ ] Confirm the student understands this creates billable resources, including EKS worker nodes, NAT Gateway, RDS, ALB, public IPv4 addresses, CodeBuild minutes, ECR storage, CloudWatch Logs, S3 artifacts, and optional CloudFront.
- [ ] Confirm the student understands teardown is required after the demo.

Read-only checks:

```bash
aws sts get-caller-identity --profile <student-profile>
aws configure list --profile <student-profile>
aws configure get region --profile <student-profile>
```

Optional helper reference: `scripts/00-preflight.sh`.

## 3. Local Tool Gate

- [ ] AWS CLI works.
- [ ] Git works.
- [ ] `jq` works.
- [ ] `unzip` works.
- [ ] `kubectl` works.
- [ ] Helm works.
- [ ] Optional: Docker works for local image inspection.
- [ ] Optional: MySQL client works if using direct SQL troubleshooting.

Suggested checks:

```bash
aws --version
git --version
jq --version
unzip -v
kubectl version --client
helm version
```

## 4. Extract The Exact Production Zip

- [ ] Create a temporary extraction folder outside the repo.
- [ ] Extract the production zip to:

```text
/tmp/phase10-student-handoff/production
```

- [ ] Confirm the app source root is:

```text
/tmp/phase10-student-handoff/production/appointments-app
```

- [ ] Confirm the main CloudFormation template is:

```text
/tmp/phase10-student-handoff/production/iac/cloudformation/appointments-production.yaml
```

- [ ] Confirm the optional CloudFront template is:

```text
/tmp/phase10-student-handoff/production/iac/cloudformation/cloudfront-default-https.yaml
```

- [ ] Confirm the production package includes `NETWORK-SECURITY-REVIEW.md`.
- [ ] Confirm no extracted files are committed back into the handoff repo.

Manual command pattern:

```bash
mkdir -p /tmp/phase10-student-handoff/production
unzip -o packages/phase-10-appointments-app.zip -d /tmp/phase10-student-handoff/production
```

## 5. Prepare Local Parameters Outside Git

- [ ] Create the CloudFormation parameter file outside the repo:

```text
/tmp/appointments-prod-parameters.json
```

- [ ] Start from the package example:

```text
/tmp/phase10-student-handoff/production/iac/cloudformation/parameters.example.json
```

- [ ] Set file permissions to mode `600`.
- [ ] Fill in student-owned values for Region, source provider, repository, stack tags, database password, and deployment options.
- [ ] Keep `PipelineDeployMode=ManualApproval` for first launch.
- [ ] Keep secrets out of chat and out of Git.

Optional helper reference: `scripts/02-create-parameters.sh`.

## 6. Validate Templates Before Creating Resources

- [ ] Validate the main CloudFormation template.
- [ ] Validate the optional CloudFront companion template.
- [ ] Stop if template validation fails.

Read-only validation pattern:

```bash
aws cloudformation validate-template \
  --profile <student-profile> \
  --region <aws-region> \
  --template-body file:///tmp/phase10-student-handoff/production/iac/cloudformation/appointments-production.yaml

aws cloudformation validate-template \
  --profile <student-profile> \
  --region <aws-region> \
  --template-body file:///tmp/phase10-student-handoff/production/iac/cloudformation/cloudfront-default-https.yaml
```

Optional helper reference: `scripts/03-validate-templates.sh`.

## 7. Prepare Source Repository

- [ ] Choose one source provider: CodeCommit if available, or GitHub/CodeStar connection if CodeCommit is unavailable.
- [ ] Confirm the source repository root is the contents of `appointments-app/`.
- [ ] Do not push this entire handoff repository as the app source.
- [ ] Confirm the source branch matches the CloudFormation parameter, usually `main`.
- [ ] Confirm buildspecs are at the source root under `buildspecs/`.
- [ ] Confirm the Dockerfile is at the source root.
- [ ] Confirm manifests are at the source root under `manifests/`.

Expected source root shape:

```text
Dockerfile
manage.py
buildspecs/
manifests/
appointments/
hairdresser_django/
requirements.txt
```

Optional helper reference: `scripts/04-prepare-codecommit-source.sh`.

## 8. Approval Gate: Create Main Stack

- [ ] Read the stack name, Region, AWS profile, and parameter file path out loud or in chat.
- [ ] Confirm this creates billable resources.
- [ ] Confirm the student explicitly approves stack creation.
- [ ] Create the main CloudFormation stack only after approval.
- [ ] Wait for `CREATE_COMPLETE`.
- [ ] If creation fails, inspect failed events before retrying or deleting anything.

Expected stack output after success:

- EKS cluster name.
- ECR repository.
- RDS endpoint.
- DynamoDB table.
- CodePipeline name.
- CodeBuild project names.
- VPC/subnet/security group details.

Optional helper reference: `scripts/05-create-main-stack.sh`.

## 9. Post-Stack Kubernetes Prerequisites

- [ ] Generate kubeconfig outside the repo.
- [ ] Store kubeconfig with restrictive permissions.
- [ ] Confirm worker nodes become `Ready`.
- [ ] Install AWS Load Balancer Controller.
- [ ] Confirm controller pods are running.
- [ ] Confirm the `alb` IngressClass exists.
- [ ] Create the `appointments-django` Kubernetes Secret without printing the value.
- [ ] Enable the default namespace readiness-gate label.
- [ ] Bootstrap private RDS from inside EKS.
- [ ] Delete temporary privileged bootstrap materials after success.

Read-only validation pattern:

```bash
kubectl --kubeconfig <kubeconfig-path> get nodes -o wide
kubectl --kubeconfig <kubeconfig-path> get pods -n kube-system
kubectl --kubeconfig <kubeconfig-path> get ingressclass
kubectl --kubeconfig <kubeconfig-path> get secret appointments-django -n default
```

Optional helper references:

- `scripts/06-install-alb-controller.sh`
- `scripts/07-create-k8s-secret-and-readiness.sh`
- `scripts/08-bootstrap-rds.sh`

## 10. Approval Gate: First Pipeline Deploy

- [ ] Confirm CodePipeline reached `ApproveDeploy`.
- [ ] Confirm AWS Load Balancer Controller is running.
- [ ] Confirm `appointments-django` Secret exists.
- [ ] Confirm RDS bootstrap completed.
- [ ] Confirm the student explicitly approves the first deploy.
- [ ] Approve the pipeline gate.
- [ ] Wait for `DeployPods` to complete.

Post-deploy validation:

- [ ] Migration Job completed.
- [ ] Deployment is `2/2`.
- [ ] Service is `ClusterIP`.
- [ ] Ingress has an ALB address.
- [ ] ALB target group has healthy pod IP targets.
- [ ] `/healthz` returns HTTP 200 through the ALB path.

Optional helper references:

- `scripts/09-pipeline-status-and-approve.sh`
- `scripts/10-validate-app.sh`

## 11. Container And ECR Hardening Validation

- [ ] Explain why the app should not run as Linux root.
- [ ] Confirm the Dockerfile uses UID/GID `10001`.
- [ ] Confirm Kubernetes `securityContext` enforces non-root runtime.
- [ ] Confirm privilege escalation is disabled.
- [ ] Confirm Linux capabilities are dropped.
- [ ] Confirm `RuntimeDefault` seccomp is set.
- [ ] Confirm the runtime uses PyMySQL and the RDS CA bundle.
- [ ] Review ECR image scan findings after the image build.

Suggested live checks:

```bash
kubectl --kubeconfig <kubeconfig-path> exec deploy/appointments-deployment -- id
kubectl --kubeconfig <kubeconfig-path> get deploy appointments-deployment -o jsonpath='{.spec.template.spec.containers[0].securityContext}{"\n"}'
```

Expected runtime UID/GID: `10001`.

## 12. CloudFront HTTPS Checkpoint

- [ ] Confirm the ALB/Kubernetes path works before adding CloudFront.
- [ ] Explain the public demo path:

```text
Browser -> HTTPS -> CloudFront -> HTTP -> ALB -> HTTP -> pods
```

- [ ] Explain this is not end-to-end TLS.
- [ ] Confirm the student explicitly approves the CloudFront companion stack.
- [ ] Create or update the CloudFront companion stack using the ALB DNS name as the origin.
- [ ] Keep the default CloudFront certificate; do not add Route 53 or custom ACM for this demo.
- [ ] Confirm CloudFront HTTP redirects to HTTPS.
- [ ] Confirm CloudFront HTTPS `/healthz` returns 200.
- [ ] Confirm CloudFront HTTPS `/` returns 200.
- [ ] Explain that direct ALB access may still return the app before origin hardening.

Optional helper reference: `PHASE10_EDGE_MODE=cloudfront-only ./scripts/11-enable-cloudfront-https.sh`.

## 13. ALB Origin Hardening Checkpoint

- [ ] Generate a CloudFront origin header value outside the repo.
- [ ] Do not print, commit, or paste the generated value.
- [ ] Store the origin header value in SSM Parameter Store as a `SecureString`.
- [ ] Find the AWS-managed CloudFront origin-facing prefix list for the selected Region.
- [ ] Check security group rule quota before applying the prefix list.
- [ ] Update the CloudFront companion stack so CloudFront sends the origin header.
- [ ] Update the main stack so `CloudFrontOriginHeaderValue` points to the SSM parameter name.
- [ ] Update the main stack with the CloudFront origin-header name and `AlbSecurityGroupPrefixLists`.
- [ ] Update `DjangoCsrfTrustedOrigins` to include `https://*.cloudfront.net`.
- [ ] Rerun or approve DeployPods so the hardened Ingress annotations are rendered.
- [ ] Confirm CodeBuild shows `CLOUDFRONT_ORIGIN_HEADER_VALUE` as `PARAMETER_STORE`, not `PLAINTEXT`.
- [ ] Confirm direct ALB `/healthz` from a normal laptop times out, returns `403`, or returns a safe fallback.
- [ ] Confirm direct ALB access does not return the app.

Optional helper reference: `PHASE10_EDGE_MODE=harden-origin ./scripts/11-enable-cloudfront-https.sh`.

## 14. Network Security Review

- [ ] Run the read-only checks in `NETWORK-SECURITY-REVIEW.md`.
- [ ] Confirm CloudFront HTTPS works.
- [ ] Confirm direct ALB access does not return the app.
- [ ] Confirm the Service is still `ClusterIP`.
- [ ] Confirm worker nodes have no external IPs.
- [ ] Confirm RDS is not publicly accessible.
- [ ] Confirm ALB target health is healthy.
- [ ] Confirm no raw origin-header value appears in docs, outputs, logs, comments, or commits.
- [ ] Explain that EKS public API endpoint restriction is a separate hardening step because it can affect `kubectl` and DeployPods access.

## 15. Application Workflow Validation

- [ ] Validate `/healthz`.
- [ ] Validate the home page.
- [ ] Create a test booking only if the student approves app data mutation.
- [ ] Confirm the booking persists in RDS through the app.
- [ ] Seed or validate a DynamoDB announcement only if the student approves data mutation.
- [ ] Confirm announcements render in the app.
- [ ] Record any test data that should be cleaned up before teardown.

## 16. Teardown Gate

- [ ] Confirm the student is done demoing.
- [ ] Confirm teardown approval.
- [ ] Delete Kubernetes app/Ingress resources before deleting the EKS cluster.
- [ ] Confirm the Kubernetes-managed ALB disappears.
- [ ] Delete the CloudFront companion stack if created.
- [ ] Delete the SSM origin-header parameter if created.
- [ ] Empty ECR/S3 resources if CloudFormation deletion is blocked by non-empty resources.
- [ ] Delete the main CloudFormation stack.
- [ ] Review retained snapshots, logs, source repositories, and artifacts.
- [ ] Confirm no running EKS, EC2 nodes, RDS, ALB, NAT Gateway, ECR images, DynamoDB table, CodePipeline, artifact bucket, snapshots, or public IPv4 resources remain unless intentionally retained.

Optional helper reference: `scripts/12-teardown-plan.sh`.

## 17. Completion Criteria

- [ ] The student can explain what the production zip deployed.
- [ ] The student can explain why the lab zip is only a comparison baseline.
- [ ] The student can explain the traffic path and why it is not end-to-end TLS.
- [ ] The student can explain why direct ALB access is blocked after hardening.
- [ ] The student can explain why pods, nodes, and RDS remain private.
- [ ] The student can explain what costs were created and how teardown removed them.
- [ ] The AI assistant reports what was validated, what remains risky, and what was intentionally not changed.
