#!/bin/bash

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

    # Check if current block has reached destination block
    # Upgrade the node: v0.10.x -> v0.11.0
    if [ "$LATEST_BLOCK_HEIGHT" -ge 626575 ]; then
        echo "Block height $LATEST_BLOCK_HEIGHT has reached $TARGET_BLOCK_HEIGHT. Start to upgrade node to the new client."

        schedule_client_upgrade "https://story-geth-binaries.s3.us-west-1.amazonaws.com/story-public/story-linux-amd64-0.11.0-aac4bfe.tar.gz" "v0.11.0" 1325860
        break
    fi

    sleep 5
done