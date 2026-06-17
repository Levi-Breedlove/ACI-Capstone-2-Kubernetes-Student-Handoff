# [ACI-Capstone-2-Kubernetes-Student-Handoff](https://github.com/Levi-Breedlove/ACI-Capstone-2-Kubernetes-Student-Handoff/tree/main)

This repository is a standalone student deployment handoff for the Phase 10 Appointments Scheduler capstone.

It is designed so a student and an AI assistant can start here, understand what the package is, extract the correct production zip, deploy it into the student's own AWS account, validate the CloudFront/ALB/EKS path, and tear everything down safely.

This is not a live AWS account folder. It should not contain real account IDs, ARNs, passwords, kubeconfig files, generated secrets, live endpoints, or raw CloudFront origin-header values.

## What This Folder Is

This repository is the learning wrapper around the deployable Phase 10 package.

It contains:

- The exact student production zip to deploy.
- The original lab zip for comparison only.
- A walkthrough.
- An AI-friendly deployment checklist.
- A package comparison document.
- A cost estimate.
- A network security review checklist.
- Optional helper scripts.
- Safety instructions for AI assistants.

The important idea: students deploy the production zip, not this whole folder.

The production zip contains the app source, CloudFormation, Kubernetes manifests, buildspecs, IAM documentation, CloudFront support, ALB hardening support, and package-internal runbooks. This handoff folder explains how to use that zip safely.

## Student Repository Disposition

This repository should be treated as the student-facing control center for the Kubernetes production-style demo. It is not the full historical capstone repository, and it is not a live AWS account folder. It is a clean handoff repo that explains how to take the packaged application, deploy it into a student's own AWS account, validate it, explain it, and tear it down.

The intended standalone repository name is:

```text
ACI-Capstone-2-Kubernetes-Student-Handoff
```

The repository exists to teach the disposition of the final Phase 10 AWS deployment. Students should understand that the application is a small Django appointment scheduler, but the infrastructure around it is intentionally larger because the goal is to demonstrate enterprise deployment patterns. The project shows how source code moves through a pipeline, becomes a container image, runs in Kubernetes, receives traffic through an Application Load Balancer, uses private data services, and exposes a browser-facing HTTPS URL through CloudFront.

The most important framing is that students deploy from the production zip, not from the wrapper repository itself. The wrapper repository explains the deployment, gives them checklists and helper scripts, and keeps the cost and security warnings visible.

## What Students Are Building

Students are building a production-style AWS demo environment, not a minimal hosting setup. The deployment uses real AWS services and real cloud deployment patterns, but it intentionally keeps several advanced enterprise controls out of scope so the class demo stays affordable and understandable.

The production package creates or uses these major pieces:

- Source control through CodeCommit or GitHub.
- CodePipeline for CI/CD orchestration.
- CodeBuild for unit tests, image builds, and Kubernetes deployment.
- ECR for the application container image.
- EKS for Kubernetes orchestration.
- AWS Load Balancer Controller for ALB Ingress.
- One public Application Load Balancer and one target group.
- Kubernetes `ClusterIP` Service and pod-IP targets.
- Private worker nodes.
- Private RDS MySQL.
- DynamoDB for announcements.
- CloudFront for the public HTTPS demo URL.
- SSM Parameter Store for the CloudFront origin-header value.
- CloudFormation for repeatable infrastructure.

The current controlled demo path is:

```text
Browser -> HTTPS -> CloudFront -> HTTP -> ALB -> HTTP -> Kubernetes pods
```

This is not end-to-end TLS. CloudFront handles the browser-facing HTTPS layer. CloudFront forwards to the ALB over HTTP. The ALB forwards to Kubernetes pod IP targets over HTTP. That boundary should be explained honestly during the demo.

## Tier Trade-Offs

This handoff is useful because it lets students compare several deployment tiers.

### Tier 1: Lab Completion Package

