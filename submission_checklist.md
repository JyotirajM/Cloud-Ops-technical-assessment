# AIRMAN Skynet Cloud Ops Intern Assessment — Submission Checklist

---

## 1) Candidate & Submission Info

- **Name:** Jyotiraj Aditinandan Mahanta
- **Email:** jyotirajm008@gmail.com
- **Chosen Cloud Platform:** AWS
- **Assessment Level Submitted:** Level 1 only
- **Level 2 Option Chosen (if any):** N/A
- **GitHub Repo Link:** https://github.com/JyotirajM/Cloud-Ops-technical-assessment.git
- **Demo Video Link (optional but recommended):** [Optional]
- **Submission Date (UTC):** 11/03/2026

---

## 2) What I Implemented (Summary)

### Level 1
- [x] Mini service (`/health`, `POST /events`, `GET /events`, `GET /metrics-demo`, `GET /metrics`)
- [x] Dockerized service — image pushed to Docker Hub (`hitesh008/skynet-ops-service:latest`)
- [x] Cloud deployment — AWS EC2 t3.micro (Ubuntu 22.04), container running live
- [x] Infrastructure as Code — Terraform (EC2 + VPC + Security Group + CloudWatch + Budget)
- [x] Cost optimization report
- [x] Observability setup — CloudWatch Logs + 2 CloudWatch Alarms
- [x] Security/secrets approach — SSM Parameter Store, least-privilege IAM
- [x] Ops runbook — 6 incident scenarios with CLI commands
- [x] README with setup + teardown

---

## 3) Repository Structure

### Service Code
- Service path: `app/`
- Main entry file: `app/main.py`
- Local run command: `uvicorn app.main:app --host 0.0.0.0 --port 3000 --reload`

### Docker
- Dockerfile path: `Dockerfile`
- `.dockerignore` path: `.dockerignore`
- Docker Hub image: `hitesh008/skynet-ops-service:latest`

### Infrastructure as Code
- IaC tool used: Terraform
- IaC root path: `terraform/`
- Environment config files: `terraform/terraform.tfvars.example`

### Docs
- README path: `README.md`
- Cost report path: `docs/cost_report.md`
- Runbook path: `docs/runbook.md`
- Observability notes path: `docs/observability.md`
- Security/secrets notes path: `docs/security.md`

---

## 4) Local Run Instructions

### Prerequisites
- [x] Docker installed
- [x] Python 3.11+ installed
- [x] Terraform >= 1.5.0 installed
- [x] AWS CLI installed and configured (`aws configure`)

### Local Setup
```bash
git clone <repo-url>
cd skynet-ops-audit-service
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

### Run Service Locally
```bash
uvicorn app.main:app --host 0.0.0.0 --port 3000 --reload
```

### Test Endpoints Locally
```bash
curl http://localhost:3000/health

curl -X POST http://localhost:3000/events \
  -H "Content-Type: application/json" \
  -d '{"type":"roster_update","tenantId":"academy_001","severity":"info","message":"Test event","source":"skynet-api"}'

curl http://localhost:3000/events

curl "http://localhost:3000/events?tenantId=academy_001&severity=info"

