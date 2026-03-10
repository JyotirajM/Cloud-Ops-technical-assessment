variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "service_name" {
  description = "Service name"
  type        = string
  default     = "skynet-ops-audit-service"
}

variable "dockerhub_image" {
  description = "Your Docker Hub image (e.g. yourusername/skynet-ops-audit-service:latest)"
  type        = string
}

variable "log_level" {
  description = "Application log level"
  type        = string
  default     = "info"
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}

variable "api_key" {
  description = "API key stored in SSM SecureString"
  type        = string
  sensitive   = true
  default     = "change-me-before-deploy"
}

variable "monthly_budget_usd" {
  description = "Monthly budget cap in USD"
  type        = string
  default     = "30"
}

variable "alert_email" {
  description = "Email for billing and CloudWatch alerts"
  type        = string
  default     = "email@gmail.com"
}
