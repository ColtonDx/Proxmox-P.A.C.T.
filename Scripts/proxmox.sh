#!/bin/bash

#This is the script that will be run on the Proxmox server to create the VM templates.

# Load configuration file
source ./workingdir/Options.ini

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
            qm set "$1" --ide2 "${5}:cloudinit"
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

# Ubuntu 22.04 LTS
if [ "$Download_UBUNTU_22_04_LTS" == "Y" ]; then
    qm destroy $((nVMID + 111))
    qm destroy $((nVMID + 11))
    
    echo "Creating base Ubuntu 22.04 Template"
    create_template $((nVMID + 11)) "Template-Ubuntu-22.04" "ubuntu-22.04-template.img" "https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img" "$PROXMOX_STORAGE_POOL"
 fi

# Ubuntu 24.04
if [ "$Download_UBUNTU_24_04" == "Y" ]; then
    qm destroy $((nVMID + 112))
    qm destroy $((nVMID + 12))    
    
    echo "Creating base Ubuntu 24.04 Template"
    create_template $((nVMID + 12)) "Template-Ubuntu-24.04" "ubuntu-24.04-template.img" "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img" "$PROXMOX_STORAGE_POOL"
fi

# Fedora 39
if [ "$Download_FEDORA_39" == "Y" ]; then
    qm destroy $((nVMID + 121))
    qm destroy $((nVMID + 21))    
    
    echo "Creating base Fedora 39 Template"
    create_template $((nVMID + 21)) "Template-Fedora-39" "fedora-39-template.qcow2" "https://fedora.mirror.constant.com/fedora/linux/releases/39/Cloud/x86_64/images/Fedora-Cloud-Base-39-1.5.x86_64.qcow2" "$PROXMOX_STORAGE_POOL"
fi

# Fedora 40
if [ "$Download_FEDORA_40" == "Y" ]; then
    qm destroy $((nVMID + 122))
    qm destroy $((nVMID + 22))

    echo "Creating base Fedora 40 Template"
    create_template $((nVMID + 22)) "Template-Fedora-40" "fedora-40-template.qcow2" "https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-Generic.x86_64-40-1.14.qcow2" "$PROXMOX_STORAGE_POOL"
fi

# Rocky Linux 9
if [ "$Download_ROCKY_LINUX_9" == "Y" ]; then
    qm destroy $((nVMID + 131))
    qm destroy $((nVMID + 31))    
    
    echo "Creating base Rocky 9 Template"
    create_template $((nVMID + 31)) "Template-Rocky-9" "rocky-9-template.qcow2" "http://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2" "$PROXMOX_STORAGE_POOL"
fi
