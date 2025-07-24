#!/bin/bash

# Generate prometheus.yml from ansible inventory
# This script reads IP addresses from inventory.ini and creates a prometheus configuration

set -e # Exit on any error

echo "🔧 Generating prometheus.yml from inventory..."

# Check if inventory files exist
if [ ! -f "ansible/inventory.ini" ]; then
  echo "❌ Error: ansible/inventory.ini not found"
  exit 1
fi

if [ ! -f "ansible/inventory_spamnet.ini" ]; then
  echo "❌ Error: ansible/inventory_spamnet.ini not found"
  exit 1
fi

# Extract IP addresses from both inventory files
echo "📥 Reading IP addresses from inventory.ini..."
ips_regular=$(grep "ansible_host=" ansible/inventory.ini | sed 's/.*ansible_host=\([^[:space:]]*\).*/\1/')

echo "📥 Reading IP addresses from inventory_spamnet.ini..."
ips_spamnet=$(grep "ansible_host=" ansible/inventory_spamnet.ini | sed 's/.*ansible_host=\([^[:space:]]*\).*/\1/')

# Combine both sets of IPs
ips="$ips_regular $ips_spamnet"

# Create prometheus.yml
echo "📝 Creating prometheus.yml..."

cat >prometheus.yml <<'EOF'
# my global config
global:
  scrape_interval: 15s # Set the scrape interval to every 15 seconds. Default is every 1 minute.
  evaluation_interval: 15s # Evaluate rules every 15 seconds. The default is every 1 minute.
  # scrape_timeout is set to the global default (10s).

# Alertmanager configuration
alerting:
  alertmanagers:
    - static_configs:
        - targets:
          # - alertmanager:9093

# Load rules once and periodically evaluate them according to the global 'evaluation_interval'.
rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"

# A scrape configuration containing exactly one endpoint to scrape:
scrape_configs:
  - job_name: "network"
    static_configs:
      - targets:
EOF

# Add regular cluster IPs
for ip in $ips_regular; do
  echo "          - \"$ip:9090\"" >>prometheus.yml
done

cat >>prometheus.yml <<'EOF'
        labels:
          cluster: "regular"
          
  - job_name: "tx-sender"
    honor_labels: true
    scrape_protocols: ["PrometheusText0.0.4"]
    static_configs:
      - targets:
EOF

# Add spamnet cluster IPs
for ip in $ips_spamnet; do
  echo "          - \"$ip:9090\"" >>prometheus.yml
done

cat >>prometheus.yml <<'EOF'
        labels:
          cluster: "spamnet"
EOF

echo "✅ Successfully generated prometheus.yml"
echo "📊 Added $(echo "$ips" | wc -w) targets to prometheus configuration"

# Show the generated file
echo "📋 Generated prometheus.yml:"
echo "----------------------------------------"
cat prometheus.yml
echo "----------------------------------------"

