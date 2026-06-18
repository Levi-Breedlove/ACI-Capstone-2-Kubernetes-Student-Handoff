# Agent Instructions

## Repository Purpose

This repository is a student-facing Phase 10 deployment handoff for the Appointments Scheduler capstone.

The goal is to help a learner deploy the production-style AWS environment into their own AWS account with clear safety gates, cost awareness, repeatable commands, and clean teardown.

This repository is not tied to an AWS account. Do not add real account IDs, ARNs, public endpoints, IP addresses, passwords, API keys, kubeconfig files, or generated secrets to tracked files.

## Primary Sources

Use these files as the source of truth:

```text
README.md
WALKTHROUGH.md
WALKTHROUGH-CHECKLIST.md
PACKAGE-COMPARISON.md
CURRENT-COST-ESTIMATE.md
NETWORK-SECURITY-REVIEW.md
packages/phase-10-appointments-app.zip
packages/phase-10-appointments-app-lab.zip
scripts/
```

The production package is also self-contained after extraction. Inside the extracted production package, use these package-contained files as the deployment source of truth:

```text
README.md
DEPLOYMENT-RUNBOOK.md
DEPLOYMENT-TASKS.md
AI-ASSISTED-DEPLOYMENT-GUIDE.md
DEPLOYMENT.md
NETWORK-SECURITY-REVIEW.md
CLEANUP.md
iac/cloudformation/README.md
iac/cloudformation/post-deploy.md
```

The outer handoff repository explains the student path from the lab zip to the production zip. The package-contained runbook and task tracker exist so `packages/phase-10-appointments-app.zip` can later become its own standalone deployment repository without relying on the outer walkthrough files.

The production deployment package is:

```text
packages/phase-10-appointments-app.zip
```

The lab package is:

```text
packages/phase-10-appointments-app-lab.zip
```

Use the production package for personal AWS account deployment. Use the lab package only for comparison or lab-specific testing.

Current package expectation:

- `packages/phase-10-appointments-app.zip` includes `DEPLOYMENT-RUNBOOK.md`.
- `packages/phase-10-appointments-app.zip` includes `DEPLOYMENT-TASKS.md`.
- `DEPLOYMENT-RUNBOOK.md` gives the full student deployment path.
- `DEPLOYMENT-TASKS.md` is the unchecked execution tracker for a fresh student deployment.
- Do not mark package task items complete unless the student deployment has actually produced the matching evidence.

## Architecture

The intended deployment path is:

```text
CodeCommit or GitHub source
-> CodePipeline
-> CodeBuild UnitTest
-> CodeBuild BuildImage
-> ECR
-> Manual ApproveDeploy gate for first launch
-> CodeBuild DeployPods
-> EKS private worker nodes
-> Kubernetes ClusterIP Service
-> AWS Load Balancer Controller-managed ALB
-> optional CloudFront default-domain HTTPS companion stack
-> private RDS MySQL
-> DynamoDB announcements table
```

For the affordable HTTPS demo:

```text
Browser HTTPS -> CloudFront -> HTTP -> ALB -> HTTP -> Kubernetes Ingress -> ClusterIP Service -> pod IP targets
```

CloudFront provides the public HTTPS URL. Kubernetes, the ALB, the target group, and the pods remain part of the request path. This is not end-to-end TLS.

Teach the demo in the same order used by the completed reference deployment:

1. Compare the lab zip to the production package.
2. Deploy and validate the production ALB path.
3. Add CloudFront HTTPS first with `PHASE10_EDGE_MODE=cloudfront-only`.
4. Validate that CloudFront works and direct ALB access may still return the app.
5. Harden the ALB origin path with `PHASE10_EDGE_MODE=harden-origin`.
6. Validate that CloudFront still works and direct ALB access no longer returns the app.
7. Run the read-only checks in `NETWORK-SECURITY-REVIEW.md` after any CloudFront, Ingress, ALB, or stack update.

Also teach the container-hardening checkpoint before or during application validation:

- The app container should not run as Linux root.
- The production Dockerfile creates and uses UID/GID `10001`.
- The Kubernetes deployment enforces `runAsNonRoot`, `runAsUser`, `runAsGroup`, `allowPrivilegeEscalation: false`, dropped Linux capabilities, and `RuntimeDefault` seccomp.
- The runtime uses PyMySQL and the RDS CA bundle instead of the earlier MariaDB C client package path that contributed to scan findings.

The network security review should stay honest about the demo boundary:

