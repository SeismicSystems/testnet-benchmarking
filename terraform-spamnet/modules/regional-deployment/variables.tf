variable "region" {
  description = "AWS region for this deployment"
  type        = string
}

variable "instances_per_region" {
  description = "Number of instances to create in this region"
  type        = number
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "m5.xlarge"
}

variable "volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 200
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}
