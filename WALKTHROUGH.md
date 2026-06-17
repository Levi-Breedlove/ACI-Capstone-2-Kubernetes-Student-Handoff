# Student Walkthrough

This guide walks a new AWS learner through deploying the Phase 10 Appointments Scheduler into their own AWS account. It intentionally follows the staged learning path used for the completed production demo: lab baseline comparison, production ALB path, CloudFront HTTPS, then ALB origin hardening.

Follow the steps in order. Do not skip the safety gates.

If an AI assistant is helping a student, it should use this file, `WALKTHROUGH-CHECKLIST.md`, and `NETWORK-SECURITY-REVIEW.md` together. The assistant should explain each step, run read-only checks before mutations, stop for approval before cost-bearing actions, and never ask the student to paste secrets into chat.

## 0. Understand The Goal

You are deploying a Django appointments app using:

- AWS CloudFormation.
- Amazon EKS.
- Amazon ECR.
- Amazon RDS for MySQL.
- Amazon DynamoDB.
- AWS CodePipeline and CodeBuild.
- AWS Load Balancer Controller.
- One public Application Load Balancer.
- Optional CloudFront default-domain HTTPS.

The expected final public path is:

```text
Browser HTTPS -> CloudFront -> HTTP -> ALB -> HTTP -> Kubernetes Ingress -> ClusterIP Service -> app pods
```

This is a demo-safe edge pattern, not end-to-end TLS. CloudFront is the public HTTPS entry point. The ALB and pods remain on HTTP for this demo, and the hardened CloudFront path adds an origin header plus a CloudFront origin-facing prefix-list restriction so direct ALB access should not return the app.

The learning checkpoints are:

1. Compare the lab zip to the production package.
2. Deploy and validate the production app through the ALB.
3. Add CloudFront HTTPS and observe that direct ALB access may still work before hardening.
4. Harden the ALB origin path so the app is reachable through CloudFront only.

Why this matters: students should see that HTTPS, Kubernetes routing, and origin lockdown are separate concepts. CloudFront gives the browser HTTPS; Kubernetes still runs the app; the final ALB hardening step prevents the ALB from becoming a public alternate entry point.

The app itself does not need Kubernetes because appointment scheduling is complex. Kubernetes is here as the teaching platform. It lets students see pod recovery, node replacement, rolling deploys, unhealthy target routing, scaling, private workloads, and cleanup discipline on an app that is easy to understand.

Kubernetes does not replace database continuity, backups, DNS/failover planning, monitoring, alarms, incident runbooks, or cost controls. For a small real scheduling app, simpler AWS services may be a better fit.

## 1. Set A Budget First

Before deploying, create or confirm an AWS Budget.

This demo is roughly `$0.35/hour` while fully running with low traffic. Leaving it running for a day can cost about `$8`. Leaving it for a week can become painful.

Why this matters: cloud cleanup is an engineering responsibility. A good demo includes a budget, a teardown plan, and a habit of checking what is still running.

## 2. Configure AWS CLI

Recommended environment, replacing `your-student-profile` with the AWS CLI profile configured for the student's own AWS account:

```bash
export AWS_PROFILE=your-student-profile
export AWS_REGION=us-west-1
export AWS_DEFAULT_REGION=us-west-1
```

Validate:

```bash
./scripts/00-preflight.sh
```

Why this matters: the preflight step confirms the student is using the intended AWS profile and Region before any resources are created. It also catches missing local tools early, when the fix is cheap.

## 3. Extract The Packages

```bash
./scripts/01-extract-packages.sh
```

This extracts:

```text
/tmp/phase10-student-handoff/production
/tmp/phase10-student-handoff/lab
```

Use the production extraction for personal AWS deployment.

The lab extraction is included so students can compare where the project started. The demo deployment path intentionally uses the production package, then adds CloudFront HTTPS, then hardens the ALB origin path.

Why this matters: the lab package is a learning baseline, while the production package is the deployable own-account artifact. Comparing them makes the security, IAM, and infrastructure changes easier to explain.

## 4. Create The Local Parameter File

```bash
./scripts/02-create-parameters.sh
```

This creates:

```text
/tmp/appointments-prod-parameters.json
```

That file can contain an RDS password. Do not copy it into the repo. Do not paste it into chat.

Why this matters: parameter files are local deployment inputs, not source code. Keeping them in `/tmp` prevents accidental commits of database passwords or account-specific values.

## 5. Validate Templates