- `Browser -> HTTPS -> CloudFront -> HTTP -> ALB -> HTTP -> pods`.
- The demo is not end-to-end TLS.
- Direct ALB access must not return the app after origin hardening.
- Pods, nodes, and RDS should not be directly public.
- EKS public API endpoint restriction is a separate approval-gated hardening step because it can affect `kubectl` and DeployPods connectivity.

## AWS Safety Rules

Never use AWS root user credentials for deployment. Use an IAM admin user for a short-lived demo or an approved scoped deployment role.

Before any AWS-changing command, verify:

- AWS profile
- AWS account identity
- AWS Region
- Intended stack name
- Intended resource names
- Whether the command creates billable resources
- Whether the command is reversible
- Whether the student explicitly approved the action

Run read-only checks before mutating AWS resources.

Read-only examples:

```bash
aws sts get-caller-identity
aws configure list
aws cloudformation describe-stacks
aws eks list-clusters
aws ecr describe-repositories
aws rds describe-db-instances
aws elbv2 describe-load-balancers
aws codepipeline get-pipeline
```

Do not run create, update, approve, deploy, or delete commands unless the student explicitly approves them.

Examples that require explicit approval:

```bash
aws cloudformation create-stack
aws cloudformation update-stack
aws cloudformation delete-stack
aws codepipeline put-approval-result
aws codepipeline start-pipeline-execution
kubectl apply
kubectl delete
helm install
helm upgrade
helm uninstall
mysql commands that create users, grant permissions, or modify schema
```

## Secrets And Credentials

Never create, print, commit, or expose:

- AWS access keys
- AWS secret access keys
- AWS session tokens
- RDS passwords
- Django secret keys
- `.env` files
- kubeconfig files
- private keys
- local CloudFormation parameter files containing passwords
- database bootstrap files containing secrets
- generated credentials
- GitHub tokens

Use placeholders such as:

```text
TBD_AWS_ACCOUNT_ID
TBD_AWS_REGION
TBD_RDS_MASTER_PASSWORD
TBD_ALB_DNS_NAME
TBD_CLOUDFRONT_DOMAIN
TBD_GITHUB_REPOSITORY
```

Keep local parameter files in `/tmp`, not in the repository. The default walkthrough path uses:

```text
/tmp/appointments-prod-parameters.json
```

## Cost Rules

This deployment can create billable AWS resources, including:

- EKS control plane and worker nodes
- NAT Gateway
- RDS MySQL
- Application Load Balancer
- public IPv4 addresses
- EBS volumes
- ECR image storage
- CloudWatch Logs
- CloudFront request/data usage
- retained RDS snapshots

Before deployment, confirm that an AWS Budget or billing alert exists. Keep demos short and tear down promptly.

## Workflow

Follow the walkthrough in order:

1. Run local preflight checks.
2. Extract packages to `/tmp`.
3. Read extracted package `DEPLOYMENT-RUNBOOK.md` and `DEPLOYMENT-TASKS.md`.
4. Create or validate the local parameter file outside the repo.
5. Validate CloudFormation templates.
6. Prepare the source repository.
7. Create the main stack only after explicit approval.
8. Install the AWS Load Balancer Controller only after the EKS cluster exists.
9. Create Kubernetes secrets without printing secret values.
10. Bootstrap RDS from inside the cluster.
11. Approve the first pipeline deployment only after prerequisites are complete.
12. Validate ALB, pods, target health, app health, RDS behavior, and the CloudFront-only checkpoint.
13. Harden the ALB origin path so app traffic is reachable through CloudFront only.
14. Validate non-root runtime/security context and ECR scan results.
15. Run teardown planning and cleanup after the demo, including the CloudFront companion stack and SSM origin-header parameter.

Do not skip phases. If guidance conflicts with `WALKTHROUGH.md`, `WALKTHROUGH-CHECKLIST.md`, `DEPLOYMENT-RUNBOOK.md`, or `DEPLOYMENT-TASKS.md`, update the docs or document the conflict before proceeding.

## Repository Hygiene

Do not expand application source into this repository root unless a task explicitly requires rebuilding a package.

Prefer extracting archives to `/tmp`:

```bash
./scripts/01-extract-packages.sh
```

Do not commit:

- extracted package folders
- generated kubeconfig files
- generated parameter files
- AWS credentials
- secrets
- local logs with account-specific values
- real endpoints copied from AWS

## Completion Standard

A task is complete only when:

- The requested file or AWS state was actually checked.
- No secrets were added to tracked files.
- Any AWS-changing action had explicit approval.
- The relevant walkthrough/checklist item is updated if the process changed.
- Validation output is reviewed.
- Remaining manual steps, blockers, or cost risks are documented.
