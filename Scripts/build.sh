#!/bin/bash

#### Start the Build ####
# Load configuration file (required)
if [ ! -f ./Options.ini ]; then
    echo "Missing required file: Options.ini" >&2
    exit 1
fi
# shellcheck disable=SC1090
source ./Options.ini

if [ ! -f ./.env.local ]; then
    echo "Missing required file: .env.local" >&2
    exit 1
fi
# shellcheck disable=SC1090
source ./.env.local

#####################################################################################
###################FUNCTIONS
#####################################################################################

#Function to check what Images to customize with Packer.
start_packer() {

    # Debian 11
    if [ "$Download_DEBIAN_11" == "Y" ]; then
        packer_build debian11.pkr.hcl $((nVMID + 101))
    fi

    # Debian 12
    if [ "$Download_DEBIAN_12" == "Y" ]; then
        packer_build debian12.pkr.hcl $((nVMID + 102))
    fi

    # Debian 13
    if [ "$Download_DEBIAN_13" == "Y" ]; then
        packer_build debian13.pkr.hcl $((nVMID + 103))
    fi

    # Ubuntu 22.04 LTS
    if [ "$Download_UBUNTU_22_04_LTS" == "Y" ]; then
        packer_build ubuntu2204.pkr.hcl $((nVMID + 111))
    fi

    # Ubuntu 24.04
    if [ "$Download_UBUNTU_24_04" == "Y" ]; then

        packer_build ubuntu2404.pkr.hcl $((nVMID + 112))
    fi

    # Fedora 39
    if [ "$Download_FEDORA_39" == "Y" ]; then
        packer_build fedora39.pkr.hcl $((nVMID + 121))
    fi

    # Fedora 40
    if [ "$Download_FEDORA_40" == "Y" ]; then
        packer_build fedora40.pkr.hcl $((nVMID + 122))
    fi

    # Rocky Linux 9
    if [ "$Download_ROCKY_LINUX_9" == "Y" ]; then
        packer_build rocky9.pkr.hcl $((nVMID + 131))
    fi

}

#Function that runs Packer Build with Environment variable parameters
packer_build() {
    packer init "./Packer/Templates/$1"
    packer build -var-file=./Packer/Variables/vars.json \
        -var "proxmox_host_node=$PROXMOX_HOST_NODE" \
        -var "proxmox_api_url=https://${PROXMOX_HOST}:8006/api2/json" \
        -var "proxmox_api_token_id=$PROXMOX_API_TOKEN_ID" \
        -var "proxmox_api_token_secret=$PROXMOX_API_TOKEN_SECRET" \
        -var "vmid=$2" \
        -var "storage_pool=$PROXMOX_STORAGE_POOL" \
        "./Packer/Templates/$1"
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

# Define the packages to install
PACKAGES="gnupg2 ansible software-properties-common lsb-release sshpass unzip wget node.js git"

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

# Install Packer
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

#####################################################################################
################### MAIN
#####################################################################################

#CUSTOM ANSIBLE REPO
if [ "$CUSTOM_ANSIBLE_REPO" != "N" ]; then
    echo "CUSTOM_ANSIBLE_REPO is set. Preparing to update playbooks."
    # Delete all contents of ./Ansible/Playbooks/
    rm -rf ./Ansible
    # Download the contents of the specified repository into ./Ansible/Playbooks/
    echo "Downloading contents from $CUSTOM_ANSIBLE_REPO"
    git clone "$CUSTOM_ANSIBLE_REPO" ./Ansible
    echo "Playbooks updated successfully."
fi

# Check if CUSTOM_PACKER_REPO is set to anything other than "N"
if [ "$CUSTOM_PACKER_REPO" != "N" ]; then
    echo "CUSTOM_PACKER_REPO is set. Preparing to update Packer templates."
    # Delete all contents of ./Packer/Templates/
    rm -rf ./Packer
    # Download the contents of the specified repository into ./Packer/Templates/
    echo "Downloading contents from $CUSTOM_PACKER_REPO"
    git clone "$CUSTOM_PACKER_REPO" ./Packer
    echo "Packer templates updated successfully."
fi

# Checking if we are using Password Authentication, then starting build
if [ "$PROXMOX_SSH_AUTH_METHOD" = "password" ]; then
    echo "Starting build using password authentication"
    # Copy files to the remote host
    sshpass -p "$PROXMOX_SSH_PASSWORD" scp -o StrictHostKeyChecking=no ./Options.ini ./Scripts/proxmox.sh ./Scripts/cleanup.sh $PROXMOX_SSH_USER@$PROXMOX_HOST:./workingdir
    # SSH to the remote host and run proxmox.sh
    sshpass -p "$PROXMOX_SSH_PASSWORD" ssh -o StrictHostKeyChecking=no $PROXMOX_SSH_USER@$PROXMOX_HOST << 'EOF'
    chmod +x ./workingdir/proxmox.sh
    ./workingdir/proxmox.sh
EOF
    start_packer
    # SSH to the remote host and run cleanup.sh
    sshpass -p "$PROXMOX_SSH_PASSWORD" ssh -o StrictHostKeyChecking=no $PROXMOX_SSH_USER@$PROXMOX_HOST << 'EOF'
    chmod +x ./workingdir/cleanup.sh
    ./workingdir/cleanup.sh
EOF

# Checking if we are using Pubkey authentication, then starting build
elif [ "$PROXMOX_SSH_AUTH_METHOD" = "pubkey" ]; then
    echo "Starting build using public key authentication"
    # Write private key to a secure temp file and ensure it's removed on exit
    TMP_KEY="$(mktemp --tmpdir id_rsa.XXXXXX)"
    printf '%s\n' "$PROXMOX_SSH_PRIVATE_KEY" > "$TMP_KEY"
    chmod 600 "$TMP_KEY"
    trap 'rm -f "$TMP_KEY"' EXIT

    scp -i "$TMP_KEY" -o StrictHostKeyChecking=no ./Options.ini ./Scripts/proxmox.sh ./Scripts/cleanup.sh $PROXMOX_SSH_USER@$PROXMOX_HOST:./workingdir
    # SSH to the remote host and run proxmox.sh
    ssh -i "$TMP_KEY" -o StrictHostKeyChecking=no $PROXMOX_SSH_USER@"$PROXMOX_HOST" << 'EOF'
    chmod +x ./workingdir/proxmox.sh
    ./workingdir/proxmox.sh
EOF

    start_packer
    # SSH to the remote host and run cleanup.sh
    ssh -i "$TMP_KEY" -o StrictHostKeyChecking=no $PROXMOX_SSH_USER@"$PROXMOX_HOST" << 'EOF'
    chmod +x ./workingdir/cleanup.sh    
    ./workingdir/cleanup.sh
EOF
    # TMP_KEY will be removed by the EXIT trap

else
    echo "Unknown authentication method: $PROXMOX_SSH_AUTH_METHOD - Exiting"
    exit 1
fi
