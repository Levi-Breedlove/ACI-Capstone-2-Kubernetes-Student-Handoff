# Package Comparison

This document compares the original Phase 10 lab package with the production-style student handoff package. The goal is not just to list files. The goal is to show how a lab deployment was turned into a safer, repeatable, own-account AWS demo.

The learning path is intentional:

```text
Lab baseline
-> production ALB deployment
-> CloudFront HTTPS front door
-> ALB origin hardening so traffic reaches the app through CloudFront only
```

## Which Package To Use

| Package | Role | Student Action |
| --- | --- | --- |
| `packages/phase-10-appointments-app-lab.zip` | Original lab-compatible baseline | Use for comparison or lab replay only. |
| `packages/phase-10-appointments-app.zip` | Production-style own-account package | Use for the student AWS account deployment. |

The production handoff package is scrubbed for student reuse. Its default owner/repository tag examples use `Student` and `student-appointments-scheduler`, and the handoff archives do not contain personal owner text.

The production handoff also includes `NETWORK-SECURITY-REVIEW.md` so students can validate the final CloudFront, ALB, EKS, pod, and RDS boundary after deployment instead of treating the architecture as a black box.

## Artifact Snapshot

| Metric | Lab Package | Production Package |
| --- | ---: | ---: |
| Entries | 42 | 64 |
| Zip size | 30,547 bytes | 155,980 bytes |
| Integrity check | `unzip -t` passed | `unzip -t` passed |
| SHA-256 | `2f8b113c715f8d945d2eec7b2cb69a2ffe2de0074e09de9b6e92e71ef5004809` | `c540c8eb801cdff1534b53f1dd9a2e2ab91229e9bae1680e1eee5e6fcb04f605` |

The production package is larger because it adds CloudFormation, IAM documentation, deployment/runbook guidance, RDS bootstrap assets, CloudFront HTTPS support, ALB hardening support, teardown planning, and container security changes.

## Executive Summary

| Area | Lab Baseline | Production Handoff | Why Students Should Care |
| --- | --- | --- | --- |
| Account model | Lab-specific assumptions | Parameterized own-account deployment | Students learn to avoid copying account-specific values. |
| Infrastructure | Lab-provided or lab-assumed resources | CloudFormation-managed VPC, EKS, RDS, DynamoDB, ECR, CodePipeline, CodeBuild, IAM, and artifacts | The environment can be relaunched instead of reconstructed by memory. |
| Public routing | ALB/Kubernetes lab path | ALB first, then CloudFront HTTPS, then CloudFront-only ALB origin hardening | Students see security as a progression, not magic. |
| Pod exposure | Kubernetes manifests for lab path | `ClusterIP` Service behind ALB Ingress with pod-IP targets | Pods stay private while target health remains visible. |
| Runtime security | Original container path | Non-root UID/GID `10001`, dropped Linux capabilities, no privilege escalation, reduced package surface | Students can explain why "running as root" was fixed. |
| Secrets | Lab-oriented config | Secrets stay outside the repo; CloudFront origin header goes through SSM Parameter Store | Avoids leaking passwords, kubeconfigs, and shared origin secrets. |
| Network review | Lab-oriented assumptions | Student-safe review checklist for CloudFront, ALB, EKS, Kubernetes, RDS, and public IPv4 cost exposure | Students learn to verify the boundary rather than trust a diagram. |
| Cleanup | Lab cleanup expectations | Dry-run-first teardown plan, CloudFront companion stack awareness, and cost reminders | Students learn that cleanup is part of deployment. |

## Security Improvements

### Secret Handling

The lab package is useful for learning the service flow, but it is not a safe place to store live account secrets. The production handoff moves sensitive values out of source control:

- RDS password values belong in a local parameter file under `/tmp`, not in Git.
- The Django secret key is created as a Kubernetes Secret.
- The CloudFront origin header value is generated outside the repo.
- The origin header value is stored in SSM Parameter Store as a `SecureString`.
- The main stack passes only the SSM parameter name into CodeBuild.
- DeployPods receives `CLOUDFRONT_ORIGIN_HEADER_VALUE` as CodeBuild `PARAMETER_STORE`, not plaintext.

`NoEcho` is still documented as masking only. It helps prevent casual console display, but it is not a full secret-management strategy by itself.

### Container And Linux Root Hardening

The original vulnerable package findings led to a practical hardening pass. The production container now:

- Uses an Alpine Python runtime to reduce the operating-system package surface.
- Runs Gunicorn as UID/GID `10001` instead of Linux root.
- Uses Kubernetes `runAsNonRoot`, `runAsUser`, and `runAsGroup`.
- Sets `allowPrivilegeEscalation: false`.
- Drops all Linux capabilities.
- Uses the runtime-default seccomp profile.
- Replaces the MariaDB C client runtime path with PyMySQL.
- Keeps the RDS global CA bundle so PyMySQL can verify RDS TLS.

The point is simple: if the app process is compromised, it should not start with root-level Linux privileges inside the container.

### CloudFront And ALB Origin Hardening

The final demo path is:

```text
Browser HTTPS -> CloudFront -> HTTP -> ALB -> HTTP -> Kubernetes Ingress -> ClusterIP Service -> pods
```

This is not end-to-end TLS. It is a controlled demo-safe edge pattern.

The production handoff adds three controls after the CloudFront-only checkpoint:

