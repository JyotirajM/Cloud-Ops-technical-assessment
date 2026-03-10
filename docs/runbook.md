# Ops Runbook — skynet-ops-audit-service
## Environment: AWS ECS Fargate (ap-south-1)

---

## Quick Reference

| Item | Value |
|------|-------|
| Cluster | `skynet-ops-audit-service-dev` |
| Service | `skynet-ops-audit-service-dev` |
| Log Group | `/ecs/skynet-ops-audit-service/dev` |
| Health endpoint | `http://<TASK_PUBLIC_IP>:3000/health` |
| Metrics endpoint | `http://<TASK_PUBLIC_IP>:3000/metrics` |
| Region | `ap-south-1` |

### Get current task public IP
```bash
TASK_ARN=$(aws ecs list-tasks \
  --cluster skynet-ops-audit-service-dev \
  --query "taskArns[0]" --output text)

ENI_ID=$(aws ecs describe-tasks \
  --cluster skynet-ops-audit-service-dev \
  --tasks $TASK_ARN \
  --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value" \
  --output text)

aws ec2 describe-network-interfaces \
  --network-interface-ids $ENI_ID \
  --query "NetworkInterfaces[0].Association.PublicIp" --output text
```

---

## Scenario 1 — Service Down / Health Check Failing

**Symptoms:** CloudWatch alarm `service-down` firing. `GET /health` returns no response or 5xx.

**Steps:**
```bash
# 1. Check running task count
aws ecs describe-services \
  --cluster skynet-ops-audit-service-dev \
  --services skynet-ops-audit-service-dev \
  --query "services[0].runningCount"

# 2. Check recent logs for crash reason
aws logs tail /ecs/skynet-ops-audit-service/dev --since 30m

# 3. Check task stopped reason
aws ecs list-tasks \
  --cluster skynet-ops-audit-service-dev \
  --desired-status STOPPED \
  --query "taskArns[0]" --output text | xargs -I{} \
  aws ecs describe-tasks --cluster skynet-ops-audit-service-dev --tasks {} \
  --query "tasks[0].stoppedReason"

# 4. Force new deployment (restarts the task)
aws ecs update-service \
  --cluster skynet-ops-audit-service-dev \
  --service skynet-ops-audit-service-dev \
  --force-new-deployment

# 5. Wait and verify health
sleep 30
curl http://<TASK_PUBLIC_IP>:3000/health
```

---

## Scenario 2 — Latency Spike

**Symptoms:** Response times > 1000ms on GET /events or POST /events. Users reporting slow API.

**Steps:**
```bash
# 1. Check logs for slow queries or errors
aws logs tail /ecs/skynet-ops-audit-service/dev --since 15m | grep -i "slow\|timeout\|error"

# 2. Test metrics-demo slow endpoint to confirm service is processing
curl "http://<TASK_PUBLIC_IP>:3000/metrics-demo?mode=normal"

# 3. Check Prometheus metrics for request count and errors
curl http://<TASK_PUBLIC_IP>:3000/metrics | grep request_count

# 4. Check Fargate task CPU/memory in CloudWatch console
# Navigate: CloudWatch > Metrics > ECS > ClusterName/ServiceName > CPUUtilization

# 5. If CPU is >80%: scale up task count temporarily
aws ecs update-service \
  --cluster skynet-ops-audit-service-dev \
  --service skynet-ops-audit-service-dev \
  --desired-count 2

# 6. Root cause: if SQLite locking, consider EFS mount or DB migration
```

**Alert threshold:** Latency > 1000ms for 2 consecutive minutes on GET /events.

---

## Scenario 3 — Sudden Cost Spike

**Symptoms:** AWS Budget alert email received (>80% of $50 monthly budget).

