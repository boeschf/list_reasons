#!/usr/bin/env bash

declare -A reason_stats
cxi_issue_count=0
cxi_issue_list=""

# Get a list of nodes that are down or drained
nodes=$(sinfo -a -h -N -o "%N %T" | grep -E ".*down.*|.*drain.*" | awk '{print $1}')

# Loop over each node
counter=1
for node in ${nodes}; do
    echo ""
    echo "Processing node #$counter: $node"
    echo "==============================="
    # Get the list of jobs for the node
    #jobs=$(sacct -X -n -o "user,start,jobid%-16,elapsed,nnodes,state%-16,FailedNode%9,Ntasks,NodeList%-46" --nodelist $node)
    jobs=$(sacct -X -n -o "user,jobid%-16,state%-36,Reason%-16,ExitCode%-8,SystemComment%-16,Comment%-16" --nodelist $node)

    scontrol show node $node | grep -E "NodeName=|State=|Reason="
    sacct -X -n -o "user,start,jobid%-16,elapsed,nnodes,state%-16,FailedNode%9,Ntasks,NodeList%-46" --nodelist $node | tail -n 5

    # Retrieve the reason and state information using scontrol
    reason=$(scontrol show node $node | grep -oP "Reason=\K.*")

    # Retrieve recent jobs on this node using sacct (last 1 job for simplicity)
    job_info=$(sacct -X -n -o "user,jobid%-16" --nodelist $node | tail -n 1)
    job_user=$(echo "$job_info" | awk '{print $1}')
    job_id=$(echo "$job_info" | awk '{print $2}')

    # Format the information to store by reason
    if [[ -z "$reason" ]]; then
        reason="No reason specified"
    fi
    node_info="Node: $node"
    [[ -n "$job_user" ]] && node_info+=", User: $job_user"
    [[ -n "$job_id" ]] && node_info+=", JobID: $job_id"

    # Append this node's info to the reason category in the associative array
    reason_stats["$reason"]+="$node_info"$'\n'

    # Check if the reason contains "cxi: could not delete service device"
    if [[ "$reason" == *"cxi: could not delete service device"* ]]; then
        ((cxi_issue_count++))
        cxi_issue_list+="$node_info, Reason: $reason"$'\n'
    fi

    # Check if jobs list is not empty
    if [[ -n "$jobs" ]]; then
        # Get the last entry in jobs
        last_entry=$(echo "$jobs" | tail -n 1)

        # Extract the first column (user) and third column (job ID) from the last entry
        last_user=$(echo "$last_entry" | awk '{print $1}')
        job_id=$(echo "$last_entry" | awk '{print $2}')

        echo "node = ${node}: last job = ${last_entry}"
    else
        echo "Node $node: No job information available"
    fi
    ((counter++))
done

echo ""
echo ""
# Output the grouped statistics
echo "=== Statistics Grouped by Reason ==="
for reason in "${!reason_stats[@]}"; do
    echo "Reason: $reason"
    echo "${reason_stats[$reason]}"
    echo "------------------------------------"
done


echo ""
echo ""
# Output the summary/count for "cxi: could not delete service device"
if (( cxi_issue_count > 0 )); then
    echo "=== Nodes with 'cxi: could not delete service device' Issues ==="
    echo "Total Count: $cxi_issue_count"
    echo "$cxi_issue_list"
else
    echo "No entries found with 'cxi: could not delete service device' in the reason."
fi