```bash
./scripts/03-validate-templates.sh
```

This validates the main app CloudFormation template and the optional CloudFront companion template.

Why this matters: template validation is a low-cost way to catch syntax and schema problems before CloudFormation creates billable resources.

## 6. Prepare Source

Choose one source provider:

- CodeCommit, if your AWS account supports it.
- GitHub source, if CodeCommit is unavailable in your account.

For CodeCommit:

```bash
./scripts/04-prepare-codecommit-source.sh
```

The CodeCommit repository root must be the contents of:

```text
appointments-app/
```

Do not push this whole handoff repo as the application source.

Why this matters: the pipeline buildspecs expect `Dockerfile`, `manage.py`, `buildspecs/`, and `manifests/` at the source repository root. Pushing the whole handoff folder would change the paths and break the pipeline unless the buildspecs were redesigned.

## 7. Create The Main Stack

This creates billable AWS resources.

```bash
./scripts/05-create-main-stack.sh
```

Wait for the stack to reach `CREATE_COMPLETE`.

Why this matters: this is the first major cost-bearing step. It creates the AWS foundation: VPC, private worker-node networking, EKS, RDS, DynamoDB, ECR, CodeBuild, CodePipeline, IAM roles, and artifact storage.

## 8. Install Kubernetes Prerequisites

After the stack exists:

```bash
./scripts/06-install-alb-controller.sh
./scripts/07-create-k8s-secret-and-readiness.sh
./scripts/08-bootstrap-rds.sh
```

These steps:

- Generate kubeconfig.
- Install AWS Load Balancer Controller.
- Create the Django Kubernetes Secret.
- Enable readiness-gate injection.
- Bootstrap the private RDS schema and IAM database user.

Why this matters: the first pipeline deploy is intentionally paused until these prerequisites exist. Without the controller, no ALB is created. Without the Django Secret, pods cannot start safely. Without RDS bootstrap, migrations cannot connect correctly to the private database.

## 9. Approve The First Deploy

The first launch should pause at `ApproveDeploy`.

```bash
./scripts/09-pipeline-status-and-approve.sh
```

Approve only after:

- AWS Load Balancer Controller is running.
- Django Secret exists.
- RDS bootstrap completed.

Why this matters: `ManualApproval` is a safety gate for first launch. After the environment is proven, the same package supports `AutoDeploy` for a more realistic continuous deployment pipeline.

## 10. Validate The ALB Path

```bash
./scripts/10-validate-app.sh
```

Expected:

- Deployment is `2/2`.
- Service is `ClusterIP`.
- Ingress has an ALB address.
- Target group has healthy pod IP targets.
- `/healthz` returns 200.

Why this matters: this proves the Kubernetes and ALB path before CloudFront is added. Students should be able to point at each hop: Ingress, Service, pod IP target, health check, and browser response.

## 11. Understand Container Root Hardening

Before adding CloudFront, inspect what changed in the production container:

- The Dockerfile creates a non-root user and group with UID/GID `10001`.
- The container runs Gunicorn as `USER 10001:10001`.
- The Kubernetes deployment enforces `runAsNonRoot`, `runAsUser: 10001`, and `runAsGroup: 10001`.
- The pod disables privilege escalation.
- The pod drops all Linux capabilities.
- The pod uses the runtime-default seccomp profile.
- The runtime moved away from the MariaDB C client package path and uses PyMySQL with the RDS CA bundle instead.

Why this matters: a container process running as Linux root has more power inside the container than the app needs. If an attacker finds an app-level vulnerability, non-root execution and reduced Linux privileges limit what that process can do. The package changes also reduce the operating-system package surface that produced earlier ECR scan findings.

Suggested validation during a live deployment:

```bash
kubectl exec deploy/appointments-deployment -- id
kubectl get deploy appointments-deployment -o jsonpath='{.spec.template.spec.containers[0].securityContext}{"\n"}'
```

Expected:

- Runtime UID/GID is `10001`.
- The security context shows non-root settings, no privilege escalation, dropped capabilities, and `RuntimeDefault` seccomp.

## 12. Add CloudFront HTTPS First

After the ALB path works:

```bash
PHASE10_EDGE_MODE=cloudfront-only ./scripts/11-enable-cloudfront-https.sh
```

This creates one CloudFront distribution using the default `*.cloudfront.net` certificate. It does not create Route 53, DNS records, ACM certificates, WAF, or a second ALB.

At this checkpoint:

