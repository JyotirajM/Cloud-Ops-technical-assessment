# Observability Setup — skynet-ops-audit-service

---

## Logging

### Implementation
- Structured logs via Python's built-in `logging` module
- Every HTTP request logged via FastAPI middleware: method, URL, timestamp
- Log level configurable via `LOG_LEVEL` environment variable (pulled from SSM)
- Logs shipped to **AWS CloudWatch Logs** via ECS `awslogs` log driver

### Log Group
```
/ecs/skynet-ops-audit-service/dev
```

### Retention Policy
| Environment | Retention |
|-------------|-----------|
| Dev         | 7 days    |
| Pilot/Staging | 14 days (recommended) |

### Sample Log Output
```json
INFO:skynet-service:Request received: GET /health
INFO:skynet-service:Request received: POST /events
INFO:skynet-service:Request received: GET /events?tenantId=academy_001&severity=warning
INFO:uvicorn.access:127.0.0.1:56789 - "POST /events HTTP/1.1" 201
```

### Viewing Logs
```bash
# Tail live logs
aws logs tail /ecs/skynet-ops-audit-service/dev --follow

# Last 30 minutes
aws logs tail /ecs/skynet-ops-audit-service/dev --since 30m

# Filter for errors only
aws logs filter-log-events \
  --log-group-name /ecs/skynet-ops-audit-service/dev \
  --filter-pattern "ERROR"
```

---

## Metrics

### Prometheus Metrics (built-in)
The service exposes a `/metrics` endpoint via `prometheus-client`:

| Metric | Type | Description |
|--------|------|-------------|
| `request_count` | Counter | Total HTTP requests received since startup |

**Endpoint:** `GET http://<TASK_IP>:3000/metrics`

### CloudWatch Container Insights Metrics
Enabled on ECS cluster. Available metrics:

| Metric | Namespace | Description |
|--------|-----------|-------------|
| `RunningTaskCount` | ECS/ContainerInsights | Number of healthy running tasks |
| `CPUUtilization` | ECS/ContainerInsights | Fargate task CPU usage % |
| `MemoryUtilization` | ECS/ContainerInsights | Fargate task memory usage % |
| `5xxErrorCount` | ECS/ContainerInsights | HTTP 5xx error count |

---

## Alerts

### Alert 1 — High Error Rate
| Property | Value |
|----------|-------|
| Name | `skynet-ops-audit-service-dev-high-error-rate` |
| Metric | `5xxErrorCount` |
| Threshold | > 10 errors in 1 minute |
| Evaluation | 2 consecutive periods |
| Rationale | 10 errors/min on a low-traffic pilot service indicates a real problem (bad deploy, DB failure, unhandled exception) |

### Alert 2 — Service Down
| Property | Value |
|----------|-------|
| Name | `skynet-ops-audit-service-dev-service-down` |
| Metric | `RunningTaskCount` |
| Threshold | < 1 running task |
| Evaluation | 1 period (60s) |
| Rationale | Zero tasks = service completely unavailable. Immediate attention needed. |

### Adding Email Notifications to Alerts
```bash
# 1. Create SNS topic
aws sns create-topic --name skynet-ops-alerts-dev

# 2. Subscribe your email
aws sns subscribe \
  --topic-arn arn:aws:sns:ap-south-1:<ACCOUNT_ID>:skynet-ops-alerts-dev \
  --protocol email \
  --notification-endpoint your-email@example.com

# 3. Add the topic ARN to alarm_actions in terraform/main.tf and re-apply
```

---

## Observability Testing with /metrics-demo

The `/metrics-demo` endpoint can simulate different traffic patterns to validate your observability setup:

```bash
# Test normal response
curl "http://<TASK_IP>:3000/metrics-demo"

# Simulate 500 error (check CloudWatch for error alarm)
curl "http://<TASK_IP>:3000/metrics-demo?mode=error"

# Simulate slow response (check latency in Container Insights)
curl "http://<TASK_IP>:3000/metrics-demo?mode=slow"

# Generate burst log traffic (check CloudWatch Logs dashboard)
curl "http://<TASK_IP>:3000/metrics-demo?mode=burst"
```

---

## Recommended CloudWatch Dashboard (Manual Setup)

Create a dashboard in CloudWatch console with these widgets:

1. **RunningTaskCount** — Line chart, last 3 hours
2. **CPUUtilization** — Line chart, last 1 hour
3. **MemoryUtilization** — Line chart, last 1 hour
4. **Log Insights query** — Recent errors:
   ```
   fields @timestamp, @message
   | filter @message like /ERROR/
   | sort @timestamp desc
   | limit 20
   ```
