#!/bin/bash

# Global setting variables, typically uppercase
export GO_VERSION="1.23.2"

_COSMOVISOR_VERSION="v1.6.0"

_INIT_STORY_GETH_VERSION="0.9.3-b224fdf"
_INIT_STORY_VERSION="0.9.13-b4c7db1"

# URL of the update script to download
_UPDATE_SCRIPT_URL="https://raw.githubusercontent.com/DeSpread/story-validator/refs/heads/main/story-validators-race/wave-2/story-automatic-update.sh"
# Path to save the update script
_UPDATE_SCRIPT_PATH="/usr/local/bin/story-automatic-update.sh"
# Path for the systemd update service file
_UPDATE_SERVICE_PATH="/etc/systemd/system/story-update.service"

# Function to get AWS Geth binary URL
get_aws_geth_binary_url() {
    local geth_version="$1"
    echo "https://story-geth-binaries.s3.us-west-1.amazonaws.com/geth-public/geth-linux-amd64-${geth_version}.tar.gz"
}

# Function to get AWS Story binary URL
get_aws_story_binary_url() {
    local story_version="$1"
    echo "https://story-geth-binaries.s3.us-west-1.amazonaws.com/story-public/story-linux-amd64-${story_version}.tar.gz"
}

display_logo() {
  echo " ▗▄▄▄ ▗▄▄▄▖ ▗▄▄▖▗▄▄▖ ▗▄▄▖ ▗▄▄▄▖ ▗▄▖ ▗▄▄▄ "
  echo " ▐▌  █▐▌   ▐▌   ▐▌ ▐▌▐▌ ▐▌▐▌   ▐▌ ▐▌▐▌  █"
  echo " ▐▌  █▐▛▀▀▘ ▝▀▚▖▐▛▀▘ ▐▛▀▚▖▐▛▀▀▘▐▛▀▜▌▐▌  █"
  echo " ▐▙▄▄▀▐▙▄▄▖▗▄▄▞▘▐▌   ▐▌ ▐▌▐▙▄▄▖▐▌ ▐▌▐▙▄▄▀"
  echo ""
  echo "- Website: https://despread.io"
  echo "- Twitter: https://x.com/despreadteam"
  echo "- Github: https://github.com/DeSpread"
  echo ""
}

# Display the main dashboard menu
display_dashboard_menu() {
    clear
    display_logo

    echo "Story Node Dashboard by DeSpread."
    echo "1. Install Story Node"
    echo "2. Upgrade Node"
    echo "3. Check Version"
    echo "4. Check Sync Status"
    echo "5. Check Logs"
    echo "6. Quit"
    echo ""
    echo -n "Please enter your choice: "
}

# Install required packages
install_required_packages() {
    sudo apt update && sudo apt upgrade -y
    sudo apt install curl git jq build-essential gcc unzip wget lz4 -y
}

# Install Go
install_go() {
    cd $HOME && wget "https://golang.org/dl/go$GO_VERSION.linux-amd64.tar.gz" && \
    sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf "go$GO_VERSION.linux-amd64.tar.gz" && \
    rm "go$GO_VERSION.linux-amd64.tar.gz" && echo "export PATH=$PATH:/usr/local/go/bin:~/go/bin" >> $HOME/.bash_profile && . $HOME/.bash_profile && go version
    mkdir -p $HOME/go/bin
}

# Download and Install Story-Geth Binary
install_story_geth() {
    wget -q $(get_aws_geth_binary_url "$_INIT_STORY_GETH_VERSION") -O /tmp/geth-linux-amd64-$_INIT_STORY_GETH_VERSION.tar.gz
    tar -xzf /tmp/geth-linux-amd64-$_INIT_STORY_GETH_VERSION.tar.gz -C /tmp
    mkdir -p $HOME/go/bin
    sudo cp /tmp/geth-linux-amd64-$_INIT_STORY_GETH_VERSION/geth $HOME/go/bin/story-geth
}

# Download and Install Story Binary using Cosmovisor
install_story_binary() {
    wget -q $(get_aws_story_binary_url "$_INIT_STORY_VERSION") -O /tmp/story-linux-amd64-$_INIT_STORY_VERSION.tar.gz
    tar -xzf /tmp/story-linux-amd64-$_INIT_STORY_VERSION.tar.gz -C /tmp
    mkdir -p $HOME/.story/story/cosmovisor/genesis/bin
    sudo cp /tmp/story-linux-amd64-$_INIT_STORY_VERSION/story $HOME/.story/story/cosmovisor/genesis/bin/story
}

