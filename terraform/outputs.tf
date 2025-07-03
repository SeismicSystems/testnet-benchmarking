output "instance_ips" {
  description = "Public IP addresses of all instances"
  value = aws_instance.multi[*].public_ip
}

output "deployment_summary" {
  description = "Summary of the deployment"
  value = {
    total_instances = length(aws_instance.multi)
    region         = "us-west-2"
  }
} 