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
if ! command -v rye &> /dev/null; then
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

# Setting up shared core directory
print_info "Setting up shared cores directory..."
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

# Install cores if they don't exist
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
    print_info "Xray core already installed in shared directory."
fi

if [ ! -f "/opt/marznode/cores/sing-box/sing-box" ]; then
    # sing box
    print_info "Which version of sing-box core do you want? (e.g., 1.10.3) (leave blank for latest): "
    read -r version
    latest=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep '"tag_name"' | cut -d '"' -f 4)
    sversion=${version:-$latest}

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
    print_info "Sing-box core already installed in shared directory."
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
    print_info "Hysteria core already installed in shared directory."
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
    
    # Configure hysteria.yaml with domain and port
    cat << EOF > /opt/marznode/cores/hysteria/config.yaml
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
  dir: /etc/hysteria/acme/

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
XRAY_EXECUTABLE_PATH=/opt/marznode/cores/xray/xray
XRAY_ASSETS_PATH=/opt/marznode/cores/xray
XRAY_CONFIG_PATH=/opt/marznode/cores/xray/config.json
#XRAY_VLESS_REALITY_FLOW=xtls-rprx-vision
#XRAY_RESTART_ON_FAILURE=True
#XRAY_RESTART_ON_FAILURE_INTERVAL=5

HYSTERIA_ENABLED=$hys_enable
HYSTERIA_EXECUTABLE_PATH=/opt/marznode/cores/hysteria/hysteria
HYSTERIA_CONFIG_PATH=/opt/marznode/cores/hysteria/config.yaml

SING_BOX_ENABLED=$sing_enable
SING_BOX_EXECUTABLE_PATH=/opt/marznode/cores/sing-box/sing-box
SING_BOX_CONFIG_PATH=/opt/marznode/cores/sing-box/config.json
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
DEFAULT_DIR="/opt/marznode"
NODE_NAME="${1:-}"
COMMAND="$2"

if [ -z "$NODE_NAME" ] || [ -z "$COMMAND" ]; then
  echo "Usage: marznode <node-name> restart | start | stop | status"
  exit 1
fi

SERVICE_NAME="marznode-$NODE_NAME"

case "$COMMAND" in
    restart) 
        echo "Restarting $SERVICE_NAME..."
        # First try a normal stop
        systemctl stop $SERVICE_NAME
        
        # Wait for up to 1 second for graceful shutdown
        sleep 1
        
        # Only use force if needed
        if systemctl is-active --quiet $SERVICE_NAME; then
            echo "Service still running, using force stop..."
            systemctl stop --force $SERVICE_NAME
            sleep 1
        fi
        
        systemctl reset-failed $SERVICE_NAME 2>/dev/null
        systemctl start $SERVICE_NAME
        ;;
    start) 
        systemctl start $SERVICE_NAME 
        ;;
    stop) 
        echo "Stopping $SERVICE_NAME..."
        # First try a normal stop
        systemctl stop $SERVICE_NAME
        
        # Wait for up to 1 second for graceful shutdown
        sleep 1
        
        # Check if service stopped
        if ! systemctl is-active --quiet $SERVICE_NAME; then
            echo "Service stopped successfully."
            exit 0
        fi
        
        # Use force if needed after waiting
        echo "Service still running, using force stop..."
        systemctl stop --force $SERVICE_NAME
        sleep 1
        
        # As a last resort, use kill
        if systemctl is-active --quiet $SERVICE_NAME; then
            echo "WARNING: Service still running, using kill command..."
            systemctl kill $SERVICE_NAME
        fi
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


