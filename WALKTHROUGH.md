# Student Walkthrough

This walkthrough is the narrative guide for deploying the Phase 10 Appointments Scheduler into a student's own AWS account. Use it with `WALKTHROUGH-CHECKLIST.md` as the control checklist and `NETWORK-SECURITY-REVIEW.md` as the final read-only security review.

The deployment is intentionally staged:

```text
lab package comparison
-> production package validation
-> source repository preparation
-> main AWS stack
-> Kubernetes prerequisites
-> first pipeline deploy
-> ALB validation
-> CloudFront HTTPS
-> ALB origin hardening
-> network security review
-> teardown
```

Do not skip phases. Do not run AWS-changing commands until the student explicitly approves the specific action.

## Roles And Rules

Student responsibilities:

- Own the AWS account, budget, and final approvals.
- Keep secrets out of chat and source control.
- Read each approval gate before allowing cost-bearing or destructive work.
- Confirm the final traffic path and teardown result.

AI assistant responsibilities:

- Explain each phase before acting.
- Run read-only checks before mutations.
- State the AWS profile, account, Region, stack name, and expected billable resources before mutations.
- Stop for explicit approval before create, update, deploy, approve, or delete commands.
- Never ask the student to paste passwords, tokens, kubeconfig contents, or generated origin-header values into chat.
- Record evidence using placeholders, not account-specific secrets or live endpoints.

## Architecture Goal

You are deploying a Django appointments app using CloudFormation, CodePipeline, CodeBuild, ECR, EKS, the AWS Load Balancer Controller, a Kubernetes `ClusterIP` Service, an ALB-managed Ingress, private RDS MySQL, DynamoDB, and optional CloudFront default-domain HTTPS.

The final demo path is:

```text
Browser HTTPS -> CloudFront -> HTTP -> ALB -> HTTP -> Kubernetes Ingress -> ClusterIP Service -> pod IP targets
```

This is not end-to-end TLS. CloudFront provides the public HTTPS URL. The ALB, Kubernetes Ingress, Service, and pods remain in the request path. After origin hardening, direct ALB access must not return the app.

Why Kubernetes is here: the app is small enough that it does not need Kubernetes for business logic. Kubernetes is the teaching surface for pod recovery, node recovery, rolling deploys, ALB target health, private workloads, IAM-to-pod access, and cleanup discipline.

## Phase 0: Cost And Identity Gate

Goal: prove the student is in the right AWS account and understands cost before anything is created.

Student tasks:

- Confirm this is the student's own AWS account or an approved sandbox.
- Confirm the AWS root user is not being used.
- Confirm an AWS Budget or billing alert exists.
- Review `CURRENT-COST-ESTIMATE.md`.
- Choose the AWS CLI profile and Region, normally `us-west-1`.

AI assistant tasks:

- Run only read-only identity and configuration checks.
- Summarize the account identity without exposing credentials.
- Stop if the student cannot confirm budget or account ownership.

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

Evidence to capture:

- AWS account ID confirmed by the student.
- IAM principal is not root.
- Region selected.
- Budget or billing alert exists.

Stop if:

- The profile points to the wrong account.
- The student is using root credentials.
- The student has not approved the expected cost exposure.

## Phase 0A: AI And Validation Tooling

Goal: prepare the AI assistant and local CloudFormation linting before deployment.

Student tasks:

- Install Agent Toolkit for AWS if using Codex or another AI coding agent for AWS guidance.
- Install `cfn-lint` for local CloudFormation validation.

AI assistant tasks:

- Point the student to the official AWS Agent Toolkit quick start.
- Confirm whether the `aws-core` Agent Toolkit plugin is installed and working.
- Confirm whether `cfn-lint` is installed.
- Treat both tools as guidance and validation aids, not permission to skip approval gates.

Agent Toolkit for AWS:

```bash
codex plugin marketplace add aws/agent-toolkit-for-aws
```

Then launch Codex and run `/plugins` to browse and install the `aws-core` plugin. AWS also recommends verifying the connection by asking the agent what AWS Regions are available.

Reference:

```text
https://docs.aws.amazon.com/agent-toolkit/latest/userguide/quick-start.html
```

`cfn-lint` install options:

```bash
python3 -m pip install cfn-lint
# or on macOS:
brew install cfn-lint
```

Validation:

```bash
cfn-lint --version
codex --version
```

Why this matters: Agent Toolkit can help an AI assistant use AWS documentation and AWS-focused workflows more accurately. `cfn-lint` catches CloudFormation schema and best-practice issues before a student creates billable resources.

## Phase 1: Package Selection And Extraction