The lab zip is the baseline comparison artifact. It preserves the original Lab 10 assumptions and is useful for showing where the project started. It is not the preferred artifact for a clean student AWS account deployment because it contains lab-oriented assumptions.

### Tier 2: Simple Real-World Hosting

For a real small scheduling app, Kubernetes may be unnecessary. A simpler service such as Elastic Beanstalk, ECS Fargate, App Runner, Lambda/API Gateway, or even a small EC2 deployment could be cheaper and easier to operate.

The benefit of this tier is lower cost and simpler operations. The trade-off is that it does not teach Kubernetes scheduling, pod health, ALB target groups, ingress controllers, private node networking, rolling deploys, or readiness behavior.

### Tier 3: Current Student Production-Style Demo

This is the selected demo tier. It uses CloudFront HTTPS at the public edge, an HTTP ALB origin, HTTP pod traffic, private worker nodes, private RDS, one ALB, one target group, two pod replicas, CodePipeline, CodeBuild, ECR, EKS, RDS, DynamoDB, SSM, and CloudFormation.

The benefit of this tier is that it shows the enterprise deployment path while staying controlled and teachable. Students can see CI/CD, image publishing, Kubernetes deployment, ALB target health, pod replacement, origin-bypass hardening, non-root container runtime, ECR scanning, and teardown discipline.

The trade-off is cost and complexity. EKS, NAT Gateway, ALB, RDS, public IPv4 addresses, build minutes, logs, and storage all cost money while the environment is running. That is why teardown is part of the lesson.

### Tier 4: Lower-Cost Production Hardening

A later hardening tier could add HTTPS from CloudFront to the ALB:

```text
Browser -> HTTPS -> CloudFront -> HTTPS -> ALB -> HTTP -> Kubernetes pods
```

This improves the CloudFront-to-ALB origin hop without requiring pod-level TLS. It usually requires a real hostname and an ACM certificate attached to the ALB. ACM public certificates used with integrated AWS services do not add a direct certificate charge, but a custom domain can add domain registration, Route 53 hosted-zone, and DNS management costs.

### Tier 5: Enterprise Hardening

An enterprise hardening tier could go further:

```text
Browser -> HTTPS -> CloudFront -> HTTPS -> ALB -> HTTPS or mTLS -> pods
```

This could add WAF, managed rule groups, rate-based rules, pod-level TLS, mTLS, cert-manager, service mesh, private deployment runners, stricter EKS API access, logging, alarms, dashboards, backups, restore tests, and Multi-AZ database choices.

The benefit is a stronger production security and reliability posture. The trade-off is much more cost, complexity, certificate management, and troubleshooting overhead. This is future/reference work, not the first student demo.

## Presentation Story

Students should be able to explain the demo in plain language:

This project starts with a small Django appointments app. The app itself could run on a simpler platform, but this demo uses Kubernetes because the goal is to learn the AWS patterns used by larger systems. The production package creates the AWS foundation, the pipeline tests and builds the app, ECR stores the image, EKS runs the pods, the ALB routes to healthy pod IP targets, CloudFront gives users an HTTPS URL, and teardown removes the resources so the account does not keep billing.

Students should also be able to state what the demo does not claim. It does not claim end-to-end TLS. It does not claim multi-region disaster recovery. It does not claim that Kubernetes is required for every scheduling app. It is a controlled production-style learning environment that demonstrates cloud deployment, routing, hardening, availability behavior, cost awareness, and cleanup.

## What Is Included

