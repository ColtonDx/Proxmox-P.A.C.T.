#!/bin/bash

################################################################################
# Proxmox-P.A.C.T. Build Script
#
# This script orchestrates the complete build process for creating Proxmox VM
# templates and customizing them with Packer. It supports:
#
#  - Multiple deployment modes:
#    * SSH mode (default): SSH to Proxmox and run proxmox.sh to create templates
#    * Ansible mode: Skip SSH and use Ansible-only playbooks
#    * Interactive mode: Prompt user for mode selection
#
#  - Conditional Packer builds: Optionally run Packer to customize VM images
#
#  - Flexible configuration:
#    * Load from config file via --config=PATH (default: Options.ini)
#    * Load from environment variables via --env
#
#  - Smart dependency management:
#    * Installs only required packages based on selected options
#    * Installs Packer only if --packer is specified
#
# Usage: ./build.sh [OPTIONS]
#
# Options:
#   --ansible       Use Ansible-only mode (skip SSH to Proxmox)
#   --packer        Run Packer builds for image customization
#   --rebuild       Delete existing VMs before rebuilding (destructive)
#   --interactive   Prompt user for deployment mode and Packer option
#   --config=PATH   Load variables from config file (default: Options.ini)
#   --env           Load variables from environment variables
#   --help          Show help message
#
################################################################################

#####################################################################################
################### CLI OPTION PARSING
#####################################################################################

# Default flags and values
USE_ANSIBLE=false
RUN_PACKER=false
REBUILD=false
INTERACTIVE_MODE=false
USE_ENV_VARS=false
CONFIG_FILE="./Options.ini"
SSH_PRIVATE_KEY_PATH=""

print_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --ansible         Skip SSH to Proxmox and skip running proxmox.sh. Use Ansible only.
  --packer          Run Packer builds for image customization.
  --rebuild         Delete existing VMs before building new ones (destructive).
  --interactive     Prompt the user to choose between SSH and Ansible, and whether to run Packer.
  --config=PATH     Path to config file (default: ./Options.ini). Ignored if --env is set.
  --env             Load all variables from environment variables instead of config file.
  --ssh-key=PATH    Path to SSH private key for authentication. If not provided, password auth is used.
  --help            Show this help and exit

Notes:
  - If --interactive is set, --ansible and --packer are ignored.
  - Without any flags, defaults to SSH mode (password auth) without Packer.
  - If --env is set, --config is ignored.
  - Without --rebuild, existing VMs at target VMIDs are preserved (safer).
EOF
}

# Parse CLI arguments
for arg in "$@"; do
    case "$arg" in
        --ansible)
            USE_ANSIBLE=true
            ;;
        --packer)
            RUN_PACKER=true
            ;;
        --rebuild)
            REBUILD=true
            ;;
        --interactive)
            INTERACTIVE_MODE=true
            ;;
        --config=*)
            CONFIG_FILE="${arg#*=}"
            ;;
        --env)
            USE_ENV_VARS=true
            ;;
        --ssh-key=*)
            SSH_PRIVATE_KEY_PATH="${arg#*=}"
            ;;
        --help)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            print_usage
            exit 1
            ;;
    esac
done

# Load configuration file or environment variables
if [ "$USE_ENV_VARS" = true ]; then
    echo "Loading variables from environment variables..."
else
    # Load config file (default or custom)
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Missing required file: $CONFIG_FILE" >&2
        exit 1
    fi
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

# Set defaults for unset variables
: "${PROXMOX_SSH_AUTH_METHOD:=password}"
: "${PROXMOX_SSH_USER:=root}"
: "${PROXMOX_HOST:=pve.local}"
: "${PROXMOX_STORAGE_POOL:=local-lvm}"
: "${nVMID:=800}"

# Handle interactive mode
if [ "$INTERACTIVE_MODE" = true ]; then
    echo "=== Interactive Mode ==="
    
    # Ask about deployment mode
    read -p "Use Ansible only (skip SSH to Proxmox)? (y/n): " -r choice_ansible
    if [[ "$choice_ansible" =~ ^[Yy]$ ]]; then
        USE_ANSIBLE=true
    fi
    
    # Ask about Packer
    read -p "Run Packer builds for image customization? (y/n): " -r choice_packer
    if [[ "$choice_packer" =~ ^[Yy]$ ]]; then
        RUN_PACKER=true
    fi
    
    # Ask about rebuild
    read -p "Delete existing VMs before building (rebuild)? (y/n): " -r choice_rebuild
    if [[ "$choice_rebuild" =~ ^[Yy]$ ]]; then
        REBUILD=true
    fi
    
    # Ask for configuration file path
    read -p "Path to config file (press Enter for default './Options.ini'): " -r config_file_input
    if [ -n "$config_file_input" ]; then
        CONFIG_FILE="$config_file_input"
        USE_ENV_VARS=false
    else
        # Ask if user wants to use environment variables instead
        read -p "Use environment variables instead of config file? (y/n): " -r choice_env
        if [[ "$choice_env" =~ ^[Yy]$ ]]; then
            USE_ENV_VARS=true
        fi
    fi
    
    # Ask for SSH key path if not using Ansible
    if [ "$USE_ANSIBLE" = false ]; then
        read -p "SSH private key path (press Enter for password authentication): " -r ssh_key_input
        if [ -n "$ssh_key_input" ]; then
            SSH_PRIVATE_KEY_PATH="$ssh_key_input"
        fi
    fi
    
    # Ask for VMID
    read -p "Base VMID (press Enter for default 800): " -r vmid_input
    if [ -n "$vmid_input" ]; then
        nVMID="$vmid_input"
    fi
    
    # Ask for storage pool
    read -p "Storage pool (press Enter for default 'local-lvm'): " -r storage_input
    if [ -n "$storage_input" ]; then
        PROXMOX_STORAGE_POOL="$storage_input"
    fi
    
    echo ""