Goal: use the production package for deployment and the lab package only for comparison.

Student tasks:

- Confirm the production zip is the deployable artifact.
- Confirm the lab zip is comparison-only.
- Keep extracted package contents outside the repo.

AI assistant tasks:

- Verify package presence and zip integrity.
- Extract to `/tmp`.
- Confirm package shape before proceeding.

Commands:

```bash
unzip -t packages/phase-10-appointments-app.zip
unzip -t packages/phase-10-appointments-app-lab.zip
./scripts/01-extract-packages.sh
```

Expected paths:

```text
/tmp/phase10-student-handoff/production
/tmp/phase10-student-handoff/lab
/tmp/phase10-student-handoff/production/appointments-app
/tmp/phase10-student-handoff/production/iac/cloudformation/appointments-production.yaml
/tmp/phase10-student-handoff/production/iac/cloudformation/cloudfront-default-https.yaml
```

Evidence to capture:

- Zip integrity passes.
- `appointments-app/` exists inside the production extraction.
- `NETWORK-SECURITY-REVIEW.md` exists inside the production extraction.

Do not:

- Expand application source into the repository root.
- Commit extracted package folders.

## Phase 2: Lab-To-Production Comparison

Goal: help the student understand why the production package differs from the lab package.

Student tasks:

- Read `PACKAGE-COMPARISON.md`.
- Explain the deployment package choice in their own words.

AI assistant tasks:

- Point out the concrete differences that matter for deployment.
- Avoid turning this into a code review of unrelated app behavior.

Required explanation:

- Production uses a non-root container user with UID/GID `10001`.
- Production Kubernetes manifests enforce `runAsNonRoot`, `allowPrivilegeEscalation: false`, dropped capabilities, and `RuntimeDefault` seccomp.
- Production uses PyMySQL and the RDS CA bundle instead of the earlier MariaDB C client path.
- Production Service is `ClusterIP`, exposed through ALB Ingress with pod IP targets.
- Production includes CloudFront default-domain HTTPS and origin hardening support.

Evidence to capture:

- Student can describe why the lab zip is not the deploy target.

## Phase 3: Local Parameter File

Goal: create deployment parameters outside Git.

Student tasks:

- Choose stack values.
- Generate or store the RDS master password outside chat and outside Git.
- Keep `PipelineDeployMode=ManualApproval` for first launch.

AI assistant tasks:

- Create the parameter file under `/tmp`.
- Check that placeholder values were replaced.
- Never print secret values.

Command:

```bash
./scripts/02-create-parameters.sh
chmod 600 /tmp/appointments-prod-parameters.json
```

Required parameter decisions:

- `SourceProvider`: `CodeCommit` or `GitHub`.
- `CodeCommitRepositoryName` or `GitHubFullRepositoryId`.
- `CodeStarConnectionArn` only if using GitHub.
- `DatabaseMasterPassword`, handled outside chat.
- `DjangoAllowedHosts` and `DjangoCsrfTrustedOrigins` initial values.
- Tag values for owner and repository.

Evidence to capture:

- Parameter file path is `/tmp/appointments-prod-parameters.json`.
- File mode is restrictive.
- No parameter file was added to Git.

Stop if:

- A secret appears in chat, logs, or tracked files.
- `PipelineDeployMode` is not `ManualApproval` for first launch.

## Phase 4: Template Validation

Goal: catch template defects before creating billable resources.

Student tasks:

- Approve read-only AWS validation.
- Review any warnings before continuing.

AI assistant tasks:

- Run local `cfn-lint` before AWS validation.
- Run AWS `validate-template` for the main and CloudFront templates.
- Explain that validation does not create resources.

Commands:

```bash
./scripts/03-validate-templates.sh

cfn-lint -i W1030 W1011 -- \
  /tmp/phase10-student-handoff/production/iac/cloudformation/appointments-production.yaml

cfn-lint \
  /tmp/phase10-student-handoff/production/iac/cloudformation/cloudfront-default-https.yaml

aws cloudformation validate-template \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --template-body file:///tmp/phase10-student-handoff/production/iac/cloudformation/appointments-production.yaml

aws cloudformation validate-template \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --template-body file:///tmp/phase10-student-handoff/production/iac/cloudformation/cloudfront-default-https.yaml
```

Evidence to capture:

- `cfn-lint` succeeds or only reports understood non-blocking warnings.
- CloudFormation validation succeeds.
- The main template reports IAM capabilities.
- Any `cfn-lint` warnings are understood, fixed, or explicitly documented.

