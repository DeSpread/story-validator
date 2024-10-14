#!/bin/bash

# Global setting variables, typically uppercase
# Path to the JSON file
_UPGRADE_INFO_PATH="$HOME/.story/story/data/upgrade-info.json"

get_aws_story_binary_url() {
    local story_version="$1"
    echo "https://story-geth-binaries.s3.us-west-1.amazonaws.com/story-public/story-linux-amd64-${story_version}.tar.gz"
}

# Function to check if the upgrade has already been done
check_if_upgrade_already_done() {
    if [ -f "$_UPGRADE_INFO_PATH" ]; then
        # Read the upgrade block height from the JSON file
        _UPGRADE_HEIGHT=$(jq -r '.height' "$_UPGRADE_INFO_PATH")

        # Check if the upgrade block height matches the condition block height
        if [ "$_UPGRADE_HEIGHT" -eq "$1" ]; then
            echo "Upgrade already performed at block height $_UPGRADE_HEIGHT. Skipping upgrade."
            return 0  # Return true if the upgrade was already done
        fi
    fi
    return 1  # Return false if the upgrade was not done
}

# Schedule an upgrade to the Story client
schedule_client_upgrade() {
    # Parameters for the function
    local upgrade_link="$1"
    local client_version="$2"
    local upgrade_height="$3"

    echo "Schedule an upgrade to the Story client"
    echo "upgrade_link=$upgrade_link"
    echo "client_version=$client_version"
    echo "upgrade_height=$upgrade_height"

    # Create a temporary directory for the download
    temp_dir=$(mktemp -d)
    cd "$temp_dir"

    # Download and extract the Client
    echo "Download and extract the new client in progress..."
    curl -L "$upgrade_link" | tar -xz

    # Find the client executable
    client_executable=$(find . -type f -executable | head -n 1)

    if [ -z "$client_executable" ]; then
        echo "Error: The downloaded archive does not contain an executable file."
        cd - > /dev/null
        rm -rf "$temp_dir"
        return
    fi

    # Get the full path of the client executable
    client_path=$(readlink -f "$client_executable")

    # Run the command to schedule the upgrade
    if [ "$upgrade_height" -eq 0 ]; then
      echo "Immediately upgrade to the new client."
      cosmovisor add-upgrade "$client_version" "$client_path" --force
    else
      echo "Scheduling the upgrade to the new client."
      cosmovisor add-upgrade "$client_version" "$client_path" --force --upgrade-height "$upgrade_height"
    fi

    # Clean up
    cd - > /dev/null
    rm -rf "$temp_dir"

    echo "Upgrade scheduled successfully!"
}

# Check the block height and run the upgrade
while true; do
    # Fetch current block height
    LATEST_BLOCK_HEIGHT=$($HOME/.story/story/cosmovisor/genesis/bin/story status | jq .sync_info.latest_block_height | xargs)

    echo "Current block height: $LATEST_BLOCK_HEIGHT"

    if [ "$LATEST_BLOCK_HEIGHT" -ge 990456 ]; then
        # Upgrade the node: v0.10.1 -> v0.11.0
        # Check if the upgrade has already been performed
        if check_if_upgrade_already_done 1325860; then
            echo "No need to perform the upgrade again."
        else
            echo "Block height $LATEST_BLOCK_HEIGHT has reached 990456."
            schedule_client_upgrade "$(get_aws_story_binary_url "0.11.0-aac4bfe")" "v0.11.0" 1325860
        fi
    elif [ "$LATEST_BLOCK_HEIGHT" -ge 626575 ]; then
        # Upgrade the node: v0.10.0 -> v0.10.1
        # Check if the upgrade has already been performed
        if check_if_upgrade_already_done 990456; then
            echo "No need to perform the upgrade again."
        else
            echo "Block height $LATEST_BLOCK_HEIGHT has reached 626575."
            schedule_client_upgrade "$(get_aws_story_binary_url "0.10.1-57567e5")" "v0.10.1" 990456
        fi
    elif [ "$LATEST_BLOCK_HEIGHT" -ge 1 ]; then
        # Upgrade the node: v0.9.13 -> v0.10.0
        # Check if the upgrade has already been performed
        if check_if_upgrade_already_done 626575; then
            echo "No need to perform the upgrade again."
        else
            echo "Block height $LATEST_BLOCK_HEIGHT has reached 1."
            schedule_client_upgrade "$(get_aws_story_binary_url "0.10.0-9603826")" "v0.10.0" 626575
        fi
    fi

    sleep 5
done