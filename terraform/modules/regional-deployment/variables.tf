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

variable "additional_ssh_public_key_path" {
  description = "Path to additional SSH public key file"
  type        = string
  default     = ""
}

variable "ami_id" {
  description = "AMI ID to use for instances in this region"
  type        = string
  default     = ""
}

variable "os_type" {
  description = "Operating system type (amazon-linux or ubuntu)"
  type        = string
  default     = "amazon-linux"

  validation {
    condition     = contains(["amazon-linux", "ubuntu"], var.os_type)
    error_message = "The os_type must be either 'amazon-linux' or 'ubuntu'."
  }
}
