#!/bin/bash

################################################################################
# Proxmox-P.A.C.T. Cleanup Script
#
# Cleans up temporary artifacts after build process. Optionally deletes
# intermediate build VMs if --cleanup-vms flag is provided.
#
# Usage: ./cleanup.sh [OPTIONS]
#
# Options:
#   --cleanup-vms  Delete intermediate build VMs (from base VMID 800)
#   --vmid=NUM     Base VMID (default: 800)
#   --help         Show this help and exit
#
################################################################################

# Defaults
nVMID=800
CLEANUP_VMS=false

print_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --cleanup-vms    Delete intermediate build VMs (default: false)
  --vmid=NUM       Base VMID for VMs to delete (default: 800)
  --help           Show this help and exit

Notes:
  - Without --cleanup-vms, only removes working directory
  - --cleanup-vms will destroy VMs at: vmid+1, vmid+2, vmid+3, vmid+11, vmid+12, vmid+13, vmid+21, vmid+31
EOF
}

for arg in "$@"; do
    case "$arg" in
        --cleanup-vms) CLEANUP_VMS=true ;;
        --vmid=*) nVMID="${arg#*=}" ;;
        --help) print_usage; exit 0 ;;
        *) echo "Unknown option: $arg"; print_usage; exit 1 ;;
    esac
done

echo "Cleaning up build artifacts (nVMID=$nVMID, cleanup_vms=$CLEANUP_VMS)..."

if [ "$CLEANUP_VMS" = true ]; then
    echo "Destroying intermediate build VMs..."
    declare -a DISTRO_OFFSETS=(1 2 3 11 12 13 21 31)
    for offset in "${DISTRO_OFFSETS[@]}"; do
        vmid=$((nVMID + offset))
        echo "  Destroying VMID $vmid..."
        qm destroy "$vmid" 2>/dev/null || true
    done
fi

echo "Removing working directory..."
rm -rf ./workingdir
echo "Cleanup complete"
