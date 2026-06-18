# Student Deployment Checklist

Use this checklist with `WALKTHROUGH.md` when an AI assistant and a student deploy the production package in a student-owned AWS account.

The checklist is intentionally fine grained. Each phase has:

- Student tasks.
- AI assistant tasks.
- Evidence to capture.
- Stop conditions.
- Approval gates before AWS-changing actions.

Helper scripts are optional accelerators. The checklist remains the control flow.

## 0. Operating Rules

Student:

- [ ] Confirm this is the student's own AWS account or an approved sandbox.
- [ ] Confirm AWS root credentials are not being used.
- [ ] Confirm a budget or billing alert exists.
- [ ] Agree that deployment creates billable resources and teardown is required.

AI assistant:

- [ ] Explain each phase before running commands.
- [ ] Use read-only checks before mutations.
- [ ] Stop for explicit approval before create, update, deploy, approve, or delete commands.
- [ ] State AWS profile, account, Region, stack name, resource names, cost impact, and rollback/teardown path before mutations.
- [ ] Never ask for secrets in chat.
- [ ] Never print passwords, AWS access keys, session tokens, kubeconfig contents, generated Django secret keys, RDS passwords, or raw CloudFront origin-header values.
- [ ] Keep local secret-bearing files outside the repo, preferably under `/tmp`.
- [ ] Use placeholders in notes instead of account IDs, ARNs, public endpoints, IP addresses, or secret values.

Stop if:

- [ ] The student cannot confirm account ownership or budget.
- [ ] A secret appears in chat, logs, tracked files, or generated docs.
- [ ] The AWS identity does not match the intended account.

## 1. Package And Source Of Truth

Student:

- [ ] Confirm the deployable production package is `packages/phase-10-appointments-app.zip`.
- [ ] Confirm the lab package is comparison-only: `packages/phase-10-appointments-app-lab.zip`.
- [ ] Read the deployment path at the top of `WALKTHROUGH.md`.

AI assistant:

- [ ] Confirm working directory is the handoff repository root.
- [ ] Confirm both package zips exist.
- [ ] Confirm `README.md`, `WALKTHROUGH.md`, `WALKTHROUGH-CHECKLIST.md`, `PACKAGE-COMPARISON.md`, `CURRENT-COST-ESTIMATE.md`, and `NETWORK-SECURITY-REVIEW.md` exist.

Commands:

```bash
pwd
ls -l packages/phase-10-appointments-app.zip packages/phase-10-appointments-app-lab.zip
unzip -t packages/phase-10-appointments-app.zip
```

Evidence:

- [ ] Production zip integrity passes.
- [ ] Student can say "deploy production, compare lab."

Stop if:

- [ ] Production zip is missing or fails integrity check.
- [ ] The student intends to deploy the lab zip.

## 2. Cost And Identity Gate

Student:

- [ ] Provide AWS CLI profile name.
- [ ] Choose Region, normally `us-west-1`.
- [ ] Confirm budget or billing alarm.
- [ ] Review `CURRENT-COST-ESTIMATE.md`.

AI assistant:

- [ ] Run read-only identity checks.
- [ ] Confirm the profile's configured Region.
- [ ] Summarize expected cost-bearing services.

Commands:

```bash
export AWS_PROFILE=<student-profile>
export AWS_REGION=us-west-1
export AWS_DEFAULT_REGION=us-west-1

aws sts get-caller-identity --profile "$AWS_PROFILE"
aws configure list --profile "$AWS_PROFILE"
aws configure get region --profile "$AWS_PROFILE"
```

Optional helper:

```bash
./scripts/00-preflight.sh
```

Evidence:

- [ ] Account ID confirmed.
- [ ] Principal ARN is not root.
- [ ] Region confirmed.
- [ ] Budget or billing alert confirmed.

Stop if:

- [ ] Wrong account.
- [ ] Root user.
- [ ] No cost approval.

## 3. Local Tool Gate

Student:

- [ ] Install missing local tools before continuing.
- [ ] Install Agent Toolkit for AWS if using Codex or another AI coding agent for AWS guidance.
- [ ] Install `cfn-lint` for local CloudFormation validation.

AI assistant:

- [ ] Check required tools.
- [ ] Confirm whether `aws-core` from Agent Toolkit for AWS is installed and working.
- [ ] Check optional Docker/MySQL tools if the student wants local image or SQL troubleshooting.

Agent Toolkit for AWS:

```bash
codex plugin marketplace add aws/agent-toolkit-for-aws
```

