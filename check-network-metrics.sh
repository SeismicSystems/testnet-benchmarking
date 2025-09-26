#!/bin/bash

# Script to check CloudWatch network metrics for EC2 instances
# Usage: ./check-network-metrics.sh [--instance INDEX] [--start-time TIME] [--end-time TIME]

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --instance INDEX       Query specific instance by index (0-based), omit for all instances"
    echo "  --start-time TIME      Start time in UTC format (e.g., 2025-09-25T07:00:00Z)"
    echo "  --end-time TIME        End time in UTC format (e.g., 2025-09-25T08:00:00Z)"
    echo "  --instance-type TYPE   Instance type for limit calculations (default: m5.xlarge)"
    echo "  --help                 Show this help message"
    echo ""
    echo "If --start-time and --end-time are not provided, defaults to last 1 hour"
    echo "TIME format: YYYY-MM-DDTHH:MM:SSZ (UTC)"
    exit 1
}

# Function to convert bytes to human readable format
human_readable() {
    local bytes=$1
    local period_seconds=300  # 5 minutes
    
    # Convert to bits per second
    local bps=$(echo "scale=2; $bytes * 8 / $period_seconds" | bc -l)
    
    if (( $(echo "$bps >= 1000000000" | bc -l) )); then
        echo "$(echo "scale=2; $bps / 1000000000" | bc -l) Gbps"
    elif (( $(echo "$bps >= 1000000" | bc -l) )); then
        echo "$(echo "scale=2; $bps / 1000000" | bc -l) Mbps"
    elif (( $(echo "$bps >= 1000" | bc -l) )); then
        echo "$(echo "scale=2; $bps / 1000" | bc -l) Kbps"
    else
        echo "$(echo "scale=2; $bps" | bc -l) bps"
    fi
}

# Function to format IOPS
format_iops() {
    local ops=$1
    local period_seconds=300  # 5 minutes
    
    # Convert to operations per second
    local ops_per_sec=$(echo "scale=1; $ops / $period_seconds" | bc -l)
    
    if (( $(echo "$ops_per_sec >= 1000" | bc -l) )); then
        echo "$(echo "scale=1; $ops_per_sec / 1000" | bc -l)K IOPS"
    else
        echo "$(echo "scale=1; $ops_per_sec" | bc -l) IOPS"
    fi
}

# Function to format throughput (bytes to MB/s)
format_throughput() {
    local bytes=$1
    local period_seconds=300  # 5 minutes
    
    # Convert to MB per second
    local mbps=$(echo "scale=2; $bytes / $period_seconds / 1048576" | bc -l)
    
    if (( $(echo "$mbps >= 1000" | bc -l) )); then
        echo "$(echo "scale=2; $mbps / 1000" | bc -l) GB/s"
    else
        echo "$(echo "scale=1; $mbps" | bc -l) MB/s"
    fi
}

# Function to get max value from CloudWatch data
get_max_value() {
    local json_data="$1"
    local value=$(echo "$json_data" | jq -r '.Datapoints | map(.Maximum // .Average) | max // 0')
    # Handle null/empty values
    if [[ "$value" == "null" ]] || [[ -z "$value" ]] || [[ "$value" == "" ]]; then
        echo "0"
    else
        echo "$value"
    fi
}

# Function to get instance type limits from AWS
get_instance_limits() {
    local instance_type="$1"
    
    echo "Getting limits for $instance_type..." >&2
    
    local limits_json
    limits_json=$(aws ec2 describe-instance-types --instance-types "$instance_type" --query 'InstanceTypes[0].[NetworkInfo.NetworkPerformance,EbsInfo.EbsOptimizedInfo.MaximumIops,EbsInfo.EbsOptimizedInfo.MaximumThroughputInMBps]' --output json 2>/dev/null)
    
    if [[ $? -ne 0 ]] || [[ -z "$limits_json" ]]; then
        echo "Warning: Could not get limits for $instance_type, using defaults" >&2
        echo "Up to 10 Gigabit|4000|593.75"
        return
    fi
    
    local network_perf=$(echo "$limits_json" | jq -r '.[0] // "Up to 10 Gigabit"')
    local max_iops=$(echo "$limits_json" | jq -r '.[1] // 4000')
    local max_throughput_mbps=$(echo "$limits_json" | jq -r '.[2] // 593.75')
    
    echo "$network_perf|$max_iops|$max_throughput_mbps"
}