fi

# Validate required variables for Packer
if [ "$RUN_PACKER" = true ]; then
    if [ -z "$PACKER_TOKEN_ID" ] || [ -z "$PACKER_TOKEN_SECRET" ]; then
        echo "Error: PACKER_TOKEN_ID and PACKER_TOKEN_SECRET are required when using --packer" >&2
        exit 1
    fi
fi

# Validate required variables for Packer
if [ "$RUN_PACKER" = true ]; then
    if [ -z "$PACKER_TOKEN_ID" ] || [ -z "$PACKER_TOKEN_SECRET" ]; then
        echo "Error: PACKER_TOKEN_ID and PACKER_TOKEN_SECRET are required when using --packer" >&2
        exit 1
    fi
fi

# Display configuration
echo "Build Configuration:"
echo "  Use Ansible: $USE_ANSIBLE"
echo "  Run Packer: $RUN_PACKER"
echo "  Rebuild VMs: $REBUILD"
echo "  Using environment variables: $USE_ENV_VARS"
if [ "$USE_ENV_VARS" = false ]; then
    echo "  Config file: $CONFIG_FILE"
fi
echo ""

#####################################################################################
###################FUNCTIONS
#####################################################################################

#Function to check what Images to customize with Packer.
start_packer() {
    # Array of distros: "VAR_NAME|distro_name|vmid_offset"
    local distros=(
        "Download_DEBIAN_11|debian11|101"
        "Download_DEBIAN_12|debian12|102"
        "Download_DEBIAN_13|debian13|103"
        "Download_UBUNTU_2204|ubuntu2204|111"
        "Download_UBUNTU_2205|ubuntu2205|114"
        "Download_UBUNTU_2404|ubuntu2404|112"
        "Download_UBUNTU_2504|ubuntu2504|113"
        "Download_FEDORA_41|fedora41|121"
        "Download_ROCKY_LINUX_9|rocky9|131"
    )

    for distro in "${distros[@]}"; do
        IFS='|' read -r var_name distro_name vmid_offset <<< "$distro"
        if [ "${!var_name}" == "Y" ]; then
            packer_build "$distro_name" $((nVMID + vmid_offset))
        fi
    done
}

#Function that runs Packer Build with Environment variable parameters
packer_build() {
    local distro_name="$1"
    local vmid="$2"
    
    packer init "./Packer/Templates/universal.pkr.hcl"
    packer build -var-file=./Packer/Variables/vars.json \
        -var "proxmox_host_node=$PROXMOX_HOST_NODE" \
        -var "proxmox_api_url=https://${PROXMOX_HOST}:8006/api2/json" \
        -var "proxmox_api_token_id=$PACKER_TOKEN_ID" \
        -var "proxmox_api_token_secret=$PACKER_TOKEN_SECRET" \
        -var "vmid=$vmid" \
        -var "storage_pool=$PROXMOX_STORAGE_POOL" \
        -var "distro=$distro_name" \
        "./Packer/Templates/universal.pkr.hcl"
}

# Detect the distribution of the runner
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Unsupported distribution"
    exit 1
fi

#####################################################################################
###################REQUIREMENTS
#####################################################################################

# Build package list based on selected options
PACKAGES="gnupg2 software-properties-common lsb-release node.js"

# Add ansible only if using Ansible mode
if [ "$USE_ANSIBLE" = true ]; then
    PACKAGES="$PACKAGES ansible"
fi

# Add sshpass only if NOT using Ansible mode
if [ "$USE_ANSIBLE" = false ]; then
    PACKAGES="$PACKAGES sshpass"
fi

# Add wget, unzip, git only if running Packer
if [ "$RUN_PACKER" = true ]; then
    PACKAGES="$PACKAGES wget unzip git"
fi

# Install packages based on distribution
case "$OS" in
    ubuntu|debian)
        sudo apt-get update > /dev/null 2>&1
        sudo apt-get install -y $PACKAGES > /dev/null 2>&1
        ;;
    centos|rocky|almalinux|fedora|rhel)
        sudo dnf install -y $PACKAGES > /dev/null 2>&1
        ;;
    opensuse|sles)
        sudo zypper install -y $PACKAGES > /dev/null 2>&1
        ;;
    *)
        echo "Unsupported distribution: $OS"
        exit 1
        ;;