Then launch Codex and run `/plugins` to browse and install `aws-core`.

Reference:

```text
https://docs.aws.amazon.com/agent-toolkit/latest/userguide/quick-start.html
```

Install `cfn-lint`:

```bash
python3 -m pip install cfn-lint
# or on macOS:
brew install cfn-lint
```

Required checks:

```bash
aws --version
git --version
jq --version
unzip -v
kubectl version --client
helm version
openssl version
cfn-lint --version
```

Optional checks:

```bash
docker --version
mysql --version
```

Evidence:

- [ ] AWS CLI works.
- [ ] Git works.
- [ ] `jq`, `unzip`, `kubectl`, `helm`, `openssl`, and `cfn-lint` work.
- [ ] Agent Toolkit for AWS status is recorded if using Codex for AWS guidance.

Stop if:

- [ ] A required deployment tool is missing.

## 4. Extract Packages Outside The Repo

Student:

- [ ] Confirm extraction location under `/tmp`.

AI assistant:

- [ ] Extract production and lab packages outside Git.
- [ ] Confirm production source root and CloudFormation template paths.
- [ ] Confirm no extracted files are staged in Git.

Commands:

```bash
./scripts/01-extract-packages.sh
git status --short
```

Expected paths:

```text
/tmp/phase10-student-handoff/production/appointments-app
/tmp/phase10-student-handoff/production/iac/cloudformation/appointments-production.yaml
/tmp/phase10-student-handoff/production/iac/cloudformation/cloudfront-default-https.yaml
/tmp/phase10-student-handoff/production/NETWORK-SECURITY-REVIEW.md
/tmp/phase10-student-handoff/lab
```

Evidence:

- [ ] Production extraction exists.
- [ ] Lab extraction exists.
- [ ] `NETWORK-SECURITY-REVIEW.md` is packaged.
- [ ] Git status has no extracted package folders.

Stop if:

- [ ] Extraction happened in the repository root.

## 5. Compare Lab And Production

Student:

- [ ] Read `PACKAGE-COMPARISON.md`.
- [ ] Explain why the production package is the deployable artifact.

AI assistant:

- [ ] Show production Dockerfile hardening.
- [ ] Show production Kubernetes security context.
- [ ] Show `ClusterIP` Service and ALB Ingress `target-type: ip`.
- [ ] Show CloudFront companion stack and hardening support.

Suggested checks:

```bash
grep -n "10001\|USER" /tmp/phase10-student-handoff/production/appointments-app/Dockerfile
grep -n "runAsNonRoot\|allowPrivilegeEscalation\|seccompProfile" \
  /tmp/phase10-student-handoff/production/appointments-app/manifests/appointments-deployment.yml
grep -n "type: ClusterIP" \
  /tmp/phase10-student-handoff/production/appointments-app/manifests/appointments-service.yml
grep -n "target-type: ip" \
  /tmp/phase10-student-handoff/production/appointments-app/manifests/appointments-ingress.yml
```

Evidence:

- [ ] Student understands non-root runtime.
- [ ] Student understands `ClusterIP` plus ALB Ingress.
- [ ] Student understands CloudFront HTTPS is not end-to-end TLS.

## 6. Parameter File Outside Git

Student:

- [ ] Choose stack name.
- [ ] Choose source provider: CodeCommit or GitHub.
- [ ] Generate or store RDS master password outside chat.
- [ ] Choose non-secret tag values.
- [ ] Keep `PipelineDeployMode=ManualApproval`.

AI assistant:

- [ ] Create `/tmp/appointments-prod-parameters.json`.
- [ ] Verify placeholder values are replaced without printing secrets.
- [ ] Confirm file mode is `600`.

Commands:

```bash
./scripts/02-create-parameters.sh
chmod 600 /tmp/appointments-prod-parameters.json
ls -l /tmp/appointments-prod-parameters.json
```

Evidence:

- [ ] Parameter file exists under `/tmp`.
- [ ] Parameter file is not tracked by Git.
- [ ] `PipelineDeployMode=ManualApproval`.
- [ ] `DatabaseMasterPassword` exists but is not printed.

Stop if:

- [ ] Parameter file is inside the repo.
- [ ] Secret value is pasted into chat or logs.
- [ ] First launch is configured as `AutoDeploy`.

## 7. Validate Templates

Student:

- [ ] Approve read-only validation.
- [ ] Review any warnings or errors.

AI assistant:

- [ ] Run local `cfn-lint`.
- [ ] Run AWS CloudFormation `validate-template` for both templates.
- [ ] Explain IAM capability requirements.

