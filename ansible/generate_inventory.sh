#!/bin/bash
# generate_inventory.sh
# Run this from the ansible/ directory

set -e

echo "Generating Ansible inventory from Terraform output..."

# Check if terraform is available
if ! command -v terraform &> /dev/null; then
    echo "Error: terraform command not found"
    exit 1
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "Error: jq command not found. Please install jq."
    exit 1
fi

# Check if terraform directory exists
if [ ! -d "../terraform" ]; then
    echo "Error: terraform directory not found. Make sure you're running this from the ansible/ directory"
    exit 1
fi

# Get terraform output from terraform directory
echo "Getting Terraform output..."
cd ../terraform
terraform output -json instances > ../ansible/instances.json
cd ../ansible

# Check if output exists
if [ ! -s instances.json ]; then
    echo "Error: No terraform output found or output is empty"
    exit 1
fi

# Generate inventory file header
echo "Creating inventory.ini..."
cat > inventory.ini << 'EOF'
[ec2_instances]
EOF

# Parse JSON and append to inventory
jq -r '.[] | "\(.name) ansible_host=\(.public_ip) ansible_user=ec2-user"' instances.json >> inventory.ini

# Add group variables
cat >>inventory.ini <<'EOF'

[ec2_instances:vars]
ansible_ssh_private_key_file=~/.ssh/id_ed25519.pub
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
jwt_secret=f79ae8046bc11c9927afe911db7143c51a806c4a537cc08e0d37140b0192f430
EOF

# Clean up
rm instances.json

echo "Inventory file generated successfully!"
echo "Contents of inventory.ini:"
echo "=========================="
cat inventory.ini
echo "=========================="
echo ""
echo "To use this inventory:"
echo "1. Update the SSH key path in inventory.ini"
echo "2. Update the JWT secret if needed"
echo "3. Run: ansible-playbook -i inventory.ini deploy-docker.yml"