# Install and setup Cosmovisor
install_cosmovisor() {
    go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@$_COSMOVISOR_VERSION

    mkdir -p $HOME/.story/story/cosmovisor
    mkdir -p $HOME/.story/story/backup
    echo "export DAEMON_NAME=story" >> $HOME/.bash_profile
    echo "export DAEMON_HOME=$HOME/.story/story" >> $HOME/.bash_profile
    echo "export DAEMON_DATA_BACKUP_DIR=$HOME/.story/story/backup" >> $HOME/.bash_profile
    echo "export PATH=$HOME/go/bin:$DAEMON_HOME/cosmovisor/current/bin:$PATH" >> $HOME/.bash_profile
    . $HOME/.bash_profile
}

# Update node peers
update_node_peers() {
  echo "Update peers in progress..."
  PEERS=$(curl -sS https://story-testnet-rpc.polkachu.com/net_info |
    jq -r '.result.peers[] | select(.node_info.id != null and .remote_ip != null and .node_info.listen_addr != null) |
    "\(.node_info.id)@\(if .node_info.listen_addr | contains("0.0.0.0") then .remote_ip + ":" + (.node_info.listen_addr | sub("tcp://0.0.0.0:"; "")) else (.node_info.listen_addr | sub("tcp://"; "")) end)"' |
    paste -sd ',')

    PEERS="\"$PEERS\""
    echo "Node peers has been successfully updated. peers: $PEERS"

    if [ -n "$PEERS" ]; then
        sed -i "s/^persistent_peers *=.*/persistent_peers = $PEERS/" "$HOME/.story/story/config/config.toml"
        if [ $? -eq 0 ]; then
            echo -e "Configuration file updated successfully with new peers"
        else
            echo "Failed to update configuration file."
        fi
    else
        echo "No peers found to update."
    fi
}

# Set up systemd services
setup_systemd_services() {
    sudo tee /etc/systemd/system/story-geth.service > /dev/null <<EOF
[Unit]
Description=Story Geth Client
After=network.target

[Service]
User=$USER
ExecStart=$HOME/go/bin/story-geth --iliad --syncmode full
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    # Create and Configure systemd Service for Cosmovisor (Story)
    sudo tee /etc/systemd/system/story.service > /dev/null <<EOF
[Unit]
Description=Cosmovisor service for Story binary
After=network.target

[Service]
User=$USER
ExecStart=$HOME/go/bin/cosmovisor run run
WorkingDirectory=$HOME/.story/story
Restart=on-failure
RestartSec=3
LimitNOFILE=65535
Environment="DAEMON_NAME=story"
Environment="DAEMON_HOME=$HOME/.story/story"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=true"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="DAEMON_DATA_BACKUP_DIR=$HOME/.story/story/data"
Environment="UNSAFE_SKIP_BACKUP=true"

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd, Enable, and Start Services
    sudo systemctl daemon-reload
    sudo systemctl enable story-geth story
    sudo systemctl start story-geth story

    echo "Story node system daemon setup has been successfully completed."
}

setup_update_systemd_service() {
  # 1. Download the script and install it
  mkdir -p "/usr/local/bin"
  echo "Downloading the script from $_UPDATE_SCRIPT_URL..."
  sudo wget -q $_UPDATE_SCRIPT_URL -O $_UPDATE_SCRIPT_PATH

  # 2. Grant execute permissions to the script
  echo "Setting execute permission for the script..."
  sudo chmod +x $_UPDATE_SCRIPT_PATH

  # 3. Create the systemd service file
  echo "Creating systemd service file..."
  sudo tee $_UPDATE_SERVICE_PATH > /dev/null << EOF
[Unit]
Description=Story Automatic Update Service
After=network.target

[Service]
User=$USER
ExecStart=$_UPDATE_SCRIPT_PATH
Restart=on-failure
RestartSec=60
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

  # 4. Reload systemd configuration
  echo "Reloading systemd daemon..."
  sudo systemctl daemon-reload

  # 5. Enable and start the service
  echo "Enabling and starting the story-update service..."
  sudo systemctl enable story-update.service
  sudo systemctl start story-update.service

  # 6. Check the status
  echo "Service 'story-update' has been installed and started. Checking the status..."
  sudo systemctl status story-update.service
}

# Install the Story Node
install_story_node() {
    read -p "Enter your node moniker: " moniker

    install_required_packages
    install_go
    install_story_geth
    install_story_binary
    install_cosmovisor

    # Initialize Story node
    $HOME/.story/story/cosmovisor/genesis/bin/story init --network iliad --moniker "$moniker"

    # Initialize Cosmovisor
    cosmovisor init $HOME/.story/story/cosmovisor/genesis/bin/story
    cosmovisor version
    echo "Cosmovisor has been successfully installed"

    update_node_peers
    setup_systemd_services

    echo "Story Node has been successfully installed."

    setup_update_systemd_service

    while true; do
        echo -e "\nWhat would you like to do next?"
        echo "1. Back to dashboard menu"
        echo "2. Quit"
        read -p "Please enter your choice: " after_install_choice
        case $after_install_choice in
            1)
                return
                ;;
            2)
                echo "Exiting the script."
                exit 0
                ;;
            *)
                echo "Invalid option. Please try again."
                ;;
        esac
    done
}

