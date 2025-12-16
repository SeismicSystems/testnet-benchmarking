#!/bin/bash
# generate_inventory.sh
# Run this from the ansible/ directory

set -e

TERRAFORM_DIR="../terraform"

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

# Get current Terraform workspace
cd "$TERRAFORM_DIR"
WORKSPACE=$(terraform workspace show)
echo "Detected Terraform workspace: $WORKSPACE"

# Set output file based on workspace
if [[ "$WORKSPACE" == "default" ]]; then
  OUTPUT_FILE="../ansible/inventory.ini"
else
  OUTPUT_FILE="../ansible/inventory_${WORKSPACE}.ini"
fi

# Get terraform output from terraform directory
echo "Getting Terraform output..."
terraform output -json instances >"$OUTPUT_FILE.tmp"
cd ../ansible

# Check if output exists
if [ ! -s "$OUTPUT_FILE.tmp" ]; then
  echo "Error: No terraform output found or output is empty"
  rm -f "$OUTPUT_FILE.tmp"
  exit 1
fi

# Generate inventory file header
echo "Creating $OUTPUT_FILE..."
cat >"$OUTPUT_FILE" <<'EOF'
[ec2_instances]
EOF

# Parse JSON and append to inventory
jq -r '.[] | "\(.name) ansible_host=\(.public_ip) ansible_user=ubuntu"' "$OUTPUT_FILE.tmp" >>"$OUTPUT_FILE"

# Add group variables
cat >>"$OUTPUT_FILE" <<'EOF'

[ec2_instances:vars]
ansible_ssh_private_key_file=~/.ssh/id_ed25519
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
ansible_python_interpreter=auto_silent
jwt_secret=f79ae8046bc11c9927afe911db7143c51a806c4a537cc08e0d37140b0192f430
EOF

# Clean up
rm -f "$OUTPUT_FILE.tmp"

echo "Inventory file generated successfully for workspace: $WORKSPACE"
echo "Contents of $OUTPUT_FILE:"
echo "=========================="
cat "$OUTPUT_FILE"
echo "=========================="
echo ""
echo "To use this inventory:"
echo "1. Update the SSH key path in $OUTPUT_FILE if needed"
echo "2. Update the JWT secret if needed"
echo "3. Run: ansible-playbook -i $OUTPUT_FILE <playbook>.yml"
