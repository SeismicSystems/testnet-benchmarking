output "public_ips" {
  description = "Public IP addresses of instances in this region"
  value       = aws_instance.multi[*].public_ip
}

output "private_ips" {
  description = "Private IP addresses of instances in this region"
  value       = aws_instance.multi[*].private_ip
}

output "instance_ids" {
  description = "Instance IDs in this region"
  value       = aws_instance.multi[*].id
}

output "availability_zones" {
  description = "Availability zones of instances in this region"
  value       = aws_instance.multi[*].availability_zone
}

output "volume_ids" {
  description = "Root volume IDs of instances in this region"
  value       = [for instance in aws_instance.multi : instance.root_block_device[0].volume_id]
}

output "instance_types" {
  description = "Instance types in this region"
  value       = aws_instance.multi[*].instance_type
}

output "instance_names" {
  description = "Instance names (from tags) in this region"
  value       = [for instance in aws_instance.multi : lookup(instance.tags, "Name", "unnamed")]
}

output "region" {
  description = "AWS region"
  value       = var.region
}

output "key_pair_name" {
  description = "Name of the key pair used"
  value       = aws_key_pair.deployer.key_name
}

output "security_group_ids" {
  description = "Security group IDs"
  value = {
    ssh    = aws_security_group.ssh.id
    docker = aws_security_group.docker.id
  }
}
