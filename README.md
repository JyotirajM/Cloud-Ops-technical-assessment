# skynet-ops-audit-service

A lightweight operational audit event service for the AIRMAN Skynet ecosystem.
Built for the Cloud Ops Intern Technical Assessment — Level 1.

---

## Stack

| Layer | Technology |
|-------|-----------|
| Language | Python 3.11 |
| Framework | FastAPI + Uvicorn |
| Storage | SQLite (via SQLAlchemy) |
| Metrics | Prometheus client |
| Container | Docker |
| Cloud | AWS ECS Fargate |
| IaC | Terraform |
| Secrets | AWS SSM Parameter Store |
| Observability | AWS CloudWatch Logs + Container Insights |

---

## Project Structure

```
skynet-ops-audit-service/
├── app/
│   ├── main.py           # FastAPI app, middleware, metrics
│   ├── routes.py         # All endpoints
│   ├── models.py         # SQLAlchemy Event model
│   ├── schemas.py        # Pydantic request/response schemas
│   └── database.py       # SQLite engine + session
├── terraform/
│   ├── main.tf           # ECR, ECS, VPC, CloudWatch, Budget
│   ├── variables.tf      # All input variables
│   ├── outputs.tf        # Useful outputs after apply
│   └── terraform.tfvars.example
├── docs/
│   ├── cost_report.md    # Monthly cost estimate + controls
│   ├── runbook.md        # Incident response scenarios
│   ├── observability.md  # Logging + metrics + alerts
│   └── security.md       # Secrets + IAM + hardening
├── .env.example
├── .gitignore
├── Dockerfile
├── .dockerignore
├── requirements.txt
└── submission_checklist.md
```

---

## Local Setup & Run

### Prerequisites
- Python 3.11+
- Docker
- AWS CLI (for cloud deployment)
- Terraform >= 1.5.0

### 1. Clone and install

```bash
git clone https://github.com/JyotirajM/Cloud-Ops-technical-assessment
cd skynet-ops-audit-service

# Create virtual environment
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

### 2. Configure environment

```bash
cp .env .env
# Edit .env with your values
```

### 3. Run locally

```bash
uvicorn app.main:app --host 0.0.0.0 --port 3000 --reload
```

Service is now running at: `http://localhost:3000`

---

## Test Endpoints Locally

```bash
# Health check
curl http://localhost:3000/health

# Post an event
curl -X POST http://localhost:3000/events \
  -H "Content-Type: application/json" \
  -d '{
    "type": "roster_update",
    "tenantId": "academy_001",
    "severity": "info",
    "message": "Instructor schedule adjusted for morning slot",
    "source": "skynet-api"
  }'

# Get events (all)
curl http://localhost:3000/events

# Get events (filtered)
curl "http://localhost:3000/events?tenantId=academy_001&severity=info&limit=10"

# Validation test — should return 400
curl -X POST http://localhost:3000/events \
  -H "Content-Type: application/json" \
  -d '{"type": "test", "tenantId": "", "severity": "bad", "message": "", "source": "x"}'

# Metrics demo
curl "http://localhost:3000/metrics-demo"
curl "http://localhost:3000/metrics-demo?mode=error"
curl "http://localhost:3000/metrics-demo?mode=slow"
curl "http://localhost:3000/metrics-demo?mode=burst"

# Prometheus metrics
curl http://localhost:3000/metrics
```

---

## Docker

### Build

```bash
docker build -t skynet-ops-audit-service:latest .
```

### Run with Docker

```bash
docker run -p 3000:3000 \
  -e APP_ENV=dev \
  -e LOG_LEVEL=info \
  -e SERVICE_NAME=skynet-ops-audit-service \
  skynet-ops-audit-service:latest
```

---

## Cloud Deployment (AWS ECS Fargate)

### Prerequisites
- AWS CLI configured: `aws configure`
- Terraform installed: `terraform -version`
- Docker running

### Step 1 — Provision Infrastructure

```bash
cd terraform

# Copy and fill in your values
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set alert_email, api_key, aws_region

terraform init
terraform validate
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"
```

After apply, note the `ecr_repository_url` output value.

### Step 2 — Build and Push Docker Image to ECR

```bash
# Get ECR URL from terraform output
ECR_URL=$(terraform output -raw ecr_repository_url)
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Authenticate Docker to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_URL

# Build and push
cd ..
docker build -t skynet-ops-audit-service:latest .
docker tag skynet-ops-audit-service:latest $ECR_URL:latest
docker push $ECR_URL:latest
```

### Step 3 — Deploy to ECS

```bash
# Force ECS to pull the new image
aws ecs update-service \
  --cluster skynet-ops-audit-service-dev \
  --service skynet-ops-audit-service-dev \
  --force-new-deployment

# Wait for service to stabilize
aws ecs wait services-stable \
  --cluster skynet-ops-audit-service-dev \
  --services skynet-ops-audit-service-dev
```

### Step 4 — Get Service URL

```bash
TASK_ARN=$(aws ecs list-tasks \
  --cluster skynet-ops-audit-service-dev \
  --query "taskArns[0]" --output text)

ENI_ID=$(aws ecs describe-tasks \
  --cluster skynet-ops-audit-service-dev \
  --tasks $TASK_ARN \
  --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value" \
  --output text)

PUBLIC_IP=$(aws ec2 describe-network-interfaces \
  --network-interface-ids $ENI_ID \
  --query "NetworkInterfaces[0].Association.PublicIp" --output text)

echo "Service URL: http://$PUBLIC_IP:3000"
curl http://$PUBLIC_IP:3000/health
```

---

## Scale to Zero (Cost Saving)

```bash
# Stop all tasks (zero cost for compute)
aws ecs update-service \
  --cluster skynet-ops-audit-service-dev \
  --service skynet-ops-audit-service-dev \
  --desired-count 0

# Restart
aws ecs update-service \
  --cluster skynet-ops-audit-service-dev \
  --service skynet-ops-audit-service-dev \
  --desired-count 1
```

---

## Full Teardown

```bash
# Scale to zero first
aws ecs update-service \
  --cluster skynet-ops-audit-service-dev \
  --service skynet-ops-audit-service-dev \
  --desired-count 0

# Destroy all AWS infrastructure
cd terraform
terraform destroy -var-file="terraform.tfvars"
# Type: yes
```

> Note: CloudWatch logs are deleted with the log group on destroy. Export logs first if needed.

---

## API Reference

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Service health check |
| POST | `/events` | Ingest an audit event |
| GET | `/events` | List events (with filters) |
| GET | `/metrics` | Prometheus metrics |
| GET | `/metrics-demo` | Observability test endpoint |

### POST /events — Required Fields
| Field | Type | Values |
|-------|------|--------|
| type | string | e.g. `roster_update` |
| tenantId | string | non-empty |
| severity | string | `info`, `warning`, `error`, `critical` |
| message | string | non-empty |
| source | string | e.g. `skynet-api` |

### GET /events — Query Parameters
| Param | Type | Default |
|-------|------|---------|
| tenantId | string | — |
| severity | string | — |
| limit | integer | 20 (max 100) |
| offset | integer | 0 |

---

## Docs

- [Cost Report](docs/cost_report.md)
- [Ops Runbook](docs/runbook.md)
- [Observability](docs/observability.md)
- [Security & Secrets](docs/security.md)
