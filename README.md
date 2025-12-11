# Proxmox Packer Ansible CloudInit Templates - Proxmox P.A.C.T.
<img src="Images/th.jpg" alt="Application Logo" width="200"/>

P.A.C.T. stands for Packer Ansible CloudInit Templates, for Proxmox! P.A.C.T. creates a series of Linux VM Templates on your Proxmox instance from a variety of distros and versions. These templates will be preconfigured for CloudInit making it so that things like resizing the filesystem or forgetting your password can easily be handled from the Proxmox web interface. We will also preinstall the QEMU-GUEST-AGENT service so that the VMs interact with Proxmox without having the dreaded "Could not get a Lock" issue. These templates will also leverage both Packer and Ansible to generalize and update the images. These Ansible and Packer configurations are easily customized by the user to allow you to make your own custom templates using whichever tool is easiest for you.

## How it Works

The workflow has three deployment modes for template creation:

### SSH Mode (Default)
1. **On your management machine**: 
   - Reads configuration from environment variables, `.env.local`, or CLI parameters
   - Builds a list of distros to process based on enabled options or explicit `--build` parameter
   - Connects to Proxmox via SSH using password or key-based authentication
   - Uploads `proxmox.sh` script with CLI parameters (`--vmid`, `--storage`, `--build`)
   - Executes proxmox.sh remotely

2. **On Proxmox**:
   - Parses CLI parameters for VMID, storage pool, and distros to build
   - Downloads cloud images for each enabled distro
   - Customizes VMs with virt-customize (qemu-guest-agent, CloudInit, etc.)
   - Converts VMs to templates
   - Cleans up temporary resources

### Ansible Mode
1. **On your management machine**:
   - Installs Ansible dependencies
   - Executes `Ansible/Playbooks/create_templates.yml` which connects to Proxmox
   - Ansible handles template creation based on `Create_*` flags in `Ansible/Variables/vars.yml`

2. **On Proxmox** (via Ansible tasks):
   - Creates templates based on Ansible task configuration
   - More flexible for complex customizations

### Standalone Mode (Direct on Proxmox)
- Copy `proxmox.sh` directly to your Proxmox host
- Execute locally without SSH: `./proxmox.sh --vmid=800 --storage=local-lvm --build=debian12,ubuntu2404`
- No external dependencies needed on Proxmox

### Post-Template Customization (Optional)
1. **Packer customization**:
   - `build.sh` with `--packer` flag runs universal.pkr.hcl against created templates
   - Supports all 9 distros with single template file using distro parameter

2. **Ansible playbooks**:
   - Customize templates further using playbooks in `Ansible/Playbooks/`
   - Triggered automatically by `build.sh --ansible` or manually

## Repository Structure