esac

# Install Packer only if --packer option is enabled
if [ "$RUN_PACKER" = true ]; then
    if ! command -v packer &> /dev/null
    then
        echo "Packer is not installed. Installing Packer..."
        # Download Packer
        wget https://releases.hashicorp.com/packer/1.7.8/packer_1.7.8_linux_amd64.zip > /dev/null 2>&1
        # Unzip the downloaded file
        unzip packer_1.7.8_linux_amd64.zip > /dev/null 2>&1
        # Move the Packer binary to /usr/local/bin
        sudo mv packer /usr/local/bin/
        # Clean up the zip file
        rm packer_1.7.8_linux_amd64.zip
        echo "Packer installed successfully."
    else
        echo "Packer is already installed."
    fi
fi

#####################################################################################
################### MAIN
#####################################################################################

# Skip SSH and proxmox.sh if using Ansible-only mode
if [ "$USE_ANSIBLE" = true ]; then
    echo "Ansible-only mode: Skipping SSH connection to Proxmox and proxmox.sh execution"
else
    # Build proxmox.sh arguments based on configuration
    PROXMOX_SCRIPT_ARGS="--vmid=$nVMID --storage=$PROXMOX_STORAGE_POOL"
    
    # Add rebuild flag if enabled
    if [ "$REBUILD" = true ]; then
        PROXMOX_SCRIPT_ARGS="$PROXMOX_SCRIPT_ARGS --rebuild"
    fi
    
    # Build --build argument based on which distros are enabled
    BUILD_LIST=""
    [ "$Download_DEBIAN_11" = "Y" ] && BUILD_LIST="${BUILD_LIST}debian11,"
    [ "$Download_DEBIAN_12" = "Y" ] && BUILD_LIST="${BUILD_LIST}debian12,"
    [ "$Download_DEBIAN_13" = "Y" ] && BUILD_LIST="${BUILD_LIST}debian13,"
    [ "$Download_UBUNTU_2204" = "Y" ] && BUILD_LIST="${BUILD_LIST}ubuntu2204,"
    [ "$Download_UBUNTU_2205" = "Y" ] && BUILD_LIST="${BUILD_LIST}ubuntu2205,"
    [ "$Download_UBUNTU_2404" = "Y" ] && BUILD_LIST="${BUILD_LIST}ubuntu2404,"
    [ "$Download_UBUNTU_2504" = "Y" ] && BUILD_LIST="${BUILD_LIST}ubuntu2504,"
    [ "$Download_FEDORA_41" = "Y" ] && BUILD_LIST="${BUILD_LIST}fedora41,"
    [ "$Download_ROCKY_LINUX_9" = "Y" ] && BUILD_LIST="${BUILD_LIST}rocky9,"
    
    # Remove trailing comma
    BUILD_LIST="${BUILD_LIST%,}"
    
    # Add build list to arguments if not empty
    if [ -n "$BUILD_LIST" ]; then
        PROXMOX_SCRIPT_ARGS="$PROXMOX_SCRIPT_ARGS --build=$BUILD_LIST"
    fi
    
    # Determine if using key-based authentication
    if [ -n "$SSH_PRIVATE_KEY_PATH" ]; then
        # Using private key authentication
        echo "Starting build using public key authentication"
        # Verify private key file exists
        if [ ! -f "$SSH_PRIVATE_KEY_PATH" ]; then
            echo "Private key file not found: $SSH_PRIVATE_KEY_PATH" >&2
            exit 1
        fi
        
        scp -i "$SSH_PRIVATE_KEY_PATH" -o StrictHostKeyChecking=no ./Scripts/proxmox.sh $PROXMOX_SSH_USER@$PROXMOX_HOST:./workingdir
        # SSH to the remote host and run proxmox.sh with arguments
        ssh -i "$SSH_PRIVATE_KEY_PATH" -o StrictHostKeyChecking=no $PROXMOX_SSH_USER@"$PROXMOX_HOST" << EOF
        chmod +x ./workingdir/proxmox.sh
        ./workingdir/proxmox.sh $PROXMOX_SCRIPT_ARGS
EOF
    else
        # Using password authentication
        echo "Starting build using password authentication"
        # Copy files to the remote host
        sshpass -p "$PROXMOX_SSH_PASSWORD" scp -o StrictHostKeyChecking=no ./Scripts/proxmox.sh $PROXMOX_SSH_USER@$PROXMOX_HOST:./workingdir
        # SSH to the remote host and run proxmox.sh with arguments
        sshpass -p "$PROXMOX_SSH_PASSWORD" ssh -o StrictHostKeyChecking=no $PROXMOX_SSH_USER@$PROXMOX_HOST << EOF
        chmod +x ./workingdir/proxmox.sh
        ./workingdir/proxmox.sh $PROXMOX_SCRIPT_ARGS
EOF
    fi
fi

# Run Packer if enabled
if [ "$RUN_PACKER" = true ]; then
    echo "Running Packer builds..."
    start_packer
else
    echo "Packer builds skipped"
fi