AWS reference: CloudFormation `validate-template` checks JSON/YAML validity, and templates containing IAM resources require `CAPABILITY_IAM` or `CAPABILITY_NAMED_IAM` during stack create/update. `cfn-lint` validates CloudFormation YAML/JSON against AWS resource provider schemas and adds extra checks before the AWS API is called.

## Phase 5: Source Repository Preparation

Goal: put only the application source at the pipeline source root.

Student tasks:

- Choose CodeCommit or GitHub.
- Approve any source repository creation.
- Authorize CodeStar connection in the AWS console if using GitHub.

AI assistant tasks:

- Prepare source only from the production `appointments-app/` directory.
- Confirm root layout before pushing.
- Avoid committing package docs, parameter files, kubeconfigs, or secrets to the app repository.

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

CodeCommit helper:

```bash
./scripts/04-prepare-codecommit-source.sh
```

Evidence to capture:

- Source branch exists, usually `main`.
- `Dockerfile`, `buildspecs/`, `manifests/`, and `manage.py` are at the repository root.
- No handoff wrapper files are pushed as application source.

Stop if:

- The whole handoff repo is about to be pushed as app source.
- Git status shows secrets or local deployment files.

## Phase 6: Approval Gate: Create Main Stack

Goal: create the AWS foundation only after explicit approval.

Student tasks:

- Read the stack name, profile, account, Region, and parameter file path.
- Approve the cost-bearing stack creation by name.

AI assistant tasks:

- Run read-only checks immediately before creation.
- State the billable resources.
- Create the stack only after approval.
- Wait for completion and collect outputs.

Read-only checks:

```bash
aws sts get-caller-identity --profile "$AWS_PROFILE"
aws cloudformation describe-stacks \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --stack-name appointments-prod
```

Create command helper:

```bash
./scripts/05-create-main-stack.sh
```

This creates or configures cost-bearing resources such as EKS, EC2 worker nodes, NAT Gateway, RDS, DynamoDB, ECR, CodePipeline, CodeBuild, S3 artifacts, CloudWatch Logs, and IAM roles. The ALB is created later by Kubernetes Ingress.

Evidence to capture:

- Stack reaches `CREATE_COMPLETE`.
- Outputs include EKS cluster name, ECR repository, RDS endpoint, DynamoDB table, CodePipeline name, CodeBuild projects, and networking identifiers.

Stop if:

- Stack reaches rollback or failed state.
- CloudFormation events show an IAM, quota, subnet, RDS, or EKS creation problem.

## Phase 7: Kubernetes Prerequisites

Goal: prepare the EKS cluster before approving the first app deployment.

Student tasks:

- Approve kubeconfig generation and Kubernetes mutations.
- Generate the Django secret value outside chat.
- Approve the RDS bootstrap job because it modifies database users/schema.

AI assistant tasks:

- Store kubeconfig outside the repo.
- Install AWS Load Balancer Controller only after the EKS cluster exists.
- Create the `appointments-django` Secret without printing the value.
- Enable readiness-gate injection.
- Bootstrap RDS from inside the cluster.

Helpers:

```bash
./scripts/06-install-alb-controller.sh
./scripts/07-create-k8s-secret-and-readiness.sh
./scripts/08-bootstrap-rds.sh
```

Read-only validation:

```bash
kubectl --kubeconfig <kubeconfig-path> get nodes -o wide
kubectl --kubeconfig <kubeconfig-path> get pods -n kube-system
kubectl --kubeconfig <kubeconfig-path> get ingressclass
kubectl --kubeconfig <kubeconfig-path> get secret appointments-django -n default
```

Evidence to capture:

- Worker nodes are `Ready`.
- AWS Load Balancer Controller pods are running.
- `alb` IngressClass exists.
- `appointments-django` Secret exists.
- RDS bootstrap completed.

AWS reference: EKS Pod Identity maps an IAM role to a Kubernetes service account in a namespace, allowing pods that use that service account to receive AWS credentials through the SDK environment.

## Phase 8: Approval Gate: First Pipeline Deploy

Goal: deploy pods only after prerequisites are ready.

Student tasks:

- Confirm controller, secret, and RDS bootstrap are complete.
- Approve the `ApproveDeploy` manual gate.

AI assistant tasks:

- Inspect pipeline status.
- Approve only the intended current execution.
- Wait for `DeployPods`.
- Do not approve if prerequisites are missing.

Helper:

```bash
./scripts/09-pipeline-status-and-approve.sh
```

Evidence to capture:

- Pipeline reached `ApproveDeploy`.
- Student approved the deployment.
- `DeployPods` completed.
- Migration Job completed.

AWS reference: a CodePipeline manual approval action pauses execution until an authorized approver approves or rejects it. If no response is submitted within seven days, the action fails.

