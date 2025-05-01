#!/bin/bash

# Color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print error message
print_error() {
  echo -e "${RED}$1${NC}" >&2
}

# Function to print success message
print_success() {
  echo -e "${GREEN}$1${NC}"
}

# Function to print info message
print_info() {
  echo -e "${CYAN}$1${NC}"
}

# Function to check and update Go version
check_and_update_go() {
  # Check current Go version
  if command -v go &> /dev/null; then
    go_version=$(go version | awk '{print $3}' | sed 's/go//')
    go_major=$(echo $go_version | cut -d. -f1)
    go_minor=$(echo $go_version | cut -d. -f2)
    
    # Check if Go version is less than 1.20
    if [ "$go_major" -lt 1 ] || ([ "$go_major" -eq 1 ] && [ "$go_minor" -lt 20 ]); then
      print_info "Current Go version $go_version is too old for sing-box. Minimum required is 1.20."
      print_info "Installing Go 1.24.2..."
      
      # Download and install Go 1.24.2
      wget -q https://go.dev/dl/go1.24.2.linux-amd64.tar.gz
      sudo rm -rf /usr/local/go
      sudo tar -C /usr/local -xzf go1.24.2.linux-amd64.tar.gz
      rm go1.24.2.linux-amd64.tar.gz
      
      # Add to PATH for current session
      export PATH=$PATH:/usr/local/go/bin
      
      # Check if Go is in profile
      if ! grep -q "/usr/local/go/bin" ~/.profile; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.profile
      fi
      
      print_success "Go updated to version $(go version | awk '{print $3}')"
    else
      print_info "Go version $go_version is suitable for building sing-box."
    fi
  else
    print_info "Go not found. Installing Go 1.24.2..."
    wget -q https://go.dev/dl/go1.24.2.linux-amd64.tar.gz
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf go1.24.2.linux-amd64.tar.gz
    rm go1.24.2.linux-amd64.tar.gz
    
    # Add to PATH for current session
    export PATH=$PATH:/usr/local/go/bin
    
    # Check if Go is in profile
    if ! grep -q "/usr/local/go/bin" ~/.profile; then
      echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.profile
    fi
    
    print_success "Go installed successfully: $(go version | awk '{print $3}')"
  fi
}

# X architecture detection function
x_architecture() {
  local arch
  case "$(uname -m)" in
    'i386' | 'i686') arch='32' ;;
    'amd64' | 'x86_64') arch='64' ;;
    'armv5tel') arch='arm32-v5' ;;
    'armv6l')
      arch='arm32-v6'
      grep Features /proc/cpuinfo | grep -qw 'vfp' || arch='arm32-v5'
      ;;
    'armv7' | 'armv7l')
      arch='arm32-v7a'
      grep Features /proc/cpuinfo | grep -qw 'vfp' || arch='arm32-v5'
      ;;
    'armv8' | 'aarch64') arch='arm64-v8a' ;;
    'mips') arch='mips32' ;;
    'mipsle') arch='mips32le' ;;
    'mips64')
      arch='mips64'
      lscpu | grep -q "Little Endian" && arch='mips64le'
      ;;
    'mips64le') arch='mips64le' ;;
    'ppc64') arch='ppc64' ;;
    'ppc64le') arch='ppc64le' ;;
    'riscv64') arch='riscv64' ;;
    's390x') arch='s390x' ;;
    *)
      print_error "Error: The architecture is not supported."
      return 1
      ;;
  esac
  echo "$arch"
}

# Hysteria architecture detection
hys_architecture() {
    case "$(uname -m)" in
        i386 | i686) echo "386" ;;
        x86_64) grep -q avx /proc/cpuinfo && echo "amd64-avx" || echo "amd64" ;;
        armv5*) echo "armv5" ;;
        armv7* | arm) echo "arm" ;;
        aarch64) echo "arm64" ;;
        mips) echo "mipsle" ;;
        riscv64) echo "riscv64" ;;
        s390x) echo "s390x" ;;
        *) echo "Unsupported architecture: $(uname -m)";;
    esac
}

# Installing necessary packages
print_info "Installing necessary packages..."
print_info "DON'T PANIC IF IT LOOKS STUCK!"
sudo apt-get update
sudo apt-get install curl socat git wget unzip make golang -y