- **.Github/**
  - **workflows/**: Contains Git workflow files for automating the build and deployment process. You can modify these for your Runners but no modifications should be required by default. I recommend running this with a Docker Runner and not a Host Runner.

- **Scripts/**
  - **build.sh**: Central orchestration script supporting multiple modes:
    - `--interactive`: Interactive mode with user prompts for all settings
    - `--packer`: Enable Packer customization phase
    - `--ansible`: Enable Ansible playbook execution (alternative to SSH)
    - `--ssh-key PATH`: Use SSH key instead of password authentication
    - `--env`: Load variables from .env.local file
    - `--var-file PATH`: Load variables from custom file
  - **proxmox.sh**: Executed on Proxmox host to create base templates. Accepts CLI parameters:
    - `--vmid=NUM`: Starting VMID (default: 800)
    - `--storage=NAME`: Storage pool name (default: local-lvm)
    - `--build=LIST`: Comma-separated distro list (default: all enabled)
  - **proxmox-updated.sh**: Alias/copy of proxmox.sh for reference

- **Packer/**
  - **Templates/**: 
    - **universal.pkr.hcl**: Universal template supporting all 9 distros. Uses `distro` variable to configure behavior for: debian11, debian12, debian13, ubuntu2204, ubuntu2404, ubuntu2504, fedora41, rocky9
    - Individual distro files (debian11.pkr.hcl, etc.) are deprecated; use universal.pkr.hcl instead
  - **Variables/**: 
    - **vars.json**: Variables configuration for Packer builds. Contains distro-specific settings and defaults.

- **Ansible/**
  - **Playbooks/**: 
    - **create_templates.yml**: Main playbook for creating templates via Ansible (alternative to SSH mode). Uses `Create_*` flags in vars.yml
    - **tasks/create_template.yml**: Reusable task for individual template creation
    - **generic.yml**: Optional post-creation customization playbook (detects OS family for package manager compatibility)
  - **Variables/**: 
    - **vars.yml**: Variables for Ansible playbooks including template creation flags (Create_Debian11, Create_Ubuntu2404, etc.) and Proxmox connection details

## Getting Started

### Prerequisites

1. **Proxmox Setup**:
   - A user account in Proxmox with sufficient permissions (can create VMs, modify storage)
   - An API Token for that user (for Packer customization phase)
   - SSH access to at least one Proxmox node

2. **Management Machine Requirements**:
   - Bash shell (Linux, macOS, or Windows with WSL)
   - curl (for downloading templates)
   - git (for cloning the repository)
   - For SSH mode: sshpass (auto-installed by build.sh if using password auth) or SSH private key
   - For Ansible mode: Ansible (auto-installed by build.sh if using --ansible flag)
   - For Packer mode: Packer (auto-installed by build.sh if using --packer flag)

### Quick Setup

1. **Clone the Repository**

   ```bash
   git clone https://github.com/ColtonDx/Proxmox-P.A.C.T.git
   cd Proxmox-P.A.C.T
   chmod +x ./Scripts/build.sh
   ```

2. **Choose Your Deployment Mode**

   The easiest way to get started is with **Interactive Mode**:

   ```bash
   ./Scripts/build.sh --interactive
   ```

   This will prompt you for:
   - Deployment method (SSH with password, SSH with key, or Ansible)
   - Whether to run Packer customization phase
   - Configuration file location (defaults to `.env.local`)
   - SSH key path (if using key-based auth)
   - Starting VMID (default: 800)
   - Storage pool name (default: local-lvm)

3. **OR: Run with Explicit Parameters**

   **SSH Mode (Password Authentication)**:
   ```bash
   export PROXMOX_HOST=pve.local
   export PROXMOX_SSH_USER=root
   export PROXMOX_SSH_PASSWORD="your_password"
   export PROXMOX_API_TOKEN_ID="packer@pam!packer_token"
   export PROXMOX_API_TOKEN_SECRET="your_api_token_secret"
   ./Scripts/build.sh
   ```

   **SSH Mode (Key-Based Authentication)**:
   ```bash
   export PROXMOX_HOST=pve.local
   export PROXMOX_SSH_USER=root
   export PROXMOX_API_TOKEN_ID="packer@pam!packer_token"
   export PROXMOX_API_TOKEN_SECRET="your_api_token_secret"
   ./Scripts/build.sh --ssh-key=/path/to/private/key
   ```

   **Ansible Mode**:
   ```bash
   export PROXMOX_HOST=pve.local
   ./Scripts/build.sh --ansible
   ```

   **Standalone on Proxmox Host** (copy proxmox.sh directly to Proxmox):
   ```bash
   ./proxmox.sh --vmid=800 --storage=local-lvm --build=debian12,ubuntu2404
   ```

4. **Create Environment Configuration Files** (Optional - for non-interactive use)

   Create `.env.local` with your Proxmox settings:
   ```bash
   export PROXMOX_HOST=pve.local
   export PROXMOX_HOST_NODE=pve
   export PROXMOX_SSH_USER=root
   export PROXMOX_SSH_PASSWORD="your_password"
   # OR for key-based auth, omit PROXMOX_SSH_PASSWORD and use: ./build.sh --ssh-key=/path/to/key
   export PROXMOX_API_TOKEN_ID="packer@pam!packer_token"
   export PROXMOX_API_TOKEN_SECRET="your_api_token_secret"
   export PROXMOX_STORAGE_POOL=local-lvm
   ```

   Edit `Ansible/Variables/vars.yml` for Ansible-mode specific settings and distro selection:
   ```yaml
   nVMID: 800
   PROXMOX_STORAGE_POOL: local-lvm
   Create_Debian11: 'Y'
   Create_Debian12: 'Y'
   Create_Ubuntu2404: 'Y'
   # ... set others to N to skip
   ```

## Usage Examples

### build.sh Script

The `build.sh` script is your main entry point and supports multiple modes and options.

**Interactive Mode** (Recommended for first-time users):
```bash
./Scripts/build.sh --interactive
```

**SSH Mode with Password** (Requires PROXMOX_SSH_PASSWORD):
```bash
./Scripts/build.sh --packer --env
```

**SSH Mode with Key** (Requires SSH private key):
```bash
./Scripts/build.sh --packer --ssh-key=/home/user/.ssh/id_rsa --env
```

**Ansible Mode** (No SSH password/key needed):
```bash
./Scripts/build.sh --ansible --packer
```

**Build Specific Distros Only** (Via environment variables or --var-file):
```bash
export Download_Debian12=1
export Download_Ubuntu2404=1
./Scripts/build.sh
```

**Without Packer Customization** (Just create base templates):
```bash
./Scripts/build.sh --env
# This will only create base templates via proxmox.sh, no Packer phase
```

### proxmox.sh Script

The `proxmox.sh` script creates the base templates on Proxmox. It can be run:

**Remotely via SSH** (from build.sh):
```bash
# This is what build.sh does automatically
./proxmox.sh --vmid=800 --storage=local-lvm --build=debian12,ubuntu2404
```

**Locally on Proxmox Host** (copy file directly to Proxmox and run):
```bash
# On your management machine:
scp proxmox.sh root@pve.local:/root/

# Then SSH into Proxmox and run:
ssh root@pve.local
cd /root
./proxmox.sh --vmid=800 --storage=local-lvm --build=debian12,ubuntu2404
```

**proxmox.sh CLI Options**:
- `--vmid=NUM`: Starting VMID for templates (default: 800)
- `--storage=NAME`: Storage pool name (default: local-lvm)
- `--build=LIST`: Comma-separated distro names (default: all enabled distros)
  - Individual: `debian11`, `debian12`, `debian13`, `ubuntu2204`, `ubuntu2404`, `ubuntu2504`, `fedora41`, `rocky9`
  - Groups: `debian` (all Debian), `ubuntu` (all Ubuntu), `rhel` (Fedora/Rocky)
  - Example: `--build=debian12,ubuntu2404,fedora41`

### Ansible Playbooks

**Create Templates via Ansible** (alternative to SSH):
```bash
ansible-playbook Ansible/Playbooks/create_templates.yml
```

**Override Variables**:
```bash
ansible-playbook Ansible/Playbooks/create_templates.yml \
  -e "nVMID=900" \
  -e "Create_Debian12=Y" \
  -e "Create_Ubuntu2404=Y"
```

**From Proxmox Host** (if running Ansible locally on Proxmox):
```bash
ansible-playbook -i localhost, -c local Ansible/Playbooks/create_templates.yml
```

### Distro Information

VM template VMIDs follow this numbering scheme (with default nVMID=800):

| Distro | Base VMID |
|--------|-----------|
| Debian 11 | 801 |
| Debian 12 | 802 |
| Debian 13 | 803 |
| Ubuntu 2204 | 811 |
| Ubuntu 2404 | 812 |
| Ubuntu 2504 | 813 |
| Fedora 41 | 821 |
| Rocky Linux 9 | 831 |

If using Packer customization, customized VMs get base VMID + 100 (e.g., Debian 12 → 902).

### Configuration Variables

#### PROXMOX_HOST
The DNS hostname or IP address of your Proxmox cluster entry point. Can be a single node or cluster VIP. Must have API access.

**Example**: `pve.local` or `192.168.1.100`

#### PROXMOX_HOST_NODE
The Proxmox node ID where templates should be created. In a cluster with PVE1, PVE2, PVE3, you can specify any of them.

**Example**: `pve` or `pve1`

#### PROXMOX_SSH_USER
SSH user account on Proxmox (usually `root`).

#### PROXMOX_SSH_PASSWORD
SSH password for password-based authentication (leave empty to use key-based auth with --ssh-key).

#### PROXMOX_API_TOKEN_ID
Proxmox API token identifier for Packer customization.

**Format**: `username@realm!token_name` (e.g., `packer@pam!packer`)

#### PROXMOX_API_TOKEN_SECRET
API token secret (generated in Proxmox UI under user settings).

#### PROXMOX_STORAGE_POOL
Proxmox storage pool name where templates and VM disks will be stored.

**Example**: `local-lvm`, `local`, or custom pool name

#### nVMID
Starting VMID for template creation. Plan for 200+ VMIDs being used (base + customized versions + temporary working VMs).

**Default**: `800`
**WARNING**: Existing VMs at target VMIDs will be deleted!
    ii. Load your Secrets (API Key and SSH Password OR SSH Private Key) into a Secrets File or an Environment Variable. Options.ini has a commented out section for an include file for secrets. You can also use the following environment variables:
      - $PROXMOX_API_TOKEN_SECRET
      - $PROXMOX_SSH_PASSWORD
      - $PROXMOX_SSH_PRIVATE_KEY

    ii. Run the build script manually:

        sudo chmod +x ./Scripts/build.sh
        sudo ./Scripts/build.sh
        
5. Running with Git

    i. Set up your Git workflows in `.github/workflows/` to trigger the build and deployment process.

    ii. Ensure you have a runner with the `Proxmox` label. The necessary packages for Packer and Ansible will be installed automatically.

    iii. Make sure to set your secrets in Git Actions, or create another way for these environment variables to be set:
      - $PROXMOX_API_TOKEN_SECRET
      - $PROXMOX_SSH_PASSWORD
      - $PROXMOX_SSH_PRIVATE_KEY
    
    iv. Commit and push your changes to the repository. Git will automatically detect the workflow and run the scripts.

## Roadmap

Coming Soon...
- More sample playbook actions
- Include instruction for creating Packer credentials
- Create a video on using and customizing the repo
- Add a way for user passwords to be sent into the Ansible Playbooks. Could be done with Packer but the goal was always for VM customizations to be done via ansible and I don't want to have to pass the 'password' environment variable through packer as if the user doesn't call it that could be an issue.

## Supported Distros

- Debian 11
- Debian 12
- Debian 13
- Ubuntu 2204
- Ubuntu 2404
- Ubuntu 2504
- Fedora 41
- Rocky Linux 9
- CentOS 9

## Links

- [Packer Documentation](https://www.packer.io/docs)
- [Ansible Documentation](https://docs.ansible.com/)
- [Packer Proxmox-Clone](https://developer.hashicorp.com/packer/integrations/hashicorp/proxmox/latest/components/builder/clone)
