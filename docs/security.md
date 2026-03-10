# Security & Secrets Approach — skynet-ops-audit-service

---

## Secrets Management

### Approach: AWS SSM Parameter Store
- All secrets stored in SSM Parameter Store — **never in code or environment files**
- Sensitive values (API_KEY) use `SecureString` type (encrypted at rest with KMS)
- Non-sensitive config (APP_ENV, LOG_LEVEL) use `String` type
- ECS task pulls secrets at runtime via `secrets` block in task definition
- `.env` is in `.gitignore` — only `.env.example` is committed

### Parameters Used
| Parameter Path | Type | Description |
|----------------|------|-------------|
| `/skynet-ops-audit-service/dev/APP_ENV` | String | Environment name |
| `/skynet-ops-audit-service/dev/LOG_LEVEL` | String | Log verbosity |
| `/skynet-ops-audit-service/dev/API_KEY` | SecureString | API auth key |

### Rotating a Secret
```bash
aws ssm put-parameter \
  --name "/skynet-ops-audit-service/dev/API_KEY" \
  --value "new-strong-key-here" \
  --overwrite \
  --type SecureString

# Force ECS to pick up new value
aws ecs update-service \
  --cluster skynet-ops-audit-service-dev \
  --service skynet-ops-audit-service-dev \
  --force-new-deployment
```

---

## IAM — Least Privilege

### ECS Task Execution Role Permissions
The task execution role has ONLY:
- `AmazonECSTaskExecutionRolePolicy` — pull ECR images, write CloudWatch logs
- Custom SSM read policy — read ONLY from `/skynet-ops-audit-service/dev/*` path

### What is explicitly NOT granted
- No S3 access
- No RDS access
- No EC2 access
- No IAM mutation permissions
- No cross-account access

### Dangerous Permissions to Avoid
- ❌ `iam:*` — never grant to app roles
- ❌ `*:*` (AdministratorAccess) — never use for service roles
- ❌ `ssm:GetParameters` on `*` — scoped to service path only

---

## Container Security

### Dockerfile Hardening
- Base image: `python:3.11-slim` — minimal attack surface vs full image
- No root user needed (Fargate handles isolation)
- `.dockerignore` excludes: `.env`, `.git`, `__pycache__`, `*.pyc`, `events.db`
- No secrets baked into image layers

### Network Security
- Security group allows inbound ONLY on port 3000
- No SSH (port 22) open
- All outbound allowed (needed for SSM, ECR, CloudWatch)
- No public S3 buckets or open storage

---

## Public Exposure Controls

- Service runs on non-standard port 3000 (not 80/443)
- Security group is the only network perimeter
- For production: add ALB with HTTPS termination + WAF
- For pilot: restrict security group to known IPs if possible:

```bash
# Restrict to your IP only
MY_IP=$(curl -s https://checkip.amazonaws.com)
aws ec2 authorize-security-group-ingress \
  --group-id <SG_ID> \
  --protocol tcp --port 3000 --cidr "$MY_IP/32"
```

---

## What is Committed to Git (safe)
- `terraform/main.tf`, `variables.tf`, `outputs.tf` — no secrets
- `terraform/terraform.tfvars.example` — placeholder values only
- `.env.example` — placeholder values only
- All docs

## What is NOT Committed to Git
- `.env` (in .gitignore)
- `terraform/terraform.tfvars` (in .gitignore)
- `events.db`
- Any AWS credentials or access keys