**Steps:**
```bash
# 1. Check AWS Cost Explorer (console) for top cost drivers
# Navigate: AWS Console > Billing > Cost Explorer > Last 7 days, group by Service

# 2. Immediately scale down if not needed
aws ecs update-service \
  --cluster skynet-ops-audit-service-dev \
  --service skynet-ops-audit-service-dev \
  --desired-count 0

# 3. Check for accidentally left-on resources
aws ec2 describe-instances --region ap-south-1 \
  --query "Reservations[].Instances[?State.Name=='running'].[InstanceId,InstanceType]"

aws ecs list-clusters --region ap-south-1

# 4. Check CloudWatch log ingestion volume
aws logs describe-log-groups \
  --query "logGroups[*].[logGroupName,storedBytes]" --output table

# 5. If excessive logs: reduce log level
aws ssm put-parameter \
  --name "/skynet-ops-audit-service/dev/LOG_LEVEL" \
  --value "warning" --overwrite --type String

# Then force new deployment to pick up new env var
aws ecs update-service \
  --cluster skynet-ops-audit-service-dev \
  --service skynet-ops-audit-service-dev \
  --force-new-deployment
```

---

## Scenario 4 — DB / Storage Issue

**Symptoms:** POST /events returns 500. Logs show SQLite errors.

**Note:** SQLite in Fargate is ephemeral. Data loss on task restart is expected in this pilot setup.

```bash
# 1. Check logs for DB errors
aws logs tail /ecs/skynet-ops-audit-service/dev --since 10m | grep -i "sqlite\|database\|error"

# 2. Force restart (SQLite will reinitialize cleanly on new task)
aws ecs update-service \
  --cluster skynet-ops-audit-service-dev \
  --service skynet-ops-audit-service-dev \
  --force-new-deployment

# 3. Verify POST /events works after restart
curl -X POST http://<TASK_PUBLIC_IP>:3000/events \
  -H "Content-Type: application/json" \
  -d '{"type":"roster_update","tenantId":"academy_001","severity":"info","message":"test","source":"runbook-test"}'
```

**Upgrade path for persistence:** Mount Amazon EFS at `/app/events.db` path.

---

## Scenario 5 — Bad Deployment / Rollback

**Symptoms:** New image deployed, service returning errors or failing health checks.

```bash
# 1. Find the previous stable task definition revision
aws ecs list-task-definitions \
  --family-prefix skynet-ops-audit-service-dev \
  --sort DESC --query "taskDefinitionArns[0:5]"

# 2. Roll back to previous revision (e.g., revision :3)
aws ecs update-service \
  --cluster skynet-ops-audit-service-dev \
  --service skynet-ops-audit-service-dev \
  --task-definition skynet-ops-audit-service-dev:3

# 3. Monitor rollback
aws ecs wait services-stable \
  --cluster skynet-ops-audit-service-dev \
  --services skynet-ops-audit-service-dev

# 4. Verify health
curl http://<TASK_PUBLIC_IP>:3000/health
```

---

## Scenario 6 — Accidental Public Exposure / Misconfiguration

**Symptoms:** Security concern — sensitive endpoint unexpectedly public, or wrong security group rule.

```bash
# 1. Immediately restrict security group to your IP only
MY_IP=$(curl -s https://checkip.amazonaws.com)

SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=skynet-ops-audit-service-dev-sg" \
  --query "SecurityGroups[0].GroupId" --output text)

# Revoke broad public access
aws ec2 revoke-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp --port 3000 --cidr 0.0.0.0/0

# Re-add with your IP only
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp --port 3000 --cidr "$MY_IP/32"

# 2. Rotate API_KEY immediately
aws ssm put-parameter \
  --name "/skynet-ops-audit-service/dev/API_KEY" \
  --value "new-strong-random-key" \
  --overwrite --type SecureString

# 3. Force new deployment to pick up rotated key
aws ecs update-service \
  --cluster skynet-ops-audit-service-dev \
  --service skynet-ops-audit-service-dev \
  --force-new-deployment

# 4. Review CloudWatch logs for any unauthorized access
aws logs tail /ecs/skynet-ops-audit-service/dev --since 24h | grep -i "401\|403\|unauthorized"
```

---

## Daily Ops Checklist (Pilot)

- [ ] Check `GET /health` returns `"status": "ok"`
- [ ] Check CloudWatch alarms — no alarms in ALARM state
- [ ] Check AWS Budget — not exceeding 80% threshold
- [ ] Scale down ECS service at end of working day if not needed
