#!/bin/bash

# Generate prometheus.yml from ansible inventory
# This script reads IP addresses from inventory.ini and creates a prometheus configuration

set -e # Exit on any error

echo "🔧 Generating prometheus.yml from inventory..."

# Check if inventory file exists
if [ ! -f "ansible/inventory.ini" ]; then
  echo "❌ Error: ansible/inventory.ini not found"
  exit 1
fi

# Extract IP addresses from inventory file
echo "📥 Reading IP addresses from inventory.ini..."
ips=$(grep "ansible_host=" ansible/inventory.ini | sed 's/.*ansible_host=\([^[:space:]]*\).*/\1/')

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

# Add network metrics targets (port 9090)
for ip in $ips; do
  echo "          - \"$ip:9090\"" >>prometheus.yml
done

cat >>prometheus.yml <<'EOF'
        labels:
          service: "network"
          
  - job_name: "tx-sender"
    honor_labels: true
    scrape_protocols: ["PrometheusText0.0.4"]
    static_configs:
      - targets:
EOF

# Add tx-sender metrics targets (port 9092)
for ip in $ips; do
  echo "          - \"$ip:9092\"" >>prometheus.yml
done

cat >>prometheus.yml <<'EOF'
        labels:
          service: "tx-sender"
EOF

echo "✅ Successfully generated prometheus.yml"
echo "📊 Added $(echo "$ips" | wc -w) targets to prometheus configuration"

# Show the generated file
echo "📋 Generated prometheus.yml:"
echo "----------------------------------------"
cat prometheus.yml
echo "----------------------------------------"