- CloudFront sends a custom origin header to the ALB.
- The ALB listener forwards only requests with the expected header.
- The ALB security group can restrict listener access to the AWS-managed CloudFront origin-facing prefix list.

After hardening, direct ALB access from a normal laptop should fail, return `403`, or return a fallback `404`. It must not return the application.

## Resource Changes

| Resource Layer | Lab Baseline | Production Handoff |
| --- | --- | --- |
| Source | CodeCommit lab flow | CodeCommit or GitHub source provider; app source root remains `appointments-app/`. |
| Network | Lab network assumptions | VPC, public/private subnets, route tables, internet gateway, NAT gateway, and security groups. |
| Compute | Lab EKS reference | EKS cluster, managed node group, private worker nodes, and EKS add-ons. |
| Registry | Lab ECR reference | ECR repository with scan-on-push and encrypted storage. |
| Database | Lab assumptions | Private RDS MySQL with IAM authentication and private subnet placement. |
| NoSQL | Lab DynamoDB assumptions | DynamoDB announcements table in the student account. |
| Load balancer | Lab ALB path | AWS Load Balancer Controller-managed ALB, one target group, pod-IP targets. |
| HTTPS edge | Not part of baseline | Optional CloudFront default-domain HTTPS companion stack. |
| Artifacts | Lab-managed assumptions | Stack-owned encrypted S3 artifact bucket. |

## IAM Changes

The production package splits responsibility across roles instead of using one broad mental bucket:

| Responsibility | Production Design |
| --- | --- |
| Pipeline orchestration | Dedicated CodePipeline service role. |
| Unit tests | Separate UnitTest CodeBuild role with report upload permissions. |
| Image build | Separate BuildImage role with ECR push permissions. |
| Kubernetes deploy | DeployPods role can describe EKS and apply app resources in the target namespace. |
| App AWS access | Kubernetes service account uses EKS Pod Identity. |
| ALB controller | AWS Load Balancer Controller has its own role and Pod Identity association. |
| Database path | RDS security group allows MySQL only from the EKS security group path. |

This lets students explain least privilege in practical terms: each stage gets the AWS permissions needed for its job, not the permissions needed by every other stage.

## Kubernetes And Reliability Changes

The production manifests are designed to make availability visible during a demo:

- Two web replicas.
- One `ClusterIP` Service.
- One ALB Ingress.
- ALB target type `ip`, so target groups show pod IPs directly.
- Topology spreading across worker nodes.
- `maxUnavailable: 0` rolling updates.
- PodDisruptionBudget with at least one pod available.
- `/healthz` readiness/liveness checks.
- ALB readiness-gate guidance.
- Graceful drain timing and ALB deregistration delay.

One target group is enough for the first demo because the goal is to show a pool of healthy pod targets. Two target groups would be an active/passive design and would require a separate traffic-switching mechanism.

## Application And Data Changes

| Topic | Lab Baseline | Production Handoff |
| --- | --- | --- |
| Booking behavior | Basic app behavior | Adds `AppointmentSlot` locking with a transactional unique constraint. |
| Concurrent booking risk | Mostly UI-level prevention | Database-backed lock rejects overlapping direct or concurrent posts. |
| Django | Lab dependency set | Django 5.2 LTS line. |
| Web server | Development-style path | Gunicorn runtime. |
| Database driver | MariaDB C client path | PyMySQL compatibility shim to reduce runtime package exposure. |
| RDS setup | Manual/lab assumption | In-cluster bootstrap job template for private RDS access. |

## CI/CD Changes

The production pipeline separates build and deployment concerns:

- `UnitTest` runs Django tests.
- `BuildImage` builds and pushes the container image.
- `DeployPods` renders Kubernetes manifests and applies them to EKS.
- First launch uses `ManualApproval` so students can install the ALB controller, create the Django Secret, and bootstrap RDS before pods deploy.
- After prerequisites are proven, `AutoDeploy` can be used for a real pipeline experience.
- Images use commit-specific tags so a deployment maps back to a source revision.
- Sentinel manifest placeholders avoid accidentally replacing environment variable names.

## Cost And Cleanup Changes

The production handoff is student-owned AWS infrastructure, so cost awareness is part of the lab:

- Cost-bearing resources include EKS, EC2 nodes, NAT Gateway, RDS, ALB, public IPv4, EBS, ECR, CloudWatch Logs, CloudFront, and snapshots.
- The current demo shape is roughly `$0.35/hour` with low traffic.
- Teardown should delete Kubernetes app/Ingress resources first, confirm ALB cleanup, delete the CloudFront companion stack, delete the SSM origin-header parameter, empty ECR/S3 where needed, and delete the main stack.
- CodeCommit is retained by default unless the student intentionally deletes it.

## Student Explain-Back Questions

By the end, a student should be able to answer:

- Why is the lab zip useful, but not enough for an own-account deployment?
- Why does the production package use CloudFormation and parameter files?
- Why does the app Service stay `ClusterIP`?
- Why does ALB target type `ip` make pod health easier to teach?
- Why is CloudFront HTTPS not end-to-end TLS?
- Why did we harden the ALB after adding CloudFront?
- Why is the origin header stored through SSM Parameter Store?
- Why was running the container as Linux root a problem?
- Why did replacing MariaDB C-client runtime packages reduce vulnerability exposure?
- Why does cleanup include the CloudFront stack and SSM parameter in addition to the main stack?
