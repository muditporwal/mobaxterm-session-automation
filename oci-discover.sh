#!/usr/bin/env bash

# OCI Instance Discovery with Private IP Resolution
# This script discovers OCI instances and retrieves their private IP addresses
# by querying VNIC attachments and VNIC details
# Supports multiple filters to create separate CSV files
#
# Usage: ./oci-discover.sh <compartment_id> <region> [filter1] [filter2] ...
# Example: ./oci-discover.sh "ocid1.compartment.oc1..aaa" "ap-singapore-2" "web.*" ".*db.*"

AUTH_METHOD="instance_principal"

# Function to show usage
show_usage() {
    echo "Usage: $0 <compartment_id> <region> [filter1] [filter2] ..."
    echo ""
    echo "Arguments:"
    echo "  compartment_id  - OCI Compartment OCID"
    echo "  region         - OCI Region (e.g., ap-singapore-2)"
    echo "  filter1...     - Optional regex patterns to filter instance names"
    echo ""
    echo "Examples:"
    echo "  $0 'ocid1.compartment.oc1..aaa' 'ap-singapore-2'"
    echo "  $0 'ocid1.compartment.oc1..aaa' 'ap-singapore-2' 'web.*' '.*db.*'"
    echo "  $0 'ocid1.compartment.oc1..aaa' 'us-east-1' '^prod-.*' '^test-.*'"
    echo ""
    echo "Note: If no filters provided, will discover all instances -> all_instances.csv"
    exit 1
}