# Function to parse network performance string to baseline Gbps
parse_network_performance() {
    local network_perf="$1"
    
    # Parse various AWS network performance descriptions
    case "$network_perf" in
        *"25 Gigabit"*) echo "3125000000" ;;  # 25 Gbps baseline (25 * 1000^3 / 8)
        *"10 Gigabit"*) echo "1250000000" ;;  # 10 Gbps baseline (assume 10% baseline)
        *"5 Gigabit"*) echo "625000000" ;;    # 5 Gbps
        *"Up to 10"*) echo "1250000000" ;;    # Up to 10 Gbps (assume ~10% baseline)
        *"Up to 25"*) echo "3125000000" ;;    # Up to 25 Gbps
        *"High"*) echo "1250000000" ;;        # High = ~10 Gbps
        *"Moderate"*) echo "125000000" ;;     # Moderate = ~1 Gbps
        *"Low"*) echo "62500000" ;;           # Low = ~500 Mbps
        *) echo "1250000000" ;;               # Default fallback
    esac
}

# Parse command line arguments
INSTANCE_INDEX=""
START_TIME=""
END_TIME=""
INSTANCE_TYPE="m5.xlarge"

while [[ $# -gt 0 ]]; do
    case $1 in
        --instance)
            INSTANCE_INDEX="$2"
            shift 2
            ;;
        --start-time)
            START_TIME="$2"
            shift 2
            ;;
        --end-time)
            END_TIME="$2"
            shift 2
            ;;
        --instance-type)
            INSTANCE_TYPE="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Check if required tools are installed
for cmd in jq bc aws; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd is required but not installed"
        exit 1
    fi
done

# Set default times if not provided (last 1 hour)
if [[ -z "$START_TIME" ]]; then
    START_TIME=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)
fi

if [[ -z "$END_TIME" ]]; then
    END_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
fi

echo "Querying CloudWatch metrics from $START_TIME to $END_TIME"
echo "Period: 300 seconds (5 minutes)"
echo "Instance type: $INSTANCE_TYPE"
echo ""

# Get instance type limits
LIMITS=$(get_instance_limits "$INSTANCE_TYPE")
IFS='|' read -r NETWORK_PERF MAX_IOPS MAX_THROUGHPUT_MBPS <<< "$LIMITS"
BASELINE_BPS=$(parse_network_performance "$NETWORK_PERF")

echo ""

# Get terraform output
echo "Getting instance information from terraform..."

# Change to terraform directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
cd "$SCRIPT_DIR/terraform" || {
    echo "Error: Could not change to terraform directory at $SCRIPT_DIR/terraform"
    exit 1
}

TERRAFORM_OUTPUT=$(terraform output -json 2>/dev/null)

if [[ $? -ne 0 ]] || [[ -z "$TERRAFORM_OUTPUT" ]]; then
    echo "Error: Could not get terraform output. Make sure you're in the terraform directory and terraform has been applied."
    exit 1
fi

