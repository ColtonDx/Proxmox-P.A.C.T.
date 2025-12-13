################################################################################
# Universal Proxmox VM Customization Template
#
# This Packer template can build images for multiple distributions by passing
# the 'distro' variable. Supported distros:
#   - debian11, debian12, debian13
#   - ubuntu2204, ubuntu2205, ubuntu2404, ubuntu2504
#   - fedora41
#   - rocky9
#
# Usage:
#   packer build -var "distro=debian12" -var-file=vars.json universal.pkr.hcl
#
################################################################################

packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.8"
      source  = "github.com/hashicorp/proxmox"
    }
    ansible = {
      version = ">= 1.0.0, < 1.1.4"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

# Variable Definitions
variable "proxmox_api_url" {
    type = string
    description = "URL of the Proxmox API"
}

variable "proxmox_api_token_id" {
    type = string
    description = "Proxmox API token ID"
}

variable "proxmox_api_token_secret" {
    type = string
    sensitive = true
    description = "Proxmox API token secret"
}

variable "proxmox_host_node" {
    type = string
    sensitive = true
    description = "Proxmox host node name"
}

variable "storage_pool" {
    type = string
    description = "Storage pool name"
}

variable "vmid" {
    type = string
    description = "VM ID for the build"
}

variable "distro" {
    type = string
    description = "Distribution to build (debian11, debian12, debian13, ubuntu2204, ubuntu2205, ubuntu2404, ubuntu2504, fedora41, rocky9)"
}

variable "custom_ansible_playbook" {
    type = string
    default = "./Ansible/Playbooks/image_customizations.yml"
    description = "Path to custom Ansible playbook for template customization"
}

variable "custom_ansible_varfile" {
    type = string
    default = "./Ansible/Variables/vars.yml"
    description = "Path to custom Ansible variables file for playbook"
}

# Locals for distro-specific configuration
locals {
  distro_config = {
    debian11 = {
      template_name  = "Template-Debian-11"
      vm_name        = "PACT-Debian-11"
      build_name     = "Debian11-Packer"
      package_manager = "apt"
      update_cmd     = "apt-get update -y"
      clean_cmd      = "apt-get -y autoremove --purge && apt-get clean"
    }
    debian12 = {
      template_name  = "Template-Debian-12"
      vm_name        = "PACT-Debian-12"
      build_name     = "Debian12-Packer"
      package_manager = "apt"
      update_cmd     = "apt-get update -y"
      clean_cmd      = "apt-get -y autoremove --purge && apt-get clean"
    }
    debian13 = {
      template_name  = "Template-Debian-13"
      vm_name        = "PACT-Debian-13"
      build_name     = "Debian13-Packer"
      package_manager = "apt"
      update_cmd     = "apt-get update -y"
      clean_cmd      = "apt-get -y autoremove --purge && apt-get clean"
    }
    ubuntu2204 = {
      template_name  = "Template-Ubuntu-2204"
      vm_name        = "PACT-Ubuntu-2204"
      build_name     = "Ubuntu2204-Packer"
      package_manager = "apt"
      update_cmd     = "apt-get update -y"
      clean_cmd      = "apt-get -y autoremove --purge && apt-get clean"
    }
    ubuntu2205 = {
      template_name  = "Template-Ubuntu-2205"
      vm_name        = "PACT-Ubuntu-2205"
      build_name     = "Ubuntu2205-Packer"
      package_manager = "apt"
      update_cmd     = "apt-get update -y"
      clean_cmd      = "apt-get -y autoremove --purge && apt-get clean"
    }
    ubuntu2404 = {
      template_name  = "Template-Ubuntu-2404"
      vm_name        = "PACT-Ubuntu-2404"
      build_name     = "Ubuntu2404-Packer"
      package_manager = "apt"
      update_cmd     = "apt-get update -y"
      clean_cmd      = "apt-get -y autoremove --purge && apt-get clean"
    }
    ubuntu2504 = {
      template_name  = "Template-Ubuntu-2504"
      vm_name        = "PACT-Ubuntu-2504"
      build_name     = "Ubuntu2504-Packer"
      package_manager = "apt"
      update_cmd     = "apt-get update -y"
      clean_cmd      = "apt-get -y autoremove --purge && apt-get clean"
    }
    fedora41 = {
      template_name  = "Template-Fedora-41"
      vm_name        = "PACT-Fedora-41"
      build_name     = "Fedora41-Packer"
      package_manager = "dnf"
      update_cmd     = "dnf update -y"
      clean_cmd      = "dnf autoremove -y && dnf clean all"
    }
    rocky9 = {
      template_name  = "Template-Rocky-9"
      vm_name        = "PACT-Rocky-9"
      build_name     = "Rocky9-Packer"
      package_manager = "dnf"
      update_cmd     = "dnf update -y"
      clean_cmd      = "dnf autoremove -y && dnf clean all"
    }
  }

  config = local.distro_config[var.distro]
  build_time = timestamp()
}

# Resource Definition for the VM Template
source "proxmox-clone" "vm" {
    # Proxmox Connection Settings
    proxmox_url = "${var.proxmox_api_url}"
    username = "${var.proxmox_api_token_id}"
    token = "${var.proxmox_api_token_secret}"
    insecure_skip_tls_verify = true

    # VM General Settings
    node = "${var.proxmox_host_node}"
    vm_id = "${var.vmid}"
    vm_name = local.config.vm_name
    template_description = "An Image Customized by Packer. Distribution: ${var.distro}. Build Date: ${local.build_time}"
    clone_vm = local.config.template_name
    ssh_username = "root"
    qemu_agent = true

    # VM Hard Disk Settings
    scsi_controller = "virtio-scsi-pci"

    # VM CPU/MEM Settings
    cores = "1"
    cpu_type = "host"
    memory = "1024"

    # VM Network Settings
    network_adapters {
        model = "virtio"
        bridge = "vmbr0"
        firewall = "false"
    }

    # VM Cloud-Init Settings
    cloud_init = true
    cloud_init_storage_pool = "${var.storage_pool}"
}

# Build Definition to create the VM Template
build {
    name = local.config.build_name
    sources = ["proxmox-clone.vm"]

    # Wait for Cloud-Init and update system
    provisioner "shell" {
        inline = [
            "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 1; done",
            "${local.config.update_cmd}"
        ]
    }

    # Run Ansible playbook for customization
    provisioner "ansible" {
        playbook_file = var.custom_ansible_playbook
        use_proxy = false
        extra_arguments = ["-e", "@${var.custom_ansible_varfile}", "-e", "distro=${var.distro}"]
    }

    # Generalize the Image
    provisioner "shell" {
        inline = [
            "sudo rm /etc/ssh/ssh_host_*",
            "sudo truncate -s 0 /etc/machine-id",
            "${local.config.clean_cmd}",
            "sudo cloud-init clean",
            "sudo rm -f /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg",
            "sudo rm -f /etc/NetworkManager/system-connections/*",
            "sudo sync",
            "sudo rm -rf /var/log/* /home/*/.bash_history"
        ]
    }
}
