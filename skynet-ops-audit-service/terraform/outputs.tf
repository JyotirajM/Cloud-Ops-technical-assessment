output "elastic_ip" {
  description = "Stable public IP of your EC2 instance (won't change on restart)"
  value       = aws_eip.app.public_ip
}

output "service_url" {
  description = "Your service URL"
  value       = "http://${aws_eip.app.public_ip}:3000"
}

output "health_check_url" {
  description = "Health check URL"
  value       = "http://${aws_eip.app.public_ip}:3000/health"
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group"
  value       = aws_cloudwatch_log_group.app.name
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.app.id
}