# Parse instances from terraform output
INSTANCES=$(echo "$TERRAFORM_OUTPUT" | jq -r '
    .instances.value[] |
    "\(.instance_id)|\(.public_ip)|\(.region | gsub("[abc]$"; ""))"
')

if [[ -z "$INSTANCES" ]]; then
    echo "Error: No instances found in terraform output"
    exit 1
fi

# Convert to array for indexing
readarray -t INSTANCE_ARRAY <<< "$INSTANCES"

# Determine which instances to query
if [[ -n "$INSTANCE_INDEX" ]]; then
    if [[ ! "$INSTANCE_INDEX" =~ ^[0-9]+$ ]] || [[ "$INSTANCE_INDEX" -ge "${#INSTANCE_ARRAY[@]}" ]]; then
        echo "Error: Invalid instance index. Valid range: 0-$((${#INSTANCE_ARRAY[@]}-1))"
        exit 1
    fi
    INSTANCES_TO_QUERY=("${INSTANCE_ARRAY[$INSTANCE_INDEX]}")
    echo "Querying instance at index $INSTANCE_INDEX"
else
    INSTANCES_TO_QUERY=("${INSTANCE_ARRAY[@]}")
    echo "Querying all ${#INSTANCE_ARRAY[@]} instances"
fi

echo ""
echo "Instance Limits ($INSTANCE_TYPE):"
echo "  Network: $NETWORK_PERF"
echo "  EBS: Up to $MAX_IOPS IOPS, up to $MAX_THROUGHPUT_MBPS MB/s throughput"
echo "========================================================================="

# Query each instance
for i in "${!INSTANCES_TO_QUERY[@]}"; do
    INSTANCE_INFO="${INSTANCES_TO_QUERY[$i]}"
    IFS='|' read -r INSTANCE_ID PUBLIC_IP REGION <<< "$INSTANCE_INFO"
    
    if [[ -n "$INSTANCE_INDEX" ]]; then
        echo "Instance $INSTANCE_INDEX: $INSTANCE_ID ($PUBLIC_IP) in $REGION"
    else
        echo "Instance $i: $INSTANCE_ID ($PUBLIC_IP) in $REGION"
    fi
    echo "----------------------------------------"
    
    # Query NetworkIn
    NETWORK_IN=$(aws cloudwatch get-metric-statistics \
        --region "$REGION" \
        --namespace AWS/EC2 \
        --metric-name NetworkIn \
        --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period 300 \
        --statistics Maximum \
        2>/dev/null)
    
    # Query NetworkOut
    NETWORK_OUT=$(aws cloudwatch get-metric-statistics \
        --region "$REGION" \
        --namespace AWS/EC2 \
        --metric-name NetworkOut \
        --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period 300 \
        --statistics Maximum \
        2>/dev/null)
    
    # Query EBS Read IOPS
    EBS_READ_OPS=$(aws cloudwatch get-metric-statistics \
        --region "$REGION" \
        --namespace AWS/EC2 \
        --metric-name EBSReadOps \
        --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period 300 \
        --statistics Maximum \
        2>/dev/null)
    
    # Query EBS Write IOPS
    EBS_WRITE_OPS=$(aws cloudwatch get-metric-statistics \
        --region "$REGION" \
        --namespace AWS/EC2 \
        --metric-name EBSWriteOps \
        --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period 300 \
        --statistics Maximum \
        2>/dev/null)
    
    # Query EBS Read Throughput
    EBS_READ_BYTES=$(aws cloudwatch get-metric-statistics \
        --region "$REGION" \
        --namespace AWS/EC2 \
        --metric-name EBSReadBytes \
        --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period 300 \
        --statistics Maximum \
        2>/dev/null)
    
    # Query EBS Write Throughput
    EBS_WRITE_BYTES=$(aws cloudwatch get-metric-statistics \
        --region "$REGION" \
        --namespace AWS/EC2 \
        --metric-name EBSWriteBytes \
        --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period 300 \
        --statistics Maximum \
        2>/dev/null)
    
    # Parse results
    MAX_IN=$(get_max_value "$NETWORK_IN")
    MAX_OUT=$(get_max_value "$NETWORK_OUT")
    MAX_READ_OPS=$(get_max_value "$EBS_READ_OPS")
    MAX_WRITE_OPS=$(get_max_value "$EBS_WRITE_OPS")
    MAX_READ_BYTES=$(get_max_value "$EBS_READ_BYTES")
    MAX_WRITE_BYTES=$(get_max_value "$EBS_WRITE_BYTES")
    
    # Check if we have any data (with safe number handling)
    HAS_NETWORK_DATA=0
    HAS_EBS_DATA=0
    
    # Safely check network data
    if [[ "$MAX_IN" != "0" ]] || [[ "$MAX_OUT" != "0" ]]; then
        HAS_NETWORK_DATA=1
    fi
    
    # Safely check EBS data  
    if [[ "$MAX_READ_OPS" != "0" ]] || [[ "$MAX_WRITE_OPS" != "0" ]] || [[ "$MAX_READ_BYTES" != "0" ]] || [[ "$MAX_WRITE_BYTES" != "0" ]]; then
        HAS_EBS_DATA=1
    fi
    
    if [[ "$HAS_NETWORK_DATA" == "0" ]] && [[ "$HAS_EBS_DATA" == "0" ]]; then
        echo "  No data available for this time period"
    else
        # Network metrics
        if [[ "$HAS_NETWORK_DATA" == "1" ]]; then
            echo "  Network:"
            echo "    Peak NetworkIn:  $(human_readable $MAX_IN)"
            echo "    Peak NetworkOut: $(human_readable $MAX_OUT)"
            
            # Calculate network utilization percentage
            MAX_TOTAL=$(echo "scale=2; ($MAX_IN + $MAX_OUT) * 8 / 300" | bc -l)
            UTILIZATION=$(echo "scale=1; $MAX_TOTAL * 100 / $BASELINE_BPS" | bc -l)
            echo "    Network baseline utilization: ${UTILIZATION}%"
        fi
        
        # EBS metrics
        if [[ "$HAS_EBS_DATA" == "1" ]]; then
            echo "  EBS Storage:"
            if (( $(echo "$MAX_READ_OPS > 0" | bc -l) )); then
                echo "    Peak Read IOPS:  $(format_iops $MAX_READ_OPS)"
            fi
            if (( $(echo "$MAX_WRITE_OPS > 0" | bc -l) )); then
                echo "    Peak Write IOPS: $(format_iops $MAX_WRITE_OPS)"
            fi
            if (( $(echo "$MAX_READ_BYTES > 0" | bc -l) )); then
                echo "    Peak Read Throughput:  $(format_throughput $MAX_READ_BYTES)"
            fi
            if (( $(echo "$MAX_WRITE_BYTES > 0" | bc -l) )); then
                echo "    Peak Write Throughput: $(format_throughput $MAX_WRITE_BYTES)"
            fi
            
            # Calculate EBS utilization using dynamic limits
            TOTAL_IOPS=$(echo "scale=1; ($MAX_READ_OPS + $MAX_WRITE_OPS) / 300" | bc -l)
            TOTAL_THROUGHPUT=$(echo "scale=1; ($MAX_READ_BYTES + $MAX_WRITE_BYTES) / 300 / 1048576" | bc -l)
            
            if (( $(echo "$TOTAL_IOPS > 0" | bc -l) )); then
                IOPS_UTILIZATION=$(echo "scale=1; $TOTAL_IOPS * 100 / $MAX_IOPS" | bc -l)
                echo "    EBS IOPS utilization: ${IOPS_UTILIZATION}% (of $MAX_IOPS baseline)"
            fi
            if (( $(echo "$TOTAL_THROUGHPUT > 0" | bc -l) )); then
                THROUGHPUT_UTILIZATION=$(echo "scale=1; $TOTAL_THROUGHPUT * 100 / $MAX_THROUGHPUT_MBPS" | bc -l)
                echo "    EBS throughput utilization: ${THROUGHPUT_UTILIZATION}% (of $MAX_THROUGHPUT_MBPS MB/s baseline)"
            fi
        fi
    fi
    
    echo ""
done

echo "Note: Peak values are maximum over any 5-minute window in the time range"
echo "Network: Baseline utilization shows peak usage vs estimated baseline (>100% uses burst capacity)"
echo "EBS: Utilization shown vs instance limits. Volume limits may be lower (e.g., gp3: 3000 IOPS baseline)"