curl "http://localhost:3000/metrics-demo?mode=error"
```

---

## 5) API Endpoint Checklist (Functional Validation)

### Health
- [x] `GET /health` — returns status, service name, environment, timestamp

### Events
- [x] `POST /events` — stores event, returns eventId + storedAt (201)
- [x] `GET /events` — returns events newest first, paginated
- [x] Validation rejects bad payloads (400) — empty tenantId, invalid severity

### Optional
- [x] `GET /metrics-demo` implemented
- [x] Simulates latency (`?mode=slow`), errors (`?mode=error`), burst logs (`?mode=burst`)

---

## 6) Cloud Deployment Summary

### Deployment Type
- [x] Real cloud deployment — AWS EC2 t3.micro running live

### Cloud Services Used

- **Compute:** AWS EC2 t3.micro (Ubuntu 22.04)
- **Container:** Docker — image pulled from Docker Hub (`hitesh008/skynet-ops-service:latest`)
- **Storage/DB:** SQLite (file-based, in-container) — see cost report for upgrade path
- **Networking/Ingress:** VPC, public subnet, Internet Gateway, Security Group (port 3000)
- **Logging/Monitoring:** CloudWatch Logs (7-day retention), 2 CloudWatch Alarms
- **Secrets:** AWS SSM Parameter Store (SecureString for API_KEY)
- **Budgeting/Alerts:** AWS Budgets ($30/month cap, 80% + 100% alerts)
- **IAM:** EC2 Instance Role (least-privilege — CloudWatch write + SSM read only)

### Why I chose this architecture
- EC2 + Docker is simple, transparent, and easy to debug for a pilot deployment
- Docker Hub for image registry avoids ECR setup complexity while keeping deployment clean
- `--restart unless-stopped` ensures container auto-recovers from crashes without extra tooling
- CloudWatch log driver built into Docker — no extra agent needed on EC2
- SQLite avoids RDS minimum cost (~$15–30/month) for a low-volume pilot

### Pilot Cost-Awareness Notes
- Estimated monthly cost: ~$8–12/month (well within $25–75 target)
- Instance stopped outside working hours to avoid idle compute cost
- All resources tagged for cost attribution via Terraform default_tags
- Budget alert fires at 80% actual and 100% forecasted spend
- No Elastic IP (avoids ~$3.60/month charge when instance is stopped)

---

## 7) Cost Optimization Report

- [x] Monthly estimate included — see `docs/cost_report.md`
- [x] Assumptions documented
- [x] Component-wise cost breakdown included

### Cost Controls Implemented
- [x] Budgets — $30/month AWS Budget with 2 alert thresholds
- [x] Billing alerts — 80% actual + 100% forecasted
- [x] Tags / labels — `default_tags` in Terraform provider
- [x] Log retention policy — 7 days dev
- [x] Non-prod shutdown — `aws ec2 stop-instances` when not in use
- [x] Teardown (`destroy`) instructions — `terraform destroy` in README

### Common Cost Traps Accounted For
1. Idle compute — instance stopped outside working hours
2. Overprovisioned managed DB — SQLite used instead of RDS
3. Excessive logging — 7-day retention, info-level default
4. NAT Gateway costs — No NAT Gateway; public subnet used
5. Snapshots and unattached disks — No extra EBS volumes provisioned
6. Static IPs — No Elastic IP attached (saves cost when instance stopped)
7. Load balancer left running — No ALB provisioned for pilot
8. Cross-region traffic — All resources in single region
9. Untagged resources — Terraform default_tags applied to all resources
10. CloudWatch unlimited log retention — Explicit 7-day retention set

---

## 8) Observability & Monitoring

### Logging
- [x] Structured logs — Python logging via FastAPI middleware (method + URL per request)
- [x] Log level configurable via `LOG_LEVEL` env var
- [x] Logs shipped to CloudWatch via Docker `awslogs` log driver
- [x] Log group: `/ec2/skynet-ops-audit-service/dev`

### Metrics
- [x] Request count — Prometheus counter at `GET /metrics`
- [x] Error rate — CloudWatch `StatusCheckFailed` metric
- [x] CPU utilization — CloudWatch `CPUUtilization` metric on EC2
- [x] Health signal — CloudWatch instance status alarm

### Alerts
- [x] Alert #1: High CPU — EC2 CPU > 80% for 2 minutes → CloudWatch Alarm
- [x] Alert #2: Instance down — StatusCheckFailed > 0 → CloudWatch Alarm

### Evidence
- Monitoring configuration documented in `docs/observability.md`
- `/metrics-demo` endpoint enables live observability testing

---

## 9) Security / Secrets / IAM

### Secrets
- [x] No secrets committed to repo — `.env` and `terraform.tfvars` in `.gitignore`
- [x] `.env.example` included
- [x] Secrets management documented in `docs/security.md`

### IAM / Access Control
- [x] EC2 Instance Role attached — `CloudWatchAgentServerPolicy` + scoped SSM read
- [x] Least-privilege — SSM access scoped to `/skynet-ops-audit-service/dev/*` only
- [x] No hardcoded credentials anywhere in code or config files

### Security Basics
- [x] `python:3.11-slim` base image — minimal attack surface
- [x] `.dockerignore` excludes `.env`, `.git`, `events.db`
- [x] Security group restricts inbound to port 3000 only

---

## 10) Ops Runbook

- **Runbook file path:** `docs/runbook.md`

### Covered Scenarios
- [x] Service down / health checks failing
- [x] Latency spike
- [x] Sudden cost spike
- [x] DB/storage issue
- [x] Bad deployment / rollback
- [x] Accidental public exposure / misconfiguration

---

## 11) IaC Validation / Reproducibility

### Terraform
- [x] `terraform init` works
- [x] `terraform validate` works
- [x] `terraform plan` works
- [x] Variables documented — `terraform/variables.tf`
- [x] Outputs documented — `terraform/outputs.tf`

### Teardown
- [x] Destroy/cleanup steps documented — `terraform destroy` in README
- [x] Resource cleanup caveats noted — SQLite data is ephemeral; CloudWatch logs deleted on destroy

---

## 12) Known Limitations / Trade-offs

1. **SQLite is ephemeral** — Data lost on container restart. Acceptable for pilot. Upgrade path: Docker volume mount or RDS PostgreSQL.
2. **No HTTPS / TLS** — Plain HTTP on port 3000. For production: add ALB with ACM certificate.
3. **No load balancer** — Single EC2 instance, no failover. Acceptable for pilot; add ALB + Auto Scaling for production.
4. **Public IP changes on restart** — No Elastic IP (cost decision for pilot). Document current IP in README before submission.
5. **No authentication middleware** — API_KEY stored in SSM but not enforced in route handlers. Would add Bearer token validation for production.

---

## 13) AI Tool Usage Disclosure

### AI tools used
- [x] Claude

### What I used AI for
- Generating Terraform IaC (EC2 + VPC + CloudWatch + Budgets)
- Drafting cost report, runbook, observability, and security documentation
- Debugging EC2 setup issues (IAM role, Docker permissions, CloudWatch log driver)
- Filling the submission checklist

### What I manually verified / tested
- Python service code (app/, routes, models, schemas, database)
- Dockerfile — built and pushed to Docker Hub
- All API endpoints tested live on EC2
- Container running with auto-restart confirmed (`docker ps`)
- CloudWatch logs verified receiving traffic
- Terraform validate and plan confirmed working

---

## 14) Final Notes

Deployed on AWS EC2 t3.micro (Ubuntu 22.04) with Docker, pulling image from Docker Hub.
The architecture prioritizes simplicity and cost efficiency for pilot scale — EC2 + Docker over
ECS Fargate, SQLite over RDS, SSM over Secrets Manager — with clear documented upgrade
paths for each trade-off. Live service URL: `http://172.31.13.111:3000`