Commands:

```bash
./scripts/03-validate-templates.sh

cfn-lint -i W1030 W1011 -- \
  /tmp/phase10-student-handoff/production/iac/cloudformation/appointments-production.yaml

cfn-lint \
  /tmp/phase10-student-handoff/production/iac/cloudformation/cloudfront-default-https.yaml
```

Manual equivalent:

```bash
aws cloudformation validate-template \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --template-body file:///tmp/phase10-student-handoff/production/iac/cloudformation/appointments-production.yaml

aws cloudformation validate-template \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --template-body file:///tmp/phase10-student-handoff/production/iac/cloudformation/cloudfront-default-https.yaml
```

Evidence:

- [ ] `cfn-lint` succeeds or only reports documented non-blocking warnings.
- [ ] Main template validates.
- [ ] CloudFront template validates.
- [ ] IAM capability requirement is understood.

Stop if:

- [ ] Template validation fails.
- [ ] Lint errors are present.

## 8. Source Repository

Student:

- [ ] Approve source repository creation if needed.
- [ ] Authorize GitHub CodeStar connection in the console if using GitHub.

AI assistant:

- [ ] Confirm app source root is `appointments-app/`.
- [ ] Push only the app source root to the source repository.
- [ ] Confirm source branch matches the parameter file.

Expected source root:

```text
Dockerfile
manage.py
requirements.txt
requirements-dev.txt
buildspecs/
manifests/
appointments/
hairdresser_django/
rds-global-bundle.pem
```

Optional helper:

```bash
./scripts/04-prepare-codecommit-source.sh
```

Evidence:

- [ ] Source repository exists.
- [ ] Branch exists.
- [ ] Source root contains `Dockerfile`, `manage.py`, `buildspecs/`, and `manifests/`.
- [ ] No wrapper docs, kubeconfig, parameter files, or secrets were pushed.

Stop if:

- [ ] The whole handoff repo is about to be pushed.
- [ ] Source provider parameters do not match the prepared repository.

## 9. Approval Gate: Create Main Stack

Student:

- [ ] Read and approve the profile, account, Region, stack name, template, and parameter file.
- [ ] Confirm billable resources are acceptable.

AI assistant:

- [ ] Run read-only identity and existing-stack checks.
- [ ] State the expected billable services.
- [ ] Create the stack only after explicit approval.
- [ ] Wait for completion.
- [ ] Collect outputs.

Read-only checks:

```bash
aws sts get-caller-identity --profile "$AWS_PROFILE"
aws cloudformation describe-stacks \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --stack-name appointments-prod
```

Create helper:

```bash
./scripts/05-create-main-stack.sh
```

Evidence:

- [ ] Student approval recorded.
- [ ] Stack reaches `CREATE_COMPLETE`.
- [ ] Outputs captured: EKS cluster, ECR repo, RDS endpoint, DynamoDB table, CodePipeline, CodeBuild projects.

Stop if:

- [ ] Stack creation fails or rolls back.
- [ ] The account/Region differs from the approved values.

## 10. Kubernetes Prerequisites

Student:

- [ ] Approve kubeconfig generation.
- [ ] Approve AWS Load Balancer Controller install.
- [ ] Generate Django secret value outside chat.
- [ ] Approve RDS bootstrap because it modifies database users/schema.

AI assistant:

- [ ] Store kubeconfig outside the repo.
- [ ] Confirm nodes are ready.
- [ ] Install AWS Load Balancer Controller.
- [ ] Confirm controller pods and `alb` IngressClass.
- [ ] Create `appointments-django` Secret without printing the value.
- [ ] Enable readiness-gate namespace label.
- [ ] Bootstrap RDS from inside the cluster.
- [ ] Remove temporary bootstrap materials after success.

Helpers:

```bash
./scripts/06-install-alb-controller.sh
./scripts/07-create-k8s-secret-and-readiness.sh
./scripts/08-bootstrap-rds.sh
```

Validation:

```bash
kubectl --kubeconfig <kubeconfig-path> get nodes -o wide
kubectl --kubeconfig <kubeconfig-path> get pods -n kube-system
kubectl --kubeconfig <kubeconfig-path> get ingressclass
kubectl --kubeconfig <kubeconfig-path> get secret appointments-django -n default
```

Evidence:

- [ ] Nodes are `Ready`.
- [ ] Controller pods are running.
- [ ] `alb` IngressClass exists.
- [ ] Secret exists.
- [ ] RDS bootstrap completed.

