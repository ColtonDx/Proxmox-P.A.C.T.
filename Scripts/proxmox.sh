#!/bin/bash

#This is the script that will be run on the Proxmox server to create the VM templates.

# --- CLI parameter handling ---
# Defaults if not provided on the command line
DEFAULT_VMID=800
DEFAULT_STORAGE="local-lvm"

# Define distro metadata: id|name|vmid_offset|filename|download_url
# The id field is used for filtering (debian11, ubuntu2404, etc.)
declare -a DISTROS=(
    "debian11|Debian-11|1|debian-11-template.qcow2|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-genericcloud-amd64.qcow2"
    "debian12|Debian-12|2|debian-12-template.qcow2|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
    "debian13|Debian-13|3|debian-13-template.qcow2|https://cloud.debian.org/images/cloud/trixie/daily/latest/debian-13-genericcloud-amd64-daily.qcow2"
    "ubuntu2204|Ubuntu-2204|11|ubuntu-2204-template.img|https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
    "ubuntu2404|Ubuntu-2404|12|ubuntu-2404-template.img|https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
    "ubuntu2504|Ubuntu-2504|13|ubuntu-2504-template.img|https://cloud-images.ubuntu.com/releases/plucky/release/ubuntu-25.04-server-cloudimg-amd64.img"
    "fedora41|Fedora-41|21|fedora-41-template.qcow2|https://fedora.mirror.constant.com/fedora/linux/releases/41/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-41-1.4.x86_64.qcow2"
    "rocky9|Rocky-9|31|rocky-9-template.qcow2|http://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2"
)

# Map of distro groups to their individual IDs
declare -A DISTRO_GROUPS=(
    [debian]="debian11 debian12 debian13"
    [ubuntu]="ubuntu2204 ubuntu2404 ubuntu2504"
    [all]="debian11 debian12 debian13 ubuntu2204 ubuntu2404 ubuntu2504 fedora41 rocky9"
)

print_usage() {
        cat <<EOF
Usage: $0 [--vmid=800] [--storage=local-lvm] [--build=LIST] [--rebuild] [--packer-enabled]

Options:
    --vmid=NUM        Base VMID to use. Defaults to ${DEFAULT_VMID}.
    --storage=NAME    Storage pool to use. Defaults to ${DEFAULT_STORAGE}.
    --build=LIST      Comma-separated list of distros to build. Special values:
                        all      - build every distro (default)
                        debian   - debian11, debian12, debian13
                        ubuntu   - ubuntu2204, ubuntu2404, ubuntu2504
                      Individual names: debian11, debian12, debian13, ubuntu2204, ubuntu2404, ubuntu2504, fedora41, rocky9
    --rebuild         Delete existing VMs at target VMIDs before building (destructive).
                      Without this flag, existing VMs are preserved.
    --packer-enabled  Packer will be used for customization. Checks both base and packer VMIDs.
    --help            Show this help and exit
EOF
}

# Defaults (may be overridden by Options.ini earlier)
VMID="${DEFAULT_VMID}"
STORAGE="${PROXMOX_STORAGE:-$DEFAULT_STORAGE}"
BUILD_LIST="all"
REBUILD=false
PACKER_ENABLED=false

for arg in "$@"; do
    case "$arg" in
        --vmid=*) VMID="${arg#*=}" ;;
        --storage=*) STORAGE="${arg#*=}" ;;
        --build=*) BUILD_LIST="${arg#*=}" ;;
        --rebuild) REBUILD=true ;;
        --packer-enabled) PACKER_ENABLED=true ;;
        --help) print_usage; exit 0 ;;
        *) echo "Unknown option: $arg"; print_usage; exit 1 ;;
    esac
done

# Apply parsed values
VMID_BASE="${VMID}"
STORAGE_POOL="${STORAGE}"

# Parse build list and populate selected distros
SELECTED_DISTROS=""
if [ -z "${BUILD_LIST}" ] || [ "${BUILD_LIST}" = "all" ]; then
    SELECTED_DISTROS="${DISTRO_GROUPS[all]}"