## Phase 9: Validate The ALB And Kubernetes Path

Goal: prove the app works through the Kubernetes-managed ALB before adding CloudFront.

Student tasks:

- Confirm the app can be checked without entering secrets.
- Approve app data mutations only if booking or DynamoDB write tests are performed.

AI assistant tasks:

- Validate pods, Service, Ingress, target health, and `/healthz`.
- Keep this phase focused on ALB/Kubernetes. CloudFront comes later.

Helper:

```bash
./scripts/10-validate-app.sh
```

Expected:

- Deployment is `2/2`.
- Service type is `ClusterIP`.
- Ingress has an ALB hostname.
- ALB target group contains healthy pod IP targets.
- ALB `/healthz` returns `200`.

Evidence to capture:

- `kubectl get deploy,svc,ingress,pods -o wide`.
- Target health summary.
- HTTP status for `/healthz`.

Stop if:

- Service is `LoadBalancer`.
- Targets are unhealthy.
- Pods are crash-looping.
- Ingress has no ALB address after controller reconciliation.

## Phase 10: Container Runtime Hardening

Goal: prove the production app does not run as Linux root.

Student tasks:

- Understand why non-root runtime and reduced Linux privileges matter.

AI assistant tasks:

- Inspect the Dockerfile and Kubernetes deployment.
- Validate live runtime UID/GID after deployment.

Checks:

```bash
grep -n "10001\|USER" /tmp/phase10-student-handoff/production/appointments-app/Dockerfile
grep -n "runAsNonRoot\|runAsUser\|runAsGroup\|allowPrivilegeEscalation\|seccompProfile" \
  /tmp/phase10-student-handoff/production/appointments-app/manifests/appointments-deployment.yml

kubectl --kubeconfig <kubeconfig-path> exec deploy/appointments-deployment -- id
kubectl --kubeconfig <kubeconfig-path> get deploy appointments-deployment \
  -o jsonpath='{.spec.template.spec.containers[0].securityContext}{"\n"}'
```

Expected:

- Dockerfile creates UID/GID `10001`.
- Container uses `USER 10001:10001`.
- Deployment sets `runAsNonRoot`, UID/GID `10001`, no privilege escalation, dropped capabilities, and `RuntimeDefault` seccomp.
- Requirements include PyMySQL and the RDS CA bundle exists.

## Phase 11: CloudFront HTTPS Checkpoint

Goal: add browser HTTPS while intentionally leaving origin hardening for the next phase.

Student tasks:

- Approve CloudFront companion stack creation or update.
- Understand that this creates a public CloudFront distribution.

AI assistant tasks:

- Use the existing ALB DNS name as the CloudFront origin.
- Keep the default CloudFront certificate.
- Do not add Route 53, ACM, WAF, or a second ALB for this demo.
- Validate that direct ALB access may still work at this checkpoint.

Helper:

```bash
PHASE10_EDGE_MODE=cloudfront-only ./scripts/11-enable-cloudfront-https.sh
```

Expected:

- CloudFront HTTP redirects to HTTPS.
- CloudFront HTTPS `/healthz` returns `200`.
- CloudFront HTTPS `/` returns `200`.
- Direct ALB access may still return the app.

Evidence to capture:

- CloudFront distribution domain.
- HTTP and HTTPS status results.
- Note that origin hardening is not complete yet.

AWS references: CloudFront `ViewerProtocolPolicy=redirect-to-https` redirects HTTP viewers to HTTPS. `OriginProtocolPolicy=http-only` means CloudFront uses HTTP to connect to the origin.

## Phase 12: ALB Origin Hardening

Goal: make CloudFront the only public app path.

Student tasks:

- Approve SSM parameter creation, CloudFormation updates, and pipeline rerun.
- Never paste the generated origin-header value into chat.

AI assistant tasks:

- Generate or reuse the origin-header value outside the repo.
- Store it in SSM Parameter Store as `SecureString`.
- Update the CloudFront companion stack so CloudFront sends the header.
- Find the regional AWS-managed CloudFront origin-facing prefix list.
- Check security group quota before applying prefix-list rules.
- Update the main stack with `CloudFrontOriginHeaderName`, `CloudFrontOriginHeaderValue` as the SSM parameter name, `AlbSecurityGroupPrefixLists`, and CloudFront CSRF trusted origin values.
- Rerun or approve `DeployPods` so Ingress annotations are rendered.
- Avoid commands that print full hardened Ingress annotations.

Helper:

```bash
PHASE10_EDGE_MODE=harden-origin ./scripts/11-enable-cloudfront-https.sh
```

Expected:

