#!/bin/bash
# generate_inventory.sh
# Run this from the ansible/ directory

set -e

# Check for spamnet argument
SPAMNET_MODE=false
TERRAFORM_DIR="../terraform"
OUTPUT_FILE="inventory.ini"

if [[ "$1" == "spamnet" ]]; then
  SPAMNET_MODE=true
  TERRAFORM_DIR="../terraform-spamnet"
  OUTPUT_FILE="inventory_spamnet.ini"
fi

echo "Generating Ansible inventory from Terraform output..."

# Check if terraform is available
if ! command -v terraform &>/dev/null; then
  echo "Error: terraform command not found"
  exit 1
fi

# Check if jq is available
if ! command -v jq &>/dev/null; then
  echo "Error: jq command not found. Please install jq."
  exit 1
fi

# Check if terraform directory exists
if [ ! -d "$TERRAFORM_DIR" ]; then
  echo "Error: terraform directory not found at $TERRAFORM_DIR. Make sure you're running this from the ansible/ directory"
  exit 1
fi

# Get terraform output from terraform directory
echo "Getting Terraform output..."
cd "$TERRAFORM_DIR"
terraform output -json instances >../ansible/instances.json
cd ../ansible

# Check if output exists
if [ ! -s instances.json ]; then
  echo "Error: No terraform output found or output is empty"
  exit 1
fi

# Generate inventory file header
echo "Creating $OUTPUT_FILE..."
cat >"$OUTPUT_FILE" <<'EOF'
[ec2_instances]
EOF

# Parse JSON and append to inventory
jq -r '.[] | "\(.name) ansible_host=\(.public_ip) ansible_user=ubuntu"' instances.json >>"$OUTPUT_FILE"

# Add group variables
cat >>"$OUTPUT_FILE" <<'EOF'

[ec2_instances:vars]
ansible_ssh_private_key_file=~/.ssh/id_ed25519
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
ansible_python_interpreter=/usr/bin/python3.8
jwt_secret=f79ae8046bc11c9927afe911db7143c51a806c4a537cc08e0d37140b0192f430
EOF

# Clean up
rm instances.json

echo "Inventory file generated successfully!"
echo "Contents of $OUTPUT_FILE:"
echo "=========================="
cat "$OUTPUT_FILE"
echo "=========================="
echo ""
echo "To use this inventory:"
echo "1. Update the SSH key path in $OUTPUT_FILE"
echo "2. Update the JWT secret if needed"
echo "3. Run: ansible-playbook -i $OUTPUT_FILE deploy-docker.yml"
