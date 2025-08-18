variable "regions" {
  description = "List of AWS regions to deploy to"
  type        = list(string)
  default     = ["us-west-2"]
}

variable "instances_per_region" {
  description = "Number of instances to create per region"
  type        = number
  default     = 1
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

variable "ami_us_west_2" {
  description = "AMI ID for us-west-2 region"
  type        = string
  default     = ""
}

variable "ami_eu_central_1" {
  description = "AMI ID for eu-central-1 region"
  type        = string
  default     = ""
}

variable "ami_us_east_1" {
  description = "AMI ID for us-east-1 region"
  type        = string
  default     = ""
}

variable "ami_ap_northeast_1" {
  description = "AMI ID for ap-northeast-1 region"
  type        = string
  default     = ""
}

variable "ami_sa_east_1" {
  description = "AMI ID for sa-east-1 region"
  type        = string
  default     = ""
}