# Check logs
check_logs() {
    echo -e "\nPlease select the logs you want to check:"
    echo "1. Check Story Logs"
    echo "2. Check Story-Geth Logs"
    echo "3. Quit"
    echo -n "Please enter your choice: "
    read log_choice

    case $log_choice in
        1)
            echo -e "\nChecking Story logs"
            sudo journalctl -u story -f -o cat
            ;;
        2)
            echo -e "\nChecking Story-Geth logs"
            sudo journalctl -u story-geth -f -o cat
            ;;
        3)
            echo "Exiting log check."
            ;;
        *)
            echo "Invalid option."
            ;;
    esac
}

# Check sync status
check_sync_status() {
    echo -e "\nChecking node sync status"
    trap 'return' INT
    while true; do
        local_height=$(curl -s localhost:26657/status | jq -r '.result.sync_info.latest_block_height')
        network_height=$(curl -s https://story-testnet-rpc.polkachu.com/status | jq -r '.result.sync_info.latest_block_height')
        blocks_left=$((network_height - local_height))

        printf "\033[1;32mYour node height:\033[0m \033[1;34m$local_height\033[0m | \033[1;33mNetwork height:\033[0m \033[1;36m$network_height\033[0m | \033[1;37mBlocks left:\033[0m \033[1;31m$blocks_left\033[0m\n"

        sleep 4
    done
}

upgrade_menu() {
    clear
    echo "Here are the upgrade options:"
    echo "1. Schedule a Story client upgrade at a specific block height"
    echo "2. Story Client Instant Upgrade"
    echo "3. Back to Dashboard Menu"
    echo -n "Please enter your choice: "
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

upgrade_node() {
  while true; do
    upgrade_menu
    read upgrade_choice
    case $upgrade_choice in
        1)
            read -p "Enter the link for the client upgrade: " upgrade_link
            read -p "Enter the new version of the client (e.g. v0.11.0): " client_version
            read -p "Enter upgrade Height: " upgrade_height

            schedule_client_upgrade "$upgrade_link" "$client_version" "$upgrade_height"

            # Ask user for next action
            while true; do
                echo -e "\nWhat would you like to do next?"
                echo "1. Back to dashboard menu"
                echo "2. Quit"
                read -p "Enter your choice: " post_upgrade_choice
                case $post_upgrade_choice in
                    1)
                        return
                        ;;
                    2)
                        echo "Exiting the script. Goodbye!"
                        exit 0
                        ;;
                    *)
                        echo "Invalid option. Please try again."
                        ;;
                esac
            done
            break
            ;;
        2)
            read -p "Enter the link for the client upgrade: " upgrade_link
            read -p "Enter the new version of the client (e.g. v0.11.0): " client_version

            schedule_client_upgrade "$upgrade_link" "$client_version" 0

            # Ask user for next action
            while true; do
                echo -e "\nWhat would you like to do next?"
                echo "1. Back to dashboard menu"
                echo "2. Quit"
                read -p "Enter your choice: " post_upgrade_choice
                case $post_upgrade_choice in
                    1)
                        return
                        ;;
                    2)
                        echo "Exiting the script. Goodbye!"
                        exit 0
                        ;;
                    *)
                        echo "Invalid option. Please try again."
                        ;;
                esac
            done
            break
            ;;
        3)
            break
            ;;
        *)
            echo "This is an invalid option, please try again."
            ;;
    esac
  done
}

# Check version
check_version() {
    echo -e "\nPlease select the version you wish to check:"
    echo "1. Story Version"
    echo "2. Story-Geth Version"
    echo "3. Back to main menu"
    echo -n "Please enter your choice: "
    read version_choice

    case $version_choice in
        1)
            echo -e "\nChecking Story version."
            cosmovisor run version
            ;;
        2)
            echo -e "\nChecking Story-Geth version."
            story-geth version
            ;;
        3)
            return
            ;;
        *)
            echo "This is an invalid option, please try again."
            ;;
    esac

    echo -e "\nPress the Enter key to continue."
    read
}

# Main loop
while true; do
    display_dashboard_menu
    read choice
    case $choice in
        1) install_story_node ;;
        2) upgrade_node ;;
        3) check_version ;;
        4) check_sync_status ;;
        5) check_logs ;;
        6)
          echo "Exiting the dashboard."
          exit 0
          ;;
        *) echo "This is an invalid option, please try again." ;;
    esac
done