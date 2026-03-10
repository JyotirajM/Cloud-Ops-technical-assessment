terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "skynet-ops-audit-service"
      Environment = var.environment
      ManagedBy   = "terraform"
      CostCenter  = "skynet-pilot"
    }
  }
}

# ─────────────────────────────────────────────
# SSM Parameter Store — Secrets
# ─────────────────────────────────────────────
resource "aws_ssm_parameter" "app_env" {
  name  = "/${var.service_name}/${var.environment}/APP_ENV"
  type  = "String"
  value = var.environment
}

resource "aws_ssm_parameter" "log_level" {
  name  = "/${var.service_name}/${var.environment}/LOG_LEVEL"
  type  = "String"
  value = var.log_level
}

resource "aws_ssm_parameter" "api_key" {
  name  = "/${var.service_name}/${var.environment}/API_KEY"
  type  = "SecureString"
  value = var.api_key
}

# ─────────────────────────────────────────────
# IAM — EC2 Instance Role (CloudWatch + SSM)
# ─────────────────────────────────────────────
resource "aws_iam_role" "ec2_role" {
  name = "${var.service_name}-${var.environment}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy" "ssm_read" {
  name = "ssm-read"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameters", "ssm:GetParameter"]
      Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${var.service_name}/${var.environment}/*"
    }]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.service_name}-${var.environment}-profile"
  role = aws_iam_role.ec2_role.name
}

# ─────────────────────────────────────────────
# VPC + Subnet + Internet Gateway
# ─────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ─────────────────────────────────────────────
# Security Group — port 3000 only
# ─────────────────────────────────────────────
resource "aws_security_group" "app" {
  name        = "${var.service_name}-${var.environment}-sg"
  description = "Allow inbound on port 3000 only"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "App port"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH - restrict to your IP in production"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ─────────────────────────────────────────────
# Elastic IP — stable public IP (won't change on restart)
# ─────────────────────────────────────────────
resource "aws_eip" "app" {
  instance = aws_instance.app.id
  domain   = "vpc"
}

# ─────────────────────────────────────────────
# EC2 Instance — t3.micro Ubuntu 22.04
# ─────────────────────────────────────────────
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  # User data: install Docker, pull image, run with auto-restart + CloudWatch logs
  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Install Docker
    apt-get update -y
    apt-get install -y docker.io awslogs
    systemctl enable docker
    systemctl start docker

    # Pull and run container with:
    # - auto-restart on crash (--restart unless-stopped)
    # - CloudWatch log driver
    docker run -d \
      --name skynet-ops-audit-service \
      --restart unless-stopped \
      -p 3000:3000 \
      -e APP_ENV=${var.environment} \
      -e LOG_LEVEL=${var.log_level} \
      -e SERVICE_NAME=${var.service_name} \
      -e DATABASE_URL=sqlite:///./events.db \
      --log-driver=awslogs \
      --log-opt awslogs-region=${var.aws_region} \
      --log-opt awslogs-group=/ec2/${var.service_name}/${var.environment} \
      --log-opt awslogs-create-group=true \
      ${var.dockerhub_image}
  EOF

  tags = {
    Name = "${var.service_name}-${var.environment}"
  }
}

# ─────────────────────────────────────────────
# CloudWatch Log Group
# ─────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ec2/${var.service_name}/${var.environment}"
  retention_in_days = var.log_retention_days
}

# ─────────────────────────────────────────────
# CloudWatch Alarms
# ─────────────────────────────────────────────

# Alert 1: High CPU (proxy for latency/overload)
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.service_name}-${var.environment}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "EC2 CPU > 80% for 2 minutes — possible overload"
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = aws_instance.app.id
  }

  alarm_actions = []
}

# Alert 2: Instance status check failed (instance down)
resource "aws_cloudwatch_metric_alarm" "instance_down" {
  alarm_name          = "${var.service_name}-${var.environment}-instance-down"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "EC2 status check failed — instance may be down"
  treat_missing_data  = "breaching"

  dimensions = {
    InstanceId = aws_instance.app.id
  }

  alarm_actions = []
}

# ─────────────────────────────────────────────
# AWS Budget Alert
# ─────────────────────────────────────────────
resource "aws_budgets_budget" "monthly" {
  name         = "${var.service_name}-${var.environment}-monthly-budget"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}
