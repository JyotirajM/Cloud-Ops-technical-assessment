# Copy to terraform.tfvars — DO NOT commit terraform.tfvars to git

aws_region         = "us-east-1"
environment        = "dev"
service_name       = "skynet-ops-audit-service"
dockerhub_image    = "hitesh008/skynet-ops-service:latest"
log_level          = "info"
log_retention_days = 7
api_key            = "your-strong-random-key"
monthly_budget_usd = "30"
alert_email        = "email@gmail.com"
