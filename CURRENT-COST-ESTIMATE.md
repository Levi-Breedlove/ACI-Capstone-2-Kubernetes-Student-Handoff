# Current Cost Estimate

This is a predictive hourly estimate for the current demo architecture in `us-west-1`.

It is not a bill. It is a planning estimate based on the running resource shape and the project rate table refreshed on 2026-06-17 UTC.

## Current Running Shape

- 1 EKS cluster.
- 2 running `t3.medium` worker nodes.
- 1 NAT Gateway.
- 1 private RDS MySQL `db.t4g.micro` instance with 20 GB storage.
- 1 internet-facing Application Load Balancer.
- 1 low-traffic ALB LCU assumption.
- 3 public IPv4 addresses visible in the account.
- 2 attached EBS `gp3` root volumes totaling about 40 GB.
- 1 active CodePipeline.
- 1 CloudFront default-domain distribution with low demo traffic.
- 1 standard SSM `SecureString` parameter for the CloudFront origin header.

## Approximate Hourly Cost

| Line item | Quantity/rate | Approx hourly |
| --- | ---: | ---: |
| EKS control plane | 1 x `$0.1000/hour` | `$0.1000` |
| EC2 workers | 2 x `t3.medium` at `$0.0496/hour` | `$0.0992` |
| NAT Gateway hourly | 1 x `$0.0480/hour` | `$0.0480` |
| RDS MySQL instance | 1 x `db.t4g.micro` at `$0.0210/hour` | `$0.0210` |
| ALB hourly | 1 x `$0.0252/hour` | `$0.0252` |
| ALB low-traffic LCU | 1 x `$0.0080/hour` | `$0.0080` |
| Public IPv4 | 3 x `$0.0050/hour` | `$0.0150` |
| RDS storage | 20 GB prorated | `$0.0032` |
| EBS root volumes | 40 GB prorated | `$0.0053` |
| CodePipeline | `$1/month` prorated | `$0.0014` |
| **Steady subtotal** |  | **`$0.3263/hour`** |
| Light buffer | logs, tiny storage, low CloudFront traffic, standard SSM/KMS request noise | **`+$0.0250/hour`** |
| **Planning rate** |  | **about `$0.35/hour`** |

## What That Means

- One hour: about `$0.33-$0.35`.
- Eight hours: about `$2.60-$2.80`, before extra build minutes or heavier data transfer.
- Twenty-four hours: about `$7.80-$8.40`.

## What Can Increase The Bill

- Leaving the stack running overnight or over a weekend.
- NAT Gateway data processing.
- Many CodeBuild runs.
- CloudFront data transfer or request volume.
- Large CloudWatch log volume.
- Retained RDS snapshots.
- Route 53, WAF, Global Accelerator, extra ALBs, extra target groups, or AWS Private CA.

## Cheapest Safe Demo Pattern

Use the current CloudFront default-domain HTTPS path, keep one ALB and one target group, and tear down promptly after the demo.