- CloudFront gives the browser an HTTPS URL.
- CloudFront-to-ALB is still HTTP.
- The ALB-to-pod hop is still HTTP.
- Direct ALB access may still return the app.

That direct ALB result is expected before the hardening step. It demonstrates why CloudFront alone is not the same thing as locking down the origin.

After it completes, validate again:

```bash
./scripts/10-validate-app.sh
```

Why this matters: this checkpoint separates browser encryption from origin protection. Students should see that CloudFront can provide an HTTPS URL while the ALB is still reachable unless we deliberately harden the origin.

## 13. Harden The ALB Origin Path

After CloudFront works, apply the origin hardening step:

```bash
PHASE10_EDGE_MODE=harden-origin ./scripts/11-enable-cloudfront-https.sh
```

This step:

- Generates a CloudFront origin header value outside the repo.
- Reuses the generated value if the CloudFront-only checkpoint already created it.
- Ensures the CloudFront companion stack sends that header to the ALB.
- Stores the same generated value in SSM Parameter Store as a `SecureString`.
- Looks up the regional AWS-managed CloudFront origin-facing prefix list.
- Checks the security-group rule quota impact before applying the prefix list.
- Updates the main stack so DeployPods can read the header through CodeBuild's `PARAMETER_STORE` type, render ALB listener header gating, and apply the prefix-list security group restriction.

Do not commit, print, or paste the generated origin header value. CloudFormation `NoEcho` masks the CloudFront companion stack parameter display, and the main app stack receives only the SSM parameter name so CodeBuild does not store the raw value as a plaintext project environment variable.

If prompted, type `START_PIPELINE` so DeployPods reruns with the hardened Ingress rendering.

After it completes, validate again:

```bash
./scripts/10-validate-app.sh
```

Expected after hardening:

- CloudFront HTTPS `/healthz` returns 200.
- CloudFront HTTPS `/` returns 200.
- Direct ALB `/healthz` from a normal laptop fails, returns `403`, or returns fallback `404`.
- Direct ALB access does not return the app.

Then run the read-only checks in `NETWORK-SECURITY-REVIEW.md`. That checklist records the final expected boundary: browser HTTPS at CloudFront, HTTP to the ALB and pods for this demo, private Kubernetes/RDS resources, and EKS API endpoint restriction as a separate hardening decision.

For a repeat demo after students understand the stages, `PHASE10_EDGE_MODE=full ./scripts/11-enable-cloudfront-https.sh` performs both CloudFront creation and origin hardening in one pass.

Why this matters: this is the moment the design becomes CloudFront-only from the public internet. The ALB remains the Kubernetes origin, but it should not behave like a second public app URL.

## 14. Teardown

Before walking away:

```bash
./scripts/12-teardown-plan.sh
```

The teardown plan reminds you what to delete and in what order. The safest order is:

1. Delete Kubernetes app/Ingress resources.
2. Confirm the ALB disappears.
3. Delete the optional CloudFront companion stack if created.
4. Delete the SSM origin-header parameter if it was created.
5. Empty ECR/S3 resources when needed.
6. Delete the main CloudFormation stack.
7. Confirm no billable leftovers remain.

Why this matters: CloudFormation can delete most stack resources, but Kubernetes-managed ALBs and out-of-band SSM parameters need deliberate cleanup. Teardown is how students prove they understand ownership boundaries.

## Troubleshooting

If ALB targets do not appear immediately:

- Use the Target Group page, not only the Load Balancer page.
- Use CLI target-health checks for faster truth than the console.
- Confirm pods are ready.
- Confirm readiness gates are present.
- Confirm the Service is `ClusterIP`.
- Confirm the Ingress uses `target-type: ip`.

If CodeCommit creation fails:

- Your AWS account may not support new CodeCommit repositories.
- Use the GitHub source provider path in the CloudFormation parameters.

If CloudFront works but the app fails:

- CloudFront is only the HTTPS front door.
- The ALB still needs healthy pod IP targets.
- Kubernetes still needs healthy app pods.

If direct ALB access returns the app after CloudFront hardening:

- Treat it as a failed hardening check.
- Confirm the main stack has `AlbSecurityGroupPrefixLists` set to the regional CloudFront origin-facing prefix list ID.
- Confirm DeployPods reran after the main stack update.
- Confirm the ALB listener rule includes the CloudFront origin-header condition.
- A normal laptop should fail at the security group layer, or receive `403`/controller fallback `404` if the listener is reached. It should not receive the app.
