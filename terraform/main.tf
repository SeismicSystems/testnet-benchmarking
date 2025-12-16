terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Providers for each region
provider "aws" {
  alias  = "us_west_2"
  region = "us-west-2"
}

provider "aws" {
  alias  = "eu_central_1"
  region = "eu-central-1"
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "ap_southeast_1"
  region = "ap-southeast-1"
}

provider "aws" {
  alias  = "sa_east_1"
  region = "sa-east-1"
}

# Deploy to us-west-2
module "us_west_2" {
  count  = contains(var.regions, "us-west-2") ? 1 : 0
  source = "./modules/regional-deployment"
  
  providers = {
    aws = aws.us_west_2
  }
  
  region                        = "us-west-2"
  instances_per_region          = var.instances_per_region
  instance_type                 = var.instance_type
  volume_size                   = var.volume_size
  ssh_public_key_path           = var.ssh_public_key_path
  additional_ssh_public_key_path = var.additional_ssh_public_key_path
  ami_id                        = var.ami_us_west_2
  os_type                       = var.os_type
}

# Deploy to eu-central-1
module "eu_central_1" {
  count  = contains(var.regions, "eu-central-1") ? 1 : 0
  source = "./modules/regional-deployment"
  
  providers = {
    aws = aws.eu_central_1
  }
  
  region                        = "eu-central-1"
  instances_per_region          = var.instances_per_region
  instance_type                 = var.instance_type
  volume_size                   = var.volume_size
  ssh_public_key_path           = var.ssh_public_key_path
  additional_ssh_public_key_path = var.additional_ssh_public_key_path
  ami_id                        = var.ami_eu_central_1
  os_type                       = var.os_type
}

# Deploy to us-east-1
module "us_east_1" {
  count  = contains(var.regions, "us-east-1") ? 1 : 0
  source = "./modules/regional-deployment"
  
  providers = {
    aws = aws.us_east_1
  }
  
  region                        = "us-east-1"
  instances_per_region          = var.instances_per_region
  instance_type                 = var.instance_type
  volume_size                   = var.volume_size
  ssh_public_key_path           = var.ssh_public_key_path
  additional_ssh_public_key_path = var.additional_ssh_public_key_path
  ami_id                        = var.ami_us_east_1
  os_type                       = var.os_type
}

# Deploy to ap-southeast-1
module "ap_southeast_1" {
  count  = contains(var.regions, "ap-southeast-1") ? 1 : 0
  source = "./modules/regional-deployment"

  providers = {
    aws = aws.ap_southeast_1
  }

  region                        = "ap-southeast-1"
  instances_per_region          = var.instances_per_region
  instance_type                 = var.instance_type
  volume_size                   = var.volume_size
  ssh_public_key_path           = var.ssh_public_key_path
  additional_ssh_public_key_path = var.additional_ssh_public_key_path
  ami_id                        = var.ami_ap_southeast_1
  os_type                       = var.os_type
}

# Deploy to sa-east-1
module "sa_east_1" {
  count  = contains(var.regions, "sa-east-1") ? 1 : 0
  source = "./modules/regional-deployment"
  
  providers = {
    aws = aws.sa_east_1
  }
  
  region                        = "sa-east-1"
  instances_per_region          = var.instances_per_region
  instance_type                 = var.instance_type
  volume_size                   = var.volume_size
  ssh_public_key_path           = var.ssh_public_key_path
  additional_ssh_public_key_path = var.additional_ssh_public_key_path
  ami_id                        = var.ami_sa_east_1
  os_type                       = var.os_type
}