| Path | Purpose |
| --- | --- |
| `packages/phase-10-appointments-app.zip` | The production own-account deployment package. This is the package students deploy. |
| `packages/phase-10-appointments-app-lab.zip` | The original lab-compatible package. Use it for comparison or lab replay only. |
| `WALKTHROUGH.md` | Narrative guide that explains the staged deployment path. |
| `WALKTHROUGH-CHECKLIST.md` | Primary AI/student checklist for booting the production zip in a student AWS account. It does not depend on the shell scripts. |
| `PACKAGE-COMPARISON.md` | Security, IAM, resource, and architecture comparison between the lab zip and production zip. |
| `CURRENT-COST-ESTIMATE.md` | Approximate hourly cost model for the demo architecture. |
| `NETWORK-SECURITY-REVIEW.md` | Read-only checklist for validating CloudFront, ALB, EKS, pod, RDS, and public IPv4 exposure. |
| `AGENTS.md` | Safety and workflow instructions for AI assistants working inside this folder. |
| `scripts/` | Optional helper scripts that mirror parts of the checklist. They are convenience tools, not the source of truth. |

## Which Zip To Use

Use this zip for student AWS deployment:

```text
packages/phase-10-appointments-app.zip
```

Use this zip only for comparison:

```text
packages/phase-10-appointments-app-lab.zip
```

The production package copy in this handoff is student-scrubbed. Its default owner/repository tag examples use `Student` and `student-appointments-scheduler`, and the handoff archives do not contain personal owner text.

## Lab Zip Security Differences

The lab zip is useful for comparison, but it should not be treated as the production deployment path. It preserves the original lab-friendly shape, which means several security and operations gaps are intentionally visible for students to discuss.

The biggest difference is container runtime security. The lab Dockerfile does not set a non-root `USER`, so the container process runs as Linux root by default. It also starts Django with the development-style `runserver` command. The production package fixes that by running Gunicorn as UID/GID `10001`, adding Kubernetes `runAsNonRoot`, setting `allowPrivilegeEscalation: false`, dropping Linux capabilities, and using the runtime-default seccomp profile.

The second difference is package exposure. The lab Dockerfile installs native MySQL/MariaDB client build dependencies such as `default-libmysqlclient-dev`, `gcc`, and related tooling. That was acceptable for the lab path, but it increased the runtime package surface and contributed to the vulnerability discussion. The production package moved to a smaller Alpine-based runtime, replaced the MariaDB C-client path with PyMySQL, and kept the RDS global CA bundle so database TLS verification still works.

The third difference is public routing. The lab package is essentially HTTP-first. It does not include the CloudFront default-domain HTTPS companion stack, CloudFront origin header, SSM-backed origin-header rotation, ALB listener header gating, fixed-response deny fallback, or CloudFront origin-facing prefix-list restriction. The production package adds those pieces so the public demo URL is HTTPS at CloudFront and direct ALB access should not return the application after origin hardening.

The fourth difference is Kubernetes exposure. The lab service manifest uses a `LoadBalancer` service shape alongside the ALB/Ingress learning path. The production package keeps the app Service as `ClusterIP` and exposes the app through AWS Load Balancer Controller-managed Ingress with pod-IP targets. That makes the target group demo cleaner while keeping pods private.

In short, the lab zip shows the baseline. The production zip shows the hardening journey: remove lab assumptions, avoid Linux-root runtime, reduce vulnerable package surface, keep secrets out of Git, keep pods private, add CloudFront HTTPS, block direct ALB bypass, validate ECR findings, and document teardown.

## Expected Deployment Path

The production package deploys this AWS path:

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

The current affordable HTTPS demo keeps Kubernetes in the request path:

```text
Browser HTTPS -> CloudFront -> HTTP -> ALB -> HTTP -> Kubernetes Ingress -> ClusterIP Service -> pod IP targets
```

CloudFront is the public HTTPS front door. It does not replace Kubernetes, the ALB, the target group, or the pods. This is not end-to-end TLS. It is a controlled demo pattern that shows browser-facing HTTPS, Kubernetes routing, pod-IP target health, and origin hardening without adding Route 53, custom certificates, pod-level TLS, service mesh, or mTLS.

## Architectural Takeaway

This scheduling app does not need Kubernetes because the app itself is complicated. It uses Kubernetes as a learning vehicle for enterprise deployment patterns that students should recognize later: pod replacement, node recovery, unhealthy target routing, rolling deploys, rollback, scaling, private workloads, and teardown discipline.