# Check minimum required arguments
if [[ $# -lt 2 ]]; then
    echo "OCI Instance Discovery - Interactive Mode"
    echo "========================================"
    echo "No command-line arguments provided. Starting interactive input..."
    echo
    
    # Interactive input for compartment OCID
    while true; do
        read -p "Enter OCI Compartment OCID: " COMPARTMENT_OCID
        if [[ -n "$COMPARTMENT_OCID" ]]; then
            # Basic validation
            if [[ "$COMPARTMENT_OCID" =~ ^ocid1\.compartment\.oc1\. ]]; then
                break
            else
                echo "Warning: OCID format looks unusual. Continue anyway? (y/n): "
                read -r confirm
                if [[ "$confirm" =~ ^[Yy] ]]; then
                    break
                fi
            fi
        else
            echo "Compartment OCID cannot be empty. Please try again."
        fi
    done
    
    # Interactive input for region
    while true; do
        echo "Common OCI regions:"
        echo "  - ap-singapore-2 (Singapore West)"
        echo "  - ap-singapore-1 (Singapore)"
        read -p "Enter OCI Region: " REGION
        if [[ -n "$REGION" ]]; then
            break
        else
            echo "Region cannot be empty. Please try again."
        fi
    done
    
    # Interactive input for filters
    echo
    echo "Instance Name Filters (this will filter the instances):"
    echo "Examples:"
    echo "  - acc"
    echo "  - ac2"
    echo "  - glb"
    echo "  - prd"
    echo
    
    FILTERS=()
    while true; do
        if [[ ${#FILTERS[@]} -eq 0 ]]; then
            read -p "Enter filter pattern (or press Enter for all instances): " filter_input
            if [[ -z "$filter_input" ]]; then
                FILTERS=(".*")
                break
            else
                FILTERS+=("$filter_input")
            fi
        else
            read -p "Enter another filter pattern (or press Enter to continue): " filter_input
            if [[ -z "$filter_input" ]]; then
                break
            else
                FILTERS+=("$filter_input")
            fi
        fi
    done
    
    echo
    echo "Configuration Summary:"
    echo "  Compartment: $COMPARTMENT_OCID"
    echo "  Region: $REGION"
    echo "  Filters: ${FILTERS[*]}"
    echo
    read -p "Proceed with discovery? (y/n): " proceed
    if [[ ! "$proceed" =~ ^[Yy] ]]; then
        echo "Discovery cancelled."
        exit 0
    fi
    echo
else
    # Parse command-line arguments
    COMPARTMENT_OCID="$1"
    REGION="$2"
    shift 2  # Remove first two arguments
    
    # Remaining arguments are filters
    if [[ $# -eq 0 ]]; then
        FILTERS=(".*")  # Default: match all instances
    else
        FILTERS=("$@")  # Use provided filters
    fi
fi

# Function to sanitize filter name for filename
sanitize_filename() {
    local filter="$1"
    # Handle special cases first
    if [[ "$filter" == ".*" ]]; then
        echo "all_instances"
        return
    fi
    
    # More comprehensive sanitization for special characters
    local sanitized="$filter"
    
    # Replace common regex patterns with readable names
    sanitized=$(echo "$sanitized" | sed 's/\.\*/wildcard/g')
    sanitized=$(echo "$sanitized" | sed 's/\^/start_/g')
    sanitized=$(echo "$sanitized" | sed 's/\$/end/g')
    sanitized=$(echo "$sanitized" | sed 's/\[/bracket_/g')
    sanitized=$(echo "$sanitized" | sed 's/\]/bracket/g')
    sanitized=$(echo "$sanitized" | sed 's/(/paren_/g')
    sanitized=$(echo "$sanitized" | sed 's/)/paren/g')
    sanitized=$(echo "$sanitized" | sed 's/|/or/g')
    sanitized=$(echo "$sanitized" | sed 's/+/plus/g')
    sanitized=$(echo "$sanitized" | sed 's/?/question/g')
    sanitized=$(echo "$sanitized" | sed 's/{/brace_/g')
    sanitized=$(echo "$sanitized" | sed 's/}/brace/g')
    sanitized=$(echo "$sanitized" | sed 's/\\/backslash/g')
    
    # Replace any remaining special characters with underscores
    sanitized=$(echo "$sanitized" | sed 's/[^a-zA-Z0-9_-]/_/g')
    
    # Clean up multiple underscores and trim
    sanitized=$(echo "$sanitized" | sed 's/__*/_/g' | sed 's/^_\|_$//g')
    
    # Ensure we have a valid filename (fallback if empty)
    if [[ -z "$sanitized" ]]; then
        sanitized="filter_$(date +%s)"
    fi
    
    echo "$sanitized"
}

# Function to get private IP for an instance
get_instance_private_ip() {
    local instance_id="$1"
    local instance_name="$2"
    
    # Get VNIC attachment for the instance
    local vnic_id=$(oci compute vnic-attachment list \
        --auth "$AUTH_METHOD" \
        --compartment-id "$COMPARTMENT_OCID" \
        --region "$REGION" \
        --instance-id "$instance_id" \
        --query 'data[0]."vnic-id"' \
        --raw-output 2>/dev/null)
    
    if [[ -n "$vnic_id" && "$vnic_id" != "null" ]]; then
        # Get VNIC details to retrieve private IP
        local private_ip=$(oci network vnic get \
            --auth "$AUTH_METHOD" \
            --vnic-id "$vnic_id" \
            --region "$REGION" \
            --query 'data."private-ip"' \
            --raw-output 2>/dev/null)
        
        if [[ -n "$private_ip" && "$private_ip" != "null" ]]; then
            echo "$private_ip"
        else
            echo "NO_IP"
        fi
    else
        echo "NO_VNIC"
    fi
}

# Function to process a single filter
process_filter() {
    local filter="$1"
    local output_file="$2"
    local instances_json="$3"
    
    echo "Processing filter: '$filter' -> $output_file" >&2
    
    # Remove existing file if it exists (overwrite)
    if [[ -f "$output_file" ]]; then
        echo "  Overwriting existing file: $output_file" >&2
        rm -f "$output_file"
    fi
    
    # Filter instances by name pattern
    filtered_instances=$(echo "$instances_json" | jq -r '.[] | "\(.id)|\(.name)"' | grep -E "$filter")
    filter_exit_code=$?
    
    if [[ $filter_exit_code -gt 1 ]]; then
        echo "Error: Filter '$filter' failed with exit code: $filter_exit_code" >&2
        return 1
    fi
    
    if [[ -z "$filtered_instances" ]]; then
        echo "  Warning: No instances matching pattern '$filter' found." >&2
        # Create empty file with header
        echo "Name,PrivateIP,User,Port" > "$output_file"
        echo "  Created empty file: $output_file" >&2
        return 0
    fi
    
    filtered_count=$(echo "$filtered_instances" | wc -l)
    echo "  Found $filtered_count instances for filter '$filter', resolving IPs..." >&2
    
    # Create CSV file with header
    echo "Name,PrivateIP,User,Port" > "$output_file"
    
    # Process each filtered instance
    echo "$filtered_instances" | while IFS='|' read -r instance_id instance_name; do
        if [[ -n "$instance_id" && -n "$instance_name" ]]; then
            echo -n "    Processing: $instance_name ... " >&2
            private_ip=$(get_instance_private_ip "$instance_id" "$instance_name")
            echo "IP: $private_ip" >&2
            
            # Append to CSV file
            if [[ "$private_ip" != "NO_IP" && "$private_ip" != "NO_VNIC" ]]; then
                echo "\"$instance_name\",\"$private_ip\",\"opc\",\"22\"" >> "$output_file"
            else
                echo "\"$instance_name\",\"ERROR: $private_ip\",\"opc\",\"22\"" >> "$output_file"
            fi
        fi
    done
    
    echo "  ✅ Created: $output_file" >&2
}

echo "OCI Instance Discovery with IP Resolution"
echo "========================================"
echo "Compartment: $COMPARTMENT_OCID"
echo "Region: $REGION"
echo "Filters: ${FILTERS[*]}"
echo "Output: Multiple CSV files (overwrite existing)"
echo

# Validate compartment OCID format
if [[ ! "$COMPARTMENT_OCID" =~ ^ocid1\.compartment\.oc1\. ]]; then
    echo "Warning: Compartment ID format doesn't match expected pattern (ocid1.compartment.oc1.)"
    echo "Continuing anyway..."
fi

# Get all running instances once
echo "Discovering running instances..."
instances_json=$(oci compute instance list \
    --auth "$AUTH_METHOD" \
    --compartment-id "$COMPARTMENT_OCID" \
    --region "$REGION" \
    --all \
    --lifecycle-state RUNNING \
    --query 'data[].{id:id, name:"display-name"}' \
    2>/dev/null)

if [[ $? -ne 0 ]] || [[ -z "$instances_json" ]]; then
    echo "Error: Failed to retrieve instances from compartment $COMPARTMENT_OCID in region $REGION"
    echo "Please check:"
    echo "  - Compartment OCID is correct"
    echo "  - Region is valid"
    echo "  - OCI CLI authentication is working"
    echo "  - You have permissions to list instances in this compartment"
    exit 1
fi

total_instances=$(echo "$instances_json" | jq '. | length')
echo "Found $total_instances total running instances"
echo

# Process each filter
for filter in "${FILTERS[@]}"; do
    # Generate filename based on sanitized filter
    sanitized=$(sanitize_filename "$filter")
    filename="${sanitized}.csv"
    
    process_filter "$filter" "$filename" "$instances_json"
    echo
done

echo "🎉 Discovery complete! Generated CSV files:"
for filter in "${FILTERS[@]}"; do
    sanitized=$(sanitize_filename "$filter")
    filename="${sanitized}.csv"
    if [[ -f "$filename" ]]; then
        line_count=$(($(wc -l < "$filename") - 1))  # Subtract header
        echo "  📄 $filename ($line_count instances)"
    fi
done