else
    # Support comma or space separated list
    items="$(echo "$BUILD_LIST" | tr ',' ' ')"
    for item in $items; do
        if [ -n "${DISTRO_GROUPS[$item]}" ]; then
            # It's a group (debian, ubuntu, etc.)
            SELECTED_DISTROS="${SELECTED_DISTROS} ${DISTRO_GROUPS[$item]}"
        else
            # Check if it's a valid individual distro ID
            if [[ " debian11 debian12 debian13 ubuntu2204 ubuntu2404 ubuntu2504 fedora41 rocky9 " =~ " $item " ]]; then
                SELECTED_DISTROS="${SELECTED_DISTROS} $item"
            else
                echo "Warning: unknown build item '$item' - ignoring" >&2
            fi
        fi
    done
fi

# Remove duplicates and normalize spacing
SELECTED_DISTROS="$(echo "$SELECTED_DISTROS" | tr ' ' '\n' | sort -u | tr '\n' ' ' | xargs)"

echo "Using VMID_BASE=${VMID_BASE}, storage=${STORAGE_POOL}, build='${BUILD_LIST}', selected='${SELECTED_DISTROS}', rebuild=${REBUILD}, packer-enabled=${PACKER_ENABLED}"

# Create and configure a VM template
create_template() {
    local vmid="$1"
    local template_name="$2"
    local filename="$3"
    local download_url="$4"
    local storage="$5"
    
    echo "Downloading the Image"
    curl -L -o ./workingdir/"$filename" "$download_url" > /dev/null 2>&1
    
    echo "Installing Qemu-Guest-Agent to image"
    virt-customize -a ./workingdir/"$filename" --install bash-completion > /dev/null 2>&1
    virt-customize -a ./workingdir/"$filename" --install qemu-guest-agent > /dev/null 2>&1
    
    echo "Creating template $template_name (VMID: $vmid)"
    qm create "$vmid" --name "$template_name" --ostype l26
    qm set "$vmid" --net0 virtio,bridge=vmbr0
    qm set "$vmid" --serial0 socket --vga serial0
    qm set "$vmid" --memory 1024 --cores 4 --cpu host
    qm set "$vmid" --scsi0 "${storage}:0,import-from=/root/workingdir/$filename,discard=on" > /dev/null 2>&1
    qm set "$vmid" --boot order=scsi0 --scsihw virtio-scsi-single
    qm set "$vmid" --agent enabled=1,fstrim_cloned_disks=1
    qm set "$vmid" --ide3 "${storage}:cloudinit"
    qm disk resize "$vmid" scsi0 8G
    qm template "$vmid"
}

# Check if a VMID already exists
check_vmid_exists() {
    local vmid="$1"
    if qm status "$vmid" &>/dev/null; then
        return 0  # VMID exists
    else
        return 1  # VMID does not exist
    fi
}

# Handle template rebuild/destruction (base + customization VMIDs)
manage_vmid_lifecycle() {
    local vmid="$1"
    local offset="$2"
    
    if [ "$REBUILD" = true ]; then
        qm destroy "$vmid" 2>/dev/null
        # Only destroy packer VMID if packer is enabled
        if [ "$PACKER_ENABLED" = true ]; then
            qm destroy "$((vmid + 100))" 2>/dev/null
        fi
    else
        # Check base VMID
        if check_vmid_exists "$vmid"; then
            echo "Error: VMID $vmid is already in use. Use --rebuild to replace it, or choose a different nVMID." >&2
            return 1
        fi
        # Check packer VMID only if packer is enabled
        if [ "$PACKER_ENABLED" = true ]; then
            if check_vmid_exists "$((vmid + 100))"; then
                echo "Error: Packer VMID $((vmid + 100)) is already in use. Use --rebuild to replace it, or choose a different nVMID." >&2
                return 1
            fi
        fi
    fi
    return 0
}

apt-get install libguestfs-tools -y > /dev/null 2>&1

# Process all selected distros
for distro_config in "${DISTROS[@]}"; do
    IFS='|' read -r distro_id distro_name offset filename url <<< "$distro_config"
    
    # Check if this distro was selected for building
    if [[ ! " $SELECTED_DISTROS " =~ " $distro_id " ]]; then
        continue
    fi
    
    vmid=$((VMID_BASE + offset))
    template_name="Template-${distro_name}"
    
    # Handle VMID lifecycle (destroy or validate)
    if ! manage_vmid_lifecycle "$vmid" "$offset"; then
        exit 1
    fi
    
    # Build the template
    echo "Creating base ${distro_name} Template"
    create_template "$vmid" "$template_name" "$filename" "$url" "$STORAGE_POOL"
done