Stop if:

- [ ] Controller is not healthy.
- [ ] Secret is missing.
- [ ] RDS bootstrap failed.

## 11. Approval Gate: First Pipeline Deploy

Student:

- [ ] Confirm prerequisites are complete.
- [ ] Approve the `ApproveDeploy` gate.

AI assistant:

- [ ] Confirm CodePipeline is paused at `ApproveDeploy`.
- [ ] Approve only the intended execution after student approval.
- [ ] Wait for `DeployPods`.

Helper:

```bash
./scripts/09-pipeline-status-and-approve.sh
```

Evidence:

- [ ] Pipeline reached approval action.
- [ ] Student approval recorded.
- [ ] `DeployPods` completed.
- [ ] Migration Job completed.

Stop if:

- [ ] Controller, secret, or RDS bootstrap is incomplete.
- [ ] Pipeline execution is not the intended current execution.

## 12. ALB And Kubernetes Validation

Student:

- [ ] Approve any app data mutation separately.

AI assistant:

- [ ] Validate pods, Service, Ingress, ALB DNS, target health, and `/healthz`.
- [ ] Keep CloudFront out of this phase.

Helper:

```bash
./scripts/10-validate-app.sh
```

Expected:

- [ ] Deployment is `2/2`.
- [ ] Service is `ClusterIP`.
- [ ] Ingress has an ALB hostname.
- [ ] Target group has healthy pod IP targets.
- [ ] ALB `/healthz` returns HTTP `200`.

Stop if:

- [ ] Service is `LoadBalancer`.
- [ ] Targets are unhealthy.
- [ ] Ingress has no ALB.
- [ ] Pods are not ready.

## 13. Container Hardening Validation

Student:

- [ ] Explain why the app should not run as Linux root.

AI assistant:

- [ ] Confirm Dockerfile UID/GID `10001`.
- [ ] Confirm Kubernetes security context.
- [ ] Confirm PyMySQL and RDS CA bundle.
- [ ] Check live runtime identity after deployment.
- [ ] Review ECR scan results if image scan is enabled.

Checks:

```bash
kubectl --kubeconfig <kubeconfig-path> exec deploy/appointments-deployment -- id
kubectl --kubeconfig <kubeconfig-path> get deploy appointments-deployment \
  -o jsonpath='{.spec.template.spec.containers[0].securityContext}{"\n"}'
```

Expected:

- [ ] Runtime UID/GID is `10001`.
- [ ] `runAsNonRoot` is true.
- [ ] `allowPrivilegeEscalation` is false.
- [ ] Capabilities drop `ALL`.
- [ ] Seccomp is `RuntimeDefault`.

## 14. CloudFront HTTPS Checkpoint

Student:

- [ ] Approve CloudFront companion stack creation or update.
- [ ] Understand this is public HTTPS at CloudFront, not end-to-end TLS.

AI assistant:

- [ ] Confirm ALB path works first.
- [ ] Create/update CloudFront using the ALB DNS as origin.
- [ ] Keep default CloudFront certificate.
- [ ] Do not add Route 53, ACM, WAF, or a second ALB for this demo.
- [ ] Validate CloudFront.
- [ ] Explain direct ALB access may still work before hardening.

Helper:

```bash
PHASE10_EDGE_MODE=cloudfront-only ./scripts/11-enable-cloudfront-https.sh
```

Expected:

- [ ] CloudFront HTTP redirects to HTTPS.
- [ ] CloudFront HTTPS `/healthz` returns `200`.
- [ ] CloudFront HTTPS `/` returns `200`.
- [ ] Direct ALB access may still return app before hardening.

Evidence:

- [ ] CloudFront domain recorded with placeholder-safe notes.
- [ ] HTTP/HTTPS statuses recorded.

## 15. ALB Origin Hardening

Student:

- [ ] Approve SSM SecureString parameter creation.
- [ ] Approve CloudFormation stack updates.
- [ ] Approve pipeline rerun if prompted.
- [ ] Do not paste the generated origin-header value.

AI assistant:

- [ ] Generate or reuse origin-header value outside the repo.
- [ ] Store value in SSM Parameter Store as `SecureString`.
- [ ] Update CloudFront companion stack to send origin header.
- [ ] Find regional CloudFront origin-facing prefix list.
- [ ] Check security-group quota impact.
- [ ] Update main stack with origin-header name, SSM parameter name, prefix list, and CloudFront CSRF origin.
- [ ] Rerun or approve `DeployPods`.
- [ ] Confirm CodeBuild uses `PARAMETER_STORE`, not plaintext, for `CLOUDFRONT_ORIGIN_HEADER_VALUE`.
- [ ] Avoid dumping full Ingress annotations.

