#!/bin/bash

#This is the script that will be run on the Proxmox server to create the VM templates.

# Load configuration file
source ./workingdir/Options.ini

# --- CLI parameter handling ---
# Defaults if not provided on the command line
DEFAULT_VMID=800
DEFAULT_STORAGE="local-lvm"

# Read CLI args in the form `vmid=800` or `--vmid=800`, `storage=...`, `include=...` (supports `--build` and `-b` aliases)
print_usage() {
    cat <<EOF
Usage: $0 [vmid=800] [storage=local-lvm] [include=LIST]

Options:
  vmid=NUM, --vmid=NUM       Base VMID to use (sets nVMID). Defaults to ${DEFAULT_VMID}.
  storage=NAME, --storage=NAME
                             Storage pool to use (sets PROXMOX_STORAGE_POOL). Defaults to ${DEFAULT_STORAGE}.
    include=LIST, --include=LIST, --build=LIST, -b=LIST
                             Comma-separated list of images to build. Special values:
                               all (default) - build every image
                               debian        - debian11,debian12,debian13
                               ubuntu        - ubuntu2204,ubuntu2404,ubuntu2504
                             Individual names: debian11,debian12,debian13,ubuntu2204,ubuntu2404,ubuntu2504,fedora41,rocky9
  -h, --help                 Show this help and exit
EOF
}

# defaults (may be overridden by Options.ini earlier)
VMID="${DEFAULT_VMID}"
STORAGE="${PROXMOX_STORAGE_POOL:-$DEFAULT_STORAGE}"
INCLUDE="all"

for arg in "$@"; do
    case "$arg" in
        vmid=*|--vmid=*) VMID="${arg#*=}"; shift ;;
        storage=*|--storage=*) STORAGE="${arg#*=}"; shift ;;
        include=*|--include=*) INCLUDE="${arg#*=}"; shift ;;
        build=*|--build=*|-b=*) INCLUDE="${arg#*=}"; shift ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "Unknown option: $arg"; print_usage; exit 1 ;;
    esac
done

# Apply parsed values by overriding the variables used later in the script
nVMID="${VMID}"
PROXMOX_STORAGE_POOL="${STORAGE}"

# Normalize and decide which images to build. Default is all images unless include is set.
Download_DEBIAN_11="N"
Download_DEBIAN_12="N"
Download_DEBIAN_13="N"
Download_UBUNTU_2204="N"
Download_UBUNTU_2404="N"
Download_UBUNTU_2504="N"
Download_FEDORA_41="N"
Download_ROCKY_LINUX_9="N"

if [ -z "${INCLUDE}" ] || [ "${INCLUDE}" = "all" ]; then
    Download_DEBIAN_11="Y"
    Download_DEBIAN_12="Y"
    Download_DEBIAN_13="Y"
    Download_UBUNTU_2204="Y"
    Download_UBUNTU_2404="Y"
    Download_UBUNTU_2504="Y"
    Download_FEDORA_41="Y"
    Download_ROCKY_LINUX_9="Y"
else
    # support comma or space separated list
    items="$(echo "$INCLUDE" | tr ',' ' ' )"
    for it in $items; do
        case "$it" in
            debian)
                Download_DEBIAN_11="Y"; Download_DEBIAN_12="Y"; Download_DEBIAN_13="Y" ;;
            debian11) Download_DEBIAN_11="Y" ;;
            debian12) Download_DEBIAN_12="Y" ;;
            debian13) Download_DEBIAN_13="Y" ;;
            ubuntu)
                Download_UBUNTU_2204="Y"; Download_UBUNTU_2404="Y"; Download_UBUNTU_2504="Y" ;;
            ubuntu2204) Download_UBUNTU_2204="Y" ;;
            ubuntu2404) Download_UBUNTU_2404="Y" ;;
            ubuntu2504) Download_UBUNTU_2504="Y" ;;
            fedora|fedora41) Download_FEDORA_41="Y" ;;
            rocky|rocky9|rockylinux9) Download_ROCKY_LINUX_9="Y" ;;
            *) echo "Warning: unknown include item '$it' - ignoring" ;;
        esac
    done
fi

echo "Using nVMID=${nVMID}, storage=${PROXMOX_STORAGE_POOL}, include='${INCLUDE}'"
# --- end CLI parameter handling ---