Kubernetes does not automatically solve every outage. A production system still needs database continuity, backups, restore testing, DNS/failover planning, monitoring, alarms, incident runbooks, and cost controls. For a small real scheduling app, simpler AWS services may be a better fit.

## How Students Should Use This

Start with these files in order:

1. `README.md` to understand the folder.
2. `CURRENT-COST-ESTIMATE.md` to understand billing risk.
3. `PACKAGE-COMPARISON.md` to understand lab zip versus production zip.
4. `WALKTHROUGH.md` for the narrative deployment guide.
5. `WALKTHROUGH-CHECKLIST.md` as the operational AI/student checklist.
6. `NETWORK-SECURITY-REVIEW.md` after CloudFront and origin hardening are complete.

The checklist is the best control file for an AI assistant. It includes the exact production zip path, extraction target, source root, template paths, approval gates, validation checks, and teardown criteria.

## Optional Helper Scripts

The scripts in `scripts/` can speed up repeated demos, but the walkthrough checklist should still be used to understand and approve each step.

| Script | Purpose |
| --- | --- |
| `00-preflight.sh` | Local tool, account, and safety checks. |
| `01-extract-packages.sh` | Extracts production and lab zips under `/tmp`. |
| `02-create-parameters.sh` | Helps create a local CloudFormation parameter file outside the repo. |
| `03-validate-templates.sh` | Validates CloudFormation templates. |
| `04-prepare-codecommit-source.sh` | Helps prepare CodeCommit source when CodeCommit is available. |
| `05-create-main-stack.sh` | Creates the main stack after explicit approval. |
| `06-install-alb-controller.sh` | Installs AWS Load Balancer Controller after the stack exists. |
| `07-create-k8s-secret-and-readiness.sh` | Creates the Django Secret and readiness-gate label. |
| `08-bootstrap-rds.sh` | Bootstraps private RDS from inside EKS. |
| `09-pipeline-status-and-approve.sh` | Checks pipeline status and handles the first deploy approval. |
| `10-validate-app.sh` | Validates Kubernetes, ALB, CloudFront, and app health. |
| `11-enable-cloudfront-https.sh` | Adds CloudFront HTTPS and ALB origin hardening modes. |
| `12-teardown-plan.sh` | Shows teardown order and cleanup reminders. |

Do not run a script just because it exists. For any script that creates, updates, deploys, approves, or deletes AWS resources, explain the impact first and get explicit approval.

## Safety Rules

- Do not use AWS root user credentials.
- Create or confirm an AWS Budget before deploying.
- Keep passwords, kubeconfig files, generated secrets, and parameter files outside this folder.
- Use `/tmp/appointments-prod-parameters.json` or another untracked local path for CloudFormation parameters.
- Do not commit extracted package contents.
- Do not push this whole handoff folder as the app source repository.
- Push only the extracted `appointments-app/` contents as the CodeCommit/GitHub app source root.
- Keep `PipelineDeployMode=ManualApproval` for first launch.
- Tear down promptly after a demo.

## Source Provider Note

The package supports CodeCommit and GitHub/CodeStar-style source configuration.

Some new AWS accounts may not have CodeCommit available. If CodeCommit repository creation fails in a student account, use the GitHub source provider path in the CloudFormation parameters instead of forcing CodeCommit.

## Current Cost Shape

The demo shape is roughly `$0.33/hour` steady or about `$0.35/hour` with a light buffer for small logs, storage, and CloudFront traffic.

See `CURRENT-COST-ESTIMATE.md` for the line-item model.

## Completion Standard

A student demo is complete only when:

- The app deploys from the production zip.
- The student can explain the lab-to-production package differences.
- CloudFront HTTPS works.
- Direct ALB access does not return the app after hardening.
- Pods, worker nodes, and RDS are not directly public.
- Runtime non-root container hardening is validated.
- Costs are understood.
- Teardown has removed billable resources or intentionally retained items are documented.