Helper:

```bash
PHASE10_EDGE_MODE=harden-origin ./scripts/11-enable-cloudfront-https.sh
```

Expected:

- [ ] CloudFront HTTPS `/healthz` returns `200`.
- [ ] CloudFront HTTPS `/` returns `200`.
- [ ] Direct ALB `/healthz` times out, returns `403`, or returns safe fallback.
- [ ] Direct ALB access does not return the app.

Stop if:

- [ ] Direct ALB returns app content.
- [ ] ALB listener access is still broad for the hardened path.
- [ ] Origin-header value appears in output or files.

## 16. Network Security Review

Student:

- [ ] Read `NETWORK-SECURITY-REVIEW.md`.
- [ ] Confirm the final boundary is understood.

AI assistant:

- [ ] Run the read-only review commands.
- [ ] Summarize pass/fail.
- [ ] Separate demo blockers from production-hardening follow-ups.

Confirm:

- [ ] CloudFront viewer HTTP redirects to HTTPS.
- [ ] CloudFront origin protocol is HTTP only for this demo.
- [ ] Direct ALB access does not return the app.
- [ ] ALB listener has header-gated forward plus default deny.
- [ ] ALB security group uses CloudFront origin-facing prefix list for listener traffic after hardening.
- [ ] Service is `ClusterIP`.
- [ ] Target group uses pod IPs.
- [ ] Worker nodes have no public external IPs.
- [ ] RDS is not publicly accessible.
- [ ] No raw origin-header value is exposed.
- [ ] EKS API endpoint restriction is documented as a separate approval-gated hardening step.

## 17. Application Workflow Validation

Student:

- [ ] Approve or decline data-writing tests.
- [ ] Decide whether to clean up test data.

AI assistant:

- [ ] Validate `/healthz`.
- [ ] Validate home page.
- [ ] Create a test booking only after approval.
- [ ] Confirm booking persistence through the app.
- [ ] Validate DynamoDB announcements only after approval.
- [ ] Record cleanup notes for test data.

Evidence:

- [ ] HTTP status codes recorded.
- [ ] Data mutation approval recorded if used.
- [ ] Test data cleanup plan recorded.

## 18. Teardown Gate

Student:

- [ ] Confirm the demo is complete.
- [ ] Approve cleanup.
- [ ] Decide whether to retain source repo, snapshots, or logs.

AI assistant:

- [ ] Run read-only teardown plan first.
- [ ] Delete Kubernetes app/Ingress resources before deleting the EKS cluster.
- [ ] Wait for Kubernetes-managed ALB deletion.
- [ ] Delete CloudFront companion stack if created.
- [ ] Delete SSM origin-header parameter if created.
- [ ] Empty ECR/S3 resources if they block stack deletion.
- [ ] Delete the main CloudFormation stack.
- [ ] Review retained snapshots, logs, source repositories, and artifacts.

Planning helper:

```bash
./scripts/12-teardown-plan.sh
```

Final evidence:

- [ ] No running EKS cluster unless intentionally retained.
- [ ] No worker nodes unless intentionally retained.
- [ ] No demo RDS instance unless intentionally retained.
- [ ] No demo ALB unless intentionally retained.
- [ ] No NAT Gateway unless intentionally retained.
- [ ] No ECR images, artifact bucket objects, CodePipeline, CodeBuild projects, DynamoDB table, or public IPv4 resources unless intentionally retained.
- [ ] Retained snapshots/logs/repos are documented.

Stop if:

- [ ] Student has not approved destructive cleanup.
- [ ] The AWS profile/Region no longer matches the deployment.
- [ ] ALB still exists after Ingress deletion.

## 19. Completion Criteria

Student can explain:

- [ ] What the production zip deployed.
- [ ] Why the lab zip was comparison-only.
- [ ] Why the app uses Kubernetes for learning rather than necessity.
- [ ] The traffic path and why it is not end-to-end TLS.
- [ ] Why direct ALB access is blocked after hardening.
- [ ] Why pods, nodes, and RDS remain private.
- [ ] Which resources created cost.
- [ ] How teardown removed or intentionally retained resources.

AI assistant final report includes:

- [ ] What was validated.
- [ ] What was changed.
- [ ] What was not changed.
- [ ] Any remaining warnings or manual follow-ups.
- [ ] Confirmation that no secrets were added to tracked files.
