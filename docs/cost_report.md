# Cost Optimization Report — skynet-ops-audit-service
## Pilot Deployment on AWS (ap-south-1 / Mumbai)

---

## Assumptions

- 1–3 flight academies (tenants), early pilot stage
- ~10,000 requests/day (mid-range of 5,000–20,000 spec)
- Request mix: 55% POST /events, 35% GET /events, 10% GET /health
- Traffic bursty: 70% within a 10-hour window (06:00–16:00 IST)
- Storage: SQLite on EFS (ephemeral container volume for dev; see note)
- 1 dev environment only
- Log retention: 7 days (dev)
- Excludes /metrics-demo synthetic traffic

---

## Monthly Cost Estimate (Dev — Pilot Scale)

| Component              | Service                      | Config                        | Est. USD/month |
|------------------------|------------------------------|-------------------------------|----------------|
| Compute                | ECS Fargate                  | 0.25 vCPU / 512 MB, 1 task   | ~$8.50         |
| Container Registry     | ECR                          | ~500 MB storage, 5 img limit  | ~$0.50         |
| Logs                   | CloudWatch Logs              | ~1 GB ingested, 7-day retain  | ~$2.00         |
| Alarms                 | CloudWatch Alarms            | 2 alarms                      | ~$0.20         |
| Secrets                | SSM Parameter Store          | 3 SecureString params         | ~$0.12         |
| Networking             | VPC, IGW, public subnets     | No NAT Gateway (cost trap!)   | ~$0.00         |
| Budget alerts          | AWS Budgets                  | 1 budget, 2 notifications     | ~$0.00         |
| **Total**              |                              |                               | **~$11–15/mo** |

> Well within the $25–$75/month pilot target.

---

## Cost Control Measures Implemented

### 1. Fargate — Minimum viable spec
- 0.25 vCPU + 512 MB is the smallest Fargate unit
- Handles ~10k req/day comfortably for a lightweight FastAPI service
- No always-on EC2 instance = no idle compute cost

### 2. Scale-to-zero strategy
- `desired_count = 0` in terraform.tfvars outside working hours
- Command: `aws ecs update-service --cluster <name> --service <name> --desired-count 0`
- Saves ~70% of compute cost overnight and on weekends

### 3. No NAT Gateway
- Tasks assigned public IPs directly (public subnets)
- NAT Gateway costs ~$32/month minimum — avoided entirely for pilot
- Trade-off: slightly less network isolation (acceptable for dev/pilot)

### 4. ECR lifecycle policy
- Keeps only last 5 images
- Prevents container registry storage accumulation (cost trap)

### 5. CloudWatch log retention = 7 days
- Default retention is NEVER (unlimited) — would grow unboundedly
- 7 days sufficient for dev debugging
- Pilot/staging: bump to 14 days if needed

### 6. SSM Parameter Store (not Secrets Manager)
- SSM Standard tier: free for String, $0.05/param/month for SecureString
- Secrets Manager: $0.40/secret/month — 8x more expensive for this use case

### 7. Budget alert on Day 1
- 80% threshold alert (actual) + 100% threshold alert (forecasted)
- Prevents bill shock from accidental resource proliferation

### 8. No Load Balancer
- ALB costs ~$16/month minimum — not justified for a pilot service
- Direct public IP access via ECS task is sufficient for assessment
- Add ALB only when moving to production with multiple tasks

---

## Common Cost Traps Identified and Mitigated

1. **Idle compute** — Mitigated by Fargate (pay-per-use) + scale-to-zero script
2. **Overprovisioned DB** — Mitigated by SQLite (no RDS = no ~$15–30/mo minimum)
3. **Excessive log volume** — Mitigated by 7-day retention + info-level default
4. **NAT Gateway costs** — Avoided entirely using public subnet + public IP
5. **Static IPs / Elastic IPs** — Not used; dynamic public IP via Fargate
6. **Load balancer left running** — No ALB provisioned for pilot
7. **Container registry accumulation** — ECR lifecycle policy: max 5 images
8. **Untagged resources** — All resources tagged with Project/Environment/CostCenter via Terraform default_tags
9. **Cross-region traffic** — All resources in single region (ap-south-1)
10. **Snapshots / unattached volumes** — No EBS volumes; SQLite is ephemeral in container

---

## Non-Prod Shutdown Strategy

```bash
# Scale to zero (stop paying for compute, keep infra intact)
aws ecs update-service \
  --cluster skynet-ops-audit-service-dev \
  --service skynet-ops-audit-service-dev \
  --desired-count 0

# Bring back up
aws ecs update-service \
  --cluster skynet-ops-audit-service-dev \
  --service skynet-ops-audit-service-dev \
  --desired-count 1
```

---

## Full Teardown (Destroy Everything)

```bash
cd terraform
terraform destroy -var-file="terraform.tfvars"
# Confirm with: yes
```

> Note: CloudWatch log groups are NOT retained after destroy (retention_in_days set, prevent_destroy = false). If you need logs after teardown, export them first.

---

## Storage Note on SQLite + Fargate

SQLite in a Fargate container is **ephemeral** — data is lost on task restart. This is acceptable for the pilot assessment demo. For a real deployment, the upgrade path would be:

- **Option A**: Mount Amazon EFS volume to persist `events.db` across restarts (~$0.30/GB/month)
- **Option B**: Migrate to RDS PostgreSQL t3.micro (~$15–20/month) when pilot graduates to production

For this assessment, SQLite is justified because: the spec explicitly allows it, cost efficiency is prioritized, and data loss risk is acceptable in a dev/pilot environment.