- CloudFront HTTPS `/healthz` returns `200`.
- CloudFront HTTPS `/` returns `200`.
- Direct ALB `/healthz` from a normal laptop times out, returns `403`, or returns a safe fallback.
- Direct ALB access does not return the app.
- CodeBuild uses `PARAMETER_STORE` for `CLOUDFRONT_ORIGIN_HEADER_VALUE`.

Evidence to capture:

- Direct ALB no longer returns app content.
- CloudFront still returns app content.
- Security group inbound rules use the CloudFront origin-facing prefix list for listener access.
- Listener rules include header-gated forward plus default deny, without printing the header value.

Stop if:

- Direct ALB access returns the app.
- Security group falls back to `0.0.0.0/0` for the hardened path.
- The origin header value appears in logs, chat, docs, or commits.

## Phase 13: Network Security Review

Goal: validate the final boundary using read-only checks.

Student tasks:

- Read `NETWORK-SECURITY-REVIEW.md`.
- Confirm the demo boundary is acceptable and not end-to-end TLS.

AI assistant tasks:

- Run the read-only checks in `NETWORK-SECURITY-REVIEW.md`.
- Summarize pass/fail results.
- Identify any separate production-hardening items.

Required confirmations:

- CloudFront HTTP redirects to HTTPS.
- CloudFront HTTPS works.
- Direct ALB access does not return the app.
- Service remains `ClusterIP`.
- Worker nodes have no external IPs.
- RDS is not publicly accessible.
- ALB target health is healthy.
- No raw origin-header value is exposed.
- EKS public API restriction remains a separate approval-gated hardening decision.

## Phase 14: Application Workflow Validation

Goal: verify the app behavior without mixing it with infrastructure changes.

Student tasks:

- Approve any data-writing tests.
- Decide whether test data should be cleaned up before teardown.

AI assistant tasks:

- Validate `/healthz`.
- Validate the home page.
- Create a booking only after approval.
- Validate RDS-backed persistence through the app.
- Validate DynamoDB announcements only after approval for data mutation.

Evidence to capture:

- URLs tested with placeholders.
- HTTP status codes.
- Test data cleanup notes.

## Phase 15: Teardown

Goal: remove resources in the right ownership order.

Student tasks:

- Approve cleanup explicitly.
- Decide whether to retain source repositories, snapshots, or logs.

AI assistant tasks:

- Start with read-only teardown planning.
- Delete Kubernetes app resources before the EKS cluster.
- Wait for the Kubernetes-managed ALB to disappear.
- Delete the CloudFront companion stack.
- Delete the out-of-band SSM origin-header parameter.
- Empty ECR/S3 resources if they block stack deletion.
- Delete the main CloudFormation stack.
- Confirm cost-bearing leftovers.

Planning helper:

```bash
./scripts/12-teardown-plan.sh
```

Teardown evidence:

- No running EKS cluster or worker nodes unless intentionally retained.
- No demo ALB, NAT Gateway, RDS instance, ECR images, artifact bucket contents, CodePipeline, CodeBuild projects, or public IPv4 resources remain unless intentionally retained.
- Retained RDS snapshots, source repositories, or logs are documented.

Stop if:

- The ALB still exists after deleting Ingress.
- The student has not approved data deletion.
- The AWS profile or Region no longer matches the deployment.

## Troubleshooting

If ALB targets do not appear:

- Confirm AWS Load Balancer Controller is running.
- Confirm the `alb` IngressClass exists.
- Confirm the Service is `ClusterIP`.
- Confirm the Ingress uses `alb.ingress.kubernetes.io/target-type: ip`.
- Confirm pods are ready and readiness gates are present.

If CodeCommit creation fails:

- The account may not support creating new CodeCommit repositories.
- Use GitHub with CodeStar Connections and update parameters accordingly.

If pipeline deploy fails:

- Confirm `DeployPods` has EKS access.
- Confirm kube prerequisites exist.
- Confirm the app source root contains `Dockerfile`, `buildspecs/`, `manifests/`, and `manage.py`.
- Confirm the built ECR image tag exists.

If CloudFront works but the app fails:

- Validate ALB target health.
- Validate pods and readiness.
- Confirm `DjangoCsrfTrustedOrigins` includes the CloudFront origin for the CloudFront path.

If direct ALB access returns the app after hardening:

- Treat it as a failed hardening check.
- Confirm `AlbSecurityGroupPrefixLists` is set to the regional CloudFront origin-facing prefix list ID.
- Confirm DeployPods reran after the main stack update.
- Confirm the ALB listener has a header-gated forward rule and fixed deny default action.
- Do not print the full Ingress annotations if the origin header value could appear.