# Check if Rye is already installed
print_info "Checking for Rye (Python environment manager)..."
if [ ! -f "$HOME/.rye/shims/rye" ]; then
    print_info "Rye not found. Installing Rye..."
    curl -sSf https://rye.astral.sh/get | bash
    
    # Add Rye shims to PATH for this session and permanently
    export PATH="$HOME/.rye/shims:$PATH"
    
    # Add to profile for future sessions
    if ! grep -q 'source "$HOME/.rye/env"' ~/.profile; then
        echo 'source "$HOME/.rye/env"' >> ~/.profile
    fi
    
    # Add to bashrc as well for interactive shells
    if ! grep -q 'source "$HOME/.rye/env"' ~/.bashrc; then
        echo 'source "$HOME/.rye/env"' >> ~/.bashrc
    fi
    
    print_success "Rye installed successfully!"
else
    print_success "Rye is already installed. Skipping installation."
fi

# Source the Rye env for this session
if [ -f "$HOME/.rye/env" ]; then
    source "$HOME/.rye/env"
else
    print_error "Rye environment file not found. Please check Rye installation."
    exit 1
fi

# Setting up shared core directory for templates (not for direct use)
print_info "Setting up cores directory..."
sudo mkdir -p /opt/marznode/cores
sudo mkdir -p /opt/marznode/cores/xray
sudo mkdir -p /opt/marznode/cores/sing-box
sudo mkdir -p /opt/marznode/cores/hysteria

# Folder name
print_info "Set a name for node directory (leave blank for a random name - not recommended): "
read -r node_directory
node_directory=${node_directory:-node$(openssl rand -hex 1)}

# clean up 
print_info "directory set to: $node_directory"
print_info "Removing existing directories and files..."
rm -rf "/opt/marznode/$node_directory" &> /dev/null

# Setting path
sudo mkdir -p /opt/marznode/$node_directory
sudo mkdir -p /opt/marznode/$node_directory/xray
sudo mkdir -p /opt/marznode/$node_directory/sing-box
sudo mkdir -p /opt/marznode/$node_directory/hysteria

# Port setup
while true; do
  print_info "Enter the SERVICE PORT value (default 53042): "
  read -r service
  service=${service:-53042}
  break
done

# Certificate setup
print_info "Please paste the content of the Client Certificate, press ENTER on a new line when finished: "

cert=""
while IFS= read -r line; do
  if [[ -z $line ]]; then
    break
  fi
  cert+="$line\n"
done

echo -e "$cert" | sudo tee /opt/marznode/$node_directory/client.pem > /dev/null

# Install cores if they don't exist in the shared template directory
if [ ! -f "/opt/marznode/cores/xray/xray" ]; then
    # xray
    print_info "Which version of xray core do you want? (e.g., 1.8.24) (leave blank for latest): "
    read -r version
    xversion=${version:-latest}

    # Fetching xray core and setting it up
    arch=$(x_architecture)
    cd "/opt/marznode/cores/xray"

    wget -O config.json "https://raw.githubusercontent.com/ebadidev/ez-node/refs/heads/main/etc/xray.json"

    print_info "Fetching Xray core version $xversion..."

    if [[ $xversion == "latest" ]]; then
      wget -O xray.zip "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-$arch.zip"
    else
      wget -O xray.zip "https://github.com/XTLS/Xray-core/releases/download/v$xversion/Xray-linux-$arch.zip"
    fi

    if unzip xray.zip; then
      rm xray.zip
      chmod +x xray
      print_success "Success! xray installed"
    else
      print_error "Failed to unzip xray.zip."
      exit 1
    fi
else
    print_info "Xray core template already exists in shared directory."
fi