create_template() {
            echo "Downloading the Image"
            curl -L -o ./workingdir/"$3" "$4" > /dev/null 2>&1
            echo "Checking that Virt-Customize is Installed"
            echo "Installing Qemu-Guest-Agent to image"
            virt-customize -a ./workingdir/"$3" --install bash-completion > /dev/null 2>&1
            virt-customize -a ./workingdir/"$3" --install qemu-guest-agent > /dev/null 2>&1
            echo "Creating template $2"
            qm create "$1" --name "$2" --ostype l26
            qm set "$1" --net0 virtio,bridge=vmbr0
            qm set "$1" --serial0 socket --vga serial0
            qm set "$1" --memory 1024 --cores 4 --cpu host
            qm set "$1" --scsi0 "${5}:0,import-from=/root/workingdir/$3,discard=on"  > /dev/null 2>&1
            qm set "$1" --boot order=scsi0 --scsihw virtio-scsi-single
            qm set "$1" --agent enabled=1,fstrim_cloned_disks=1
            qm set "$1" --ide3 "${5}:cloudinit"
            qm disk resize "$1" scsi0 8G
            qm template "$1"
        }

apt-get install libguestfs-tools -y > /dev/null 2>&1

# Debian 11
if [ "$Download_DEBIAN_11" == "Y" ]; then
    qm destroy $((nVMID + 1))
    qm destroy $((nVMID + 101))
    echo "Creating base Debian 11 Template"
    create_template $((nVMID + 1)) "Template-Debian-11" "debian-11-template.qcow2" "https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-genericcloud-amd64.qcow2" "$PROXMOX_STORAGE_POOL"
fi

# Debian 12
if [ "$Download_DEBIAN_12" == "Y" ]; then
    qm destroy $((nVMID + 2))
    qm destroy $((nVMID + 102))

    echo "Creating base Debian 12 Template"
    create_template $((nVMID + 2)) "Template-Debian-12" "debian-12-template.qcow2" "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2" "$PROXMOX_STORAGE_POOL"
fi

# Debian 13
if [ "$Download_DEBIAN_13" == "Y" ]; then
    qm destroy $((nVMID + 103))
    qm destroy $((nVMID + 3))

    echo "Creating base Debian 13 Template"
    create_template $((nVMID + 3)) "Template-Debian-13" "debian-13-template.qcow2" "https://cloud.debian.org/images/cloud/trixie/daily/latest/debian-13-genericcloud-amd64-daily.qcow2" "$PROXMOX_STORAGE_POOL"
fi

# Ubuntu 2204
if [ "$Download_UBUNTU_2204" == "Y" ]; then
    qm destroy $((nVMID + 111))
    qm destroy $((nVMID + 11))
    
    echo "Creating base Ubuntu 2204 Template"
    create_template $((nVMID + 11)) "Template-Ubuntu-2204" "ubuntu-2204-template.img" "https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img" "$PROXMOX_STORAGE_POOL"
 fi

# Ubuntu 2404
if [ "$Download_UBUNTU_2404" == "Y" ]; then
    qm destroy $((nVMID + 112))
    qm destroy $((nVMID + 12))    
    
    echo "Creating base Ubuntu 2404 Template"
    create_template $((nVMID + 12)) "Template-Ubuntu-2404" "ubuntu-2404-template.img" "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img" "$PROXMOX_STORAGE_POOL"
fi

# Ubuntu 2504
if [ "$Download_UBUNTU_2504" == "Y" ]; then
    qm destroy $((nVMID + 113))
    qm destroy $((nVMID + 13))    
    
    echo "Creating base Ubuntu 2504 Template"
    create_template $((nVMID + 13)) "Template-Ubuntu-2504" "ubuntu-2504-template.img" "https://cloud-images.ubuntu.com/releases/plucky/release/ubuntu-25.04-server-cloudimg-amd64.img" "$PROXMOX_STORAGE_POOL"
fi

# Fedora 41
if [ "$Download_FEDORA_41" == "Y" ]; then
    qm destroy $((nVMID + 121))
    qm destroy $((nVMID + 21))    
    
    echo "Creating base Fedora 41 Template"
    create_template $((nVMID + 21)) "Template-Fedora-41" "fedora-41-template.qcow2" "https://fedora.mirror.constant.com/fedora/linux/releases/41/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-41-1.4.x86_64.qcow2" "$PROXMOX_STORAGE_POOL"
fi

# Rocky Linux 9
if [ "$Download_ROCKY_LINUX_9" == "Y" ]; then
    qm destroy $((nVMID + 131))
    qm destroy $((nVMID + 31))    
    
    echo "Creating base Rocky 9 Template"
    create_template $((nVMID + 31)) "Template-Rocky-9" "rocky-9-template.qcow2" "http://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2" "$PROXMOX_STORAGE_POOL"
fi
