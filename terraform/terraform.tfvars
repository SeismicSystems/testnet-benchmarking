# Regions configuration with Tokyo for Asia coverage
#regions = ["us-west-1", "us-west-2", "us-east-1", "us-east-2"]
regions = ["us-west-2", "eu-central-1", "us-east-1", "ap-northeast-1", "sa-east-1"]
instances_per_region = 1

# Optional: Override defaults
instance_type = "m5.xlarge"
#instance_type = "m5.8xlarge"
volume_size = 4000
ssh_public_key_path = "~/.ssh/id_ed25519.pub"
additional_ssh_public_key_path = "~/.ssh/dalton_id25519.pub"

# AMI IDs for each region (leave empty to use latest Amazon Linux 2)
ami_us_west_2 = ""
ami_eu_central_1 = ""
ami_us_east_1 = ""
ami_ap_northeast_1 = ""
ami_sa_east_1 = ""