if [ ! -f "/opt/marznode/cores/sing-box/sing-box" ]; then
    # sing box
    print_info "Which version of sing-box core do you want? (e.g., 1.10.3) (leave blank for latest): "
    read -r version
    latest=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep '"tag_name"' | cut -d '"' -f 4)
    sversion=${version:-$latest}

    # Check and update Go version before building sing-box
    check_and_update_go

    # Building sing-box
    cd /opt/marznode/cores/sing-box
    wget -O config.json "https://raw.githubusercontent.com/ebadidev/ez-node/refs/heads/main/etc/sing-box.json"
    echo $sversion
    wget -O sing.zip "https://github.com/SagerNet/sing-box/archive/refs/tags/v${sversion#v}.zip"
    unzip sing.zip
    cd ./sing-box-${sversion#v}
    go build -v -trimpath -ldflags "-X github.com/sagernet/sing-box/constant.Version=${sversion#v} -s -w -buildid=" -tags with_gvisor,with_dhcp,with_wireguard,with_reality_server,with_clash_api,with_quic,with_utls,with_ech,with_v2ray_api,with_grpc ./cmd/sing-box
    chmod +x ./sing-box
    mv sing-box /opt/marznode/cores/sing-box/
    cd ..
    rm sing.zip
    rm -rf ./sing-box-${sversion#v}

    print_success "Success! sing-box installed"
else
    print_info "Sing-box core template already exists in shared directory."
fi

if [ ! -f "/opt/marznode/cores/hysteria/hysteria" ]; then
    # hysteria
    print_info "Which version of hysteria core do you want? (e.g., 2.6.0) (leave blank for latest): "
    read -r version
    latest=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | grep '"tag_name"' | cut -d '"' -f 4)
    hversion=${version:-$latest}
    hversion=${hversion#app/v}

    # Fetching hysteria core and setting it up
    cd /opt/marznode/cores/hysteria
    arch=$(hys_architecture)
    wget -O hysteria "https://github.com/apernet/hysteria/releases/download/app/v$hversion/hysteria-linux-$arch"
    chmod +x ./hysteria

    print_success "Success! hysteria installed"
else
    print_info "Hysteria core template already exists in shared directory."
fi

# Now copy the cores from the template directory to this node's directory
print_info "Copying cores to node directory..."

# Copy xray
if [ -f "/opt/marznode/cores/xray/xray" ]; then
    cp -f /opt/marznode/cores/xray/xray /opt/marznode/$node_directory/xray/
    cp -f /opt/marznode/cores/xray/config.json /opt/marznode/$node_directory/xray/
    chmod +x /opt/marznode/$node_directory/xray/xray
    print_success "Xray core copied to node directory"
else
    print_error "Xray core not found in template directory"
    exit 1
fi

# Copy sing-box
if [ -f "/opt/marznode/cores/sing-box/sing-box" ]; then
    cp -f /opt/marznode/cores/sing-box/sing-box /opt/marznode/$node_directory/sing-box/
    cp -f /opt/marznode/cores/sing-box/config.json /opt/marznode/$node_directory/sing-box/
    chmod +x /opt/marznode/$node_directory/sing-box/sing-box
    print_success "Sing-box core copied to node directory"
else
    print_error "Sing-box core not found in template directory"
    exit 1
fi

# Copy hysteria
if [ -f "/opt/marznode/cores/hysteria/hysteria" ]; then
    cp -f /opt/marznode/cores/hysteria/hysteria /opt/marznode/$node_directory/hysteria/
    chmod +x /opt/marznode/$node_directory/hysteria/hysteria
    print_success "Hysteria core copied to node directory"
else
    print_error "Hysteria core not found in template directory"
    exit 1
fi

# Get enable status for each component
print_info "Do you want to enable xray (y/n)"
read -r answer
x_enable=$( [[ "$answer" =~ ^[Yy]$ ]] && echo "True" || echo "False" )

print_info "Do you want to enable sing-box (y/n)"
read -r answer
sing_enable=$( [[ "$answer" =~ ^[Yy]$ ]] && echo "True" || echo "False" )

print_info "Do you want to enable hysteria (y/n)"
read -r answer
hys_enable=$( [[ "$answer" =~ ^[Yy]$ ]] && echo "True" || echo "False" )

# Configure Hysteria only if enabled
hysteria_domain="example.com"
hysteria_email="info@example.com"
hysteria_port="6291"

if [ "$hys_enable" = "True" ]; then
    # Hysteria domain setup
    print_info "Enter the domain name for Hysteria (e.g., example.com): "
    read -r hysteria_domain
    hysteria_domain=${hysteria_domain:-example.com}

    # Auto-fill email with info@domain
    hysteria_email="info@$hysteria_domain"
    
    print_info "Enter the port for Hysteria (default 6291): "
    read -r hysteria_port
    hysteria_port=${hysteria_port:-6291}
    
    # Configure hysteria.yaml with domain and port in the node's directory
    cat << EOF > /opt/marznode/$node_directory/hysteria/config.yaml
listen: :$hysteria_port

acme:
  domains:
    - $hysteria_domain
  email: $hysteria_email
  ca: letsencrypt
  disableHTTP: false
  disableTLSALPN: false
  altHTTPPort: 80
  altTLSALPNPort: 443
  dir: /opt/marznode/$node_directory/hysteria/acme/

masquerade:
  type: proxy
  proxy:
    url: https://www.speedtest.net
    rewriteHost: true

resolver:
  type: udp
  udp:
    addr: 1.1.1.2:53
    timeout: 10s
EOF

    print_success "Hysteria configuration created with domain: $hysteria_domain and port: $hysteria_port"
fi

# Clone marznode repository and set up Python environment
print_info "Cloning marznode repository and setting up Python environment..."
cd /opt/marznode/$node_directory

# Clone to a node-specific directory to avoid any potential sharing issues
git clone https://github.com/khodedawsh/marznode marznode-$node_directory
cd marznode-$node_directory

# Defining env path - placing ENV inside the node-specific marznode directory
ENV="/opt/marznode/$node_directory/marznode-$node_directory/.env"

# Setting up env with shared core paths
cat << EOF > "$ENV"
# Configuration for node: $node_directory (to help identify this specific node's config)
SERVICE_ADDRESS=0.0.0.0
SERVICE_PORT=$service
#INSECURE=False

XRAY_ENABLED=$x_enable
XRAY_EXECUTABLE_PATH=/opt/marznode/$node_directory/xray/xray
XRAY_ASSETS_PATH=/opt/marznode/$node_directory/xray
XRAY_CONFIG_PATH=/opt/marznode/$node_directory/xray/config.json
#XRAY_VLESS_REALITY_FLOW=xtls-rprx-vision
#XRAY_RESTART_ON_FAILURE=True
#XRAY_RESTART_ON_FAILURE_INTERVAL=5

HYSTERIA_ENABLED=$hys_enable
HYSTERIA_EXECUTABLE_PATH=/opt/marznode/$node_directory/hysteria/hysteria
HYSTERIA_CONFIG_PATH=/opt/marznode/$node_directory/hysteria/config.yaml

SING_BOX_ENABLED=$sing_enable
SING_BOX_EXECUTABLE_PATH=/opt/marznode/$node_directory/sing-box/sing-box
SING_BOX_CONFIG_PATH=/opt/marznode/$node_directory/sing-box/config.json
#SING_BOX_RESTART_ON_FAILURE=True
#SING_BOX_RESTART_ON_FAILURE_INTERVAL=5

SSL_KEY_FILE=./server.key
SSL_CERT_FILE=./server.cert
SSL_CLIENT_CERT_FILE=/opt/marznode/$node_directory/client.pem

#DEBUG=True
#AUTH_GENERATION_ALGORITHM=xxh128
EOF

print_success ".env file has been created at $ENV"

# Setup Python environment with Rye
print_info "Setting up Python environment with Rye for node $node_directory..."

# Initialize a new Rye project with node-specific name
rye init --name marznode-$node_directory --no-prompt

# Pin to Python 3.12
print_info "Pinning to Python 3.12..."
rye pin 3.12

# Add requirements from requirements.txt
if [ -f "requirements.txt" ]; then
    print_info "Adding dependencies from requirements.txt..."
    while read -r requirement; do
        # Skip empty lines and comments
        if [[ -z "$requirement" || "$requirement" == \#* ]]; then
            continue
        fi
        rye add "$requirement"
    done < requirements.txt
fi

# Ensure Rye has synchronized the environment
rye sync

print_success "Python environment set up with Rye successfully!"

# Create a script to run marznode with node-specific paths
cat << EOF > /opt/marznode/$node_directory/run_marznode.sh
#!/bin/bash
# Run script for node: $node_directory
cd /opt/marznode/$node_directory/marznode-$node_directory
# Source Rye environment
source "\$HOME/.rye/env"
# Export environment variables from THIS node's env file
export \$(grep -v '^#' ./.env | xargs)
# Display which node is starting (for verification)
echo "Starting marznode for node: $node_directory on port: $service"
# Run with Rye
rye run python marznode.py
EOF

chmod +x /opt/marznode/$node_directory/run_marznode.sh

# Create systemd service with node-specific configuration
print_info "Creating systemd service for node $node_directory..."
cat << EOF > /etc/systemd/system/marznode-$node_directory.service
[Unit]
Description=Marznode Service ($node_directory)
After=network.target
Wants=network.target

[Service]
Type=simple
WorkingDirectory=/opt/marznode/$node_directory/marznode-$node_directory
ExecStart=/opt/marznode/$node_directory/run_marznode.sh
Restart=always
RestartSec=1
LimitNOFILE=infinity
# Make sure HOME is set for the Rye environment
Environment="HOME=$(eval echo ~$SUDO_USER)"

# Logging configuration
StandardOutput=append:/var/log/marznode-$node_directory.log
StandardError=append:/var/log/marznode-$node_directory.error.log

# Optional: log rotation to prevent huge log files
LogRateLimitIntervalSec=0
LogRateLimitBurst=0

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
print_info "Enabling and starting the service..."
systemctl daemon-reload
systemctl enable marznode-$node_directory
systemctl restart marznode-$node_directory
sleep 2  # Give the service a moment to start

print_info "Checking service status..."
systemctl status marznode-$node_directory

print_success "Marznode has been successfully set up and started!"
print_success "Service name: marznode-$node_directory"
print_success "You can check logs at:"
print_success "  - /var/log/marznode-$node_directory.log"
print_success "  - /var/log/marznode-$node_directory.error.log"

# Setting up control script
cat << 'EOF' > /usr/local/bin/marznode
#!/bin/bash

# Color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print error message
print_error() {
  echo -e "${RED}$1${NC}" >&2
}

# Function to print success message
print_success() {
  echo -e "${GREEN}$1${NC}"
}

# Function to print info message
print_info() {
  echo -e "${CYAN}$1${NC}"
}

DEFAULT_DIR="/opt/marznode"
NODE_NAME="${1:-}"
COMMAND="${2:-}"

# Interactive menu functions
list_nodes() {
    local nodes=()
    local i=1
    
    # Check if the directory exists
    if [ ! -d "$DEFAULT_DIR" ]; then
        print_error "No nodes found. Directory $DEFAULT_DIR does not exist."
        exit 1
    fi
    
    # Find all service files for marznode
    for dir in "$DEFAULT_DIR"/*; do
        if [ -d "$dir" ] && [ "$(basename "$dir")" != "cores" ]; then
            nodes+=("$(basename "$dir")")
        fi
    done
    
    # Display node list
    if [ ${#nodes[@]} -eq 0 ]; then
        print_error "No nodes found in $DEFAULT_DIR"
        exit 1
    fi
    
    print_info "Available Marznode instances:"
    echo ""
    
    for node in "${nodes[@]}"; do
        if systemctl is-active --quiet "marznode-$node"; then
            echo -e "$(printf "%2d. %s " "$i" "$node")${GREEN}[ACTIVE]${NC}"
        else
            echo -e "$(printf "%2d. %s " "$i" "$node")${RED}[INACTIVE]${NC}"
        fi
        i=$((i+1))
    done
    
    echo ""
    echo "q. Quit"
    echo ""
    
    return 0
}

show_node_menu() {
    local node=$1
    local service_name="marznode-$node"
    local env_file="/opt/marznode/$node/marznode-$node/.env"
    local hysteria_config="/opt/marznode/$node/hysteria/config.yaml"
    
    clear
    print_info "Node: $node (Service: $service_name)"
    echo ""
    
    # Show current status
    if systemctl is-active --quiet "$service_name"; then
        echo -e "● Status: Running${NC}"
    else
        echo -e "○ Status: Stopped${NC}"
    fi
    
    # Get port number if available
    if [ -f "$env_file" ]; then
        port=$(grep "SERVICE_PORT" "$env_file" | cut -d'=' -f2)
        if [ -n "$port" ]; then
            echo -e "● Port: $port${NC}"
        fi
    fi
    
    echo ""
    echo "1. Restart service"
    echo "2. Stop service"
    echo "3. Start service"
    echo "4. View logs"
    echo "5. Edit .env file"
    echo "6. Edit hysteria config"
    echo "7. Delete node"
    echo ""
    echo "b. Back to node list"
    echo "q. Quit"
    echo ""
    
    read -p "Select an option: " option
    
    case $option in
        1)
            restart_node "$node"
            ;;
        2)
            stop_node "$node"
            ;;
        3)
            start_node "$node"
            ;;
        4)
            view_logs "$node"
            ;;
        5)
            edit_env "$node"
            ;;
        6)
            edit_hysteria_config "$node"
            ;;
        7)
            delete_node "$node"
            ;;
        b|B)
            return 1  # Back to main menu
            ;;
        q|Q)
            exit 0
            ;;
        *)
            print_error "Invalid option"
            sleep 1
            ;;
    esac
    
    return 0  # Stay in this menu
}

restart_node() {
    local node=$1
    local service_name="marznode-$node"
    
    print_info "Restarting $service_name..."
    
    # First try a normal stop
    systemctl stop $service_name
    
    # Wait for up to 1 second for graceful shutdown
    sleep 1
    
    # Only use force if needed
    if systemctl is-active --quiet $service_name; then
        print_info "Service still running, using force stop..."
        systemctl stop --force $service_name
        sleep 1
    fi
    
    systemctl reset-failed $service_name 2>/dev/null
    systemctl start $service_name
    
    if systemctl is-active --quiet $service_name; then
        print_success "Service restarted successfully!"
    else
        print_error "Failed to restart service."
    fi
    
    read -p "Press Enter to continue..."
}

stop_node() {
    local node=$1
    local service_name="marznode-$node"
    
    print_info "Stopping $service_name..."
    
    # First try a normal stop
    systemctl stop $service_name
    
    # Wait for up to 1 second for graceful shutdown
    sleep 1
    
    # Check if service stopped
    if ! systemctl is-active --quiet $service_name; then
        print_success "Service stopped successfully."
        read -p "Press Enter to continue..."
        return
    fi
    
    # Use force if needed after waiting
    print_info "Service still running, using force stop..."
    systemctl stop --force $service_name
    sleep 1
    
    # As a last resort, use kill
    if systemctl is-active --quiet $service_name; then
        print_info "WARNING: Service still running, using kill command..."
        systemctl kill $service_name
    fi
    
    if ! systemctl is-active --quiet $service_name; then
        print_success "Service stopped successfully!"
    else
        print_error "Failed to stop service."
    fi
    
    read -p "Press Enter to continue..."
}

start_node() {
    local node=$1
    local service_name="marznode-$node"
    
    print_info "Starting $service_name..."
    systemctl start $service_name
    
    if systemctl is-active --quiet $service_name; then
        print_success "Service started successfully!"
    else
        print_error "Failed to start service."
    fi
    
    read -p "Press Enter to continue..."
}

view_logs() {
    local node=$1
    local log_file="/var/log/marznode-$node.log"
    local error_log="/var/log/marznode-$node.error.log"
    
    if [ -f "$log_file" ]; then
        print_info "Viewing logs for $node (press q to exit):"
        sleep 1
        less -R "$log_file"
    else
        print_error "Log file not found: $log_file"
        read -p "Press Enter to continue..."
    fi
}

edit_env() {
    local node=$1
    local env_file="/opt/marznode/$node/marznode-$node/.env"
    
    if [ -f "$env_file" ]; then
        ${EDITOR:-vim} "$env_file"
    else
        print_error "Env file not found: $env_file"
        read -p "Press Enter to continue..."
    fi
}

edit_hysteria_config() {
    local node=$1
    local config_file="/opt/marznode/$node/hysteria/config.yaml"
    
    if [ -f "$config_file" ]; then
        ${EDITOR:-vim} "$config_file"
    else
        print_error "Hysteria config file not found: $config_file"
        read -p "Press Enter to continue..."
    fi
}

delete_node() {
    local node=$1
    local service_name="marznode-$node"
    local node_dir="/opt/marznode/$node"
    
    read -p "WARNING: Are you sure you want to delete $node? This cannot be undone! (y/N): " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "Deletion cancelled."
        read -p "Press Enter to continue..."
        return
    fi
    
    # Stop the service
    if systemctl is-active --quiet "$service_name"; then
        print_info "Stopping service..."
        systemctl stop --force "$service_name"
        sleep 1
    fi
    
    # Disable the service
    if systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
        print_info "Disabling service..."
        systemctl disable "$service_name"
    fi
    
    # Remove the service file
    if [ -f "/etc/systemd/system/$service_name.service" ]; then
        print_info "Removing service file..."
        rm -f "/etc/systemd/system/$service_name.service"
        systemctl daemon-reload
    fi
    
    # Remove log files
    print_info "Removing log files..."
    rm -f "/var/log/marznode-$node.log" "/var/log/marznode-$node.error.log"
    
    # Remove node directory
    if [ -d "$node_dir" ]; then
        print_info "Removing node directory..."
        rm -rf "$node_dir"
    fi
    
    print_success "Node $node has been deleted."
    read -p "Press Enter to continue..."
    
    return 1  # Return to main menu
}

interactive_mode() {
    local stay_in_menu=true
    
    while $stay_in_menu; do
        clear
        list_nodes
        
        read -p "Select a node (or q to quit): " choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            # Check if this is a valid node number
            local nodes=()
            for dir in "$DEFAULT_DIR"/*; do
                if [ -d "$dir" ] && [ "$(basename "$dir")" != "cores" ]; then
                    nodes+=("$(basename "$dir")")
                fi
            done
            
            if [ "$choice" -ge 1 ] && [ "$choice" -le "${#nodes[@]}" ]; then
                local selected_node="${nodes[$((choice-1))]}"
                local stay_in_node_menu=true
                
                while $stay_in_node_menu; do
                    if ! show_node_menu "$selected_node"; then
                        stay_in_node_menu=false
                    fi
                done
            else
                print_error "Invalid option"
                sleep 1
            fi
        elif [[ "$choice" == "q" || "$choice" == "Q" ]]; then
            stay_in_menu=false
        else
            print_error "Invalid option"
            sleep 1
        fi
    done
}

# Command mode functions
cmd_restart() {
    local node=$1
    local service_name="marznode-$node"
    
    echo "Restarting $service_name..."
    # First try a normal stop
    systemctl stop $service_name
    
    # Wait for up to 1 second for graceful shutdown
    sleep 1
    
    # Only use force if needed
    if systemctl is-active --quiet $service_name; then
        echo "Service still running, using force stop..."
        systemctl stop --force $service_name
        sleep 1
    fi
    
    systemctl reset-failed $service_name 2>/dev/null
    systemctl start $service_name
}

cmd_stop() {
    local node=$1
    local service_name="marznode-$node"
    
    echo "Stopping $service_name..."
    # First try a normal stop
    systemctl stop $service_name
    
    # Wait for up to 1 second for graceful shutdown
    sleep 1
    
    # Check if service stopped
    if ! systemctl is-active --quiet $service_name; then
        echo "Service stopped successfully."
        exit 0
    fi
    
    # Use force if needed after waiting
    echo "Service still running, using force stop..."
    systemctl stop --force $service_name
    sleep 1
    
    # As a last resort, use kill
    if systemctl is-active --quiet $service_name; then
        echo "WARNING: Service still running, using kill command..."
        systemctl kill $service_name
    fi
}

# Main execution logic
if [ -z "$NODE_NAME" ]; then
    # If no arguments, run in interactive mode
    interactive_mode
    exit 0
fi

# Direct command mode
SERVICE_NAME="marznode-$NODE_NAME"

if [ -z "$COMMAND" ]; then
    echo "Usage: marznode <node-name> restart | start | stop | status"
    exit 1
fi

case "$COMMAND" in
    restart) 
        cmd_restart "$NODE_NAME"
        ;;
    start) 
        systemctl start $SERVICE_NAME 
        ;;
    stop) 
        cmd_stop "$NODE_NAME"
        ;;
    status) 
        systemctl status $SERVICE_NAME 
        ;;
    *)
        echo "Usage: marznode <node-name> restart | start | stop | status"
        exit 1 
        ;;
esac
EOF

sudo chmod +x /usr/local/bin/marznode

print_success "Script installed successfully at /usr/local/bin/marznode"
print_success "You can control the service with: marznode $node_directory restart|start|stop|status"


