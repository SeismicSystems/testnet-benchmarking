# Regions configuration with Tokyo for Asia coverage
#regions = ["us-west-1", "us-west-2", "us-east-1", "us-east-2"]
regions = ["us-west-2", "eu-central-1", "us-east-1", "ap-northeast-1", "sa-east-1"]
instances_per_region = 1

# Optional: Override defaults
instance_type = "m5.xlarge"
volume_size = 200
ssh_public_key_path = "~/.ssh/id_ed25519.pub"
