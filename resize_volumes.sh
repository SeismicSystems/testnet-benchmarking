#!/bin/bash

# Read from the file
INSTANCES_FILE="instances.json"

# Loop through each instance object
jq -c '.[]' "$INSTANCES_FILE" | while read -r instance; do
  INSTANCE_ID=$(echo "$instance" | jq -r '.instance_id')
  VOLUME_ID=$(echo "$instance" | jq -r '.volume_id')
  PUBLIC_IP=$(echo "$instance" | jq -r '.public_ip')
  REGION=$(echo "$instance" | jq -r '.region')

  echo "Processing instance: $INSTANCE_ID in $REGION"
  echo "Volume ID: $VOLUME_ID | Public IP: $PUBLIC_IP"

  AWS_PAGER="" aws ec2 modify-volume \
    --volume-id "${VOLUME_ID}" \
    --region "${REGION:0:-1}" \
    --volume-type io1 \
    --iops 12000 \
    --size 256
  echo "-----------------------------"
done
