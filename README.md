# Proxmox Packer Ansible CloudInit Templates - Proxmox P.A.C.T.
<img src="Images/th.jpg" alt="Application Logo" width="200"/>

P.A.C.T. stands for Packer Ansible CloudInit Templates, for Proxmox! P.A.C.T. creates a series of Linux VM Templates on your Proxmox instance from a variety of distros and versions. These templates will be preconfigured for CloudInit making it so that things like resizing the filesystem or forgetting your password can easily be handled from the Proxmox web interface. We will also preinstall the QEMU-GUEST-AGENT service so that the VMs interact with Proxmox without having the dreaded "Could not get a Lock" issue. These templates will also leverage both Packer and Ansible to generalize and update the images. These Ansible and Packer configurations are easily customized by the user to allow you to make your own custom templates using whichever tool is easiest for you.

## How it Works

The workflow has three deployment modes for template creation:

### SSH Mode (Default)
1. **On your management machine**: 
   - Reads configuration from CLI arguments, interactive mode, or from an answerfile
   - Builds a list of distros to process based on enabled options or explicit `--templates` parameter
   - Connects to Proxmox via SSH using password or key-based authentication
   - Uploads `proxmox.sh` script with CLI parameters (`--vmid-base`, `--proxmox-storage`, `--build`)
   - Executes proxmox.sh remotely

2. **On Proxmox**:
   - Downloads cloud images for each enabled distros
   - Customizes VMs with virt-customize (qemu-guest-agent, CloudInit, etc.)
   - Converts VMs to templates
   - Cleans up temporary resources

### Ansible Mode (Alternative to SSH)
1. **On your management machine**:
   - Installs Ansible dependencies
   - Executes `Ansible/Playbooks/create_templates.yml` which connects to Proxmox
   - Ansible handles template creation instead of using proxmox.sh

2. **On Proxmox** (via Ansible tasks):
   - Creates templates based on Ansible task configuration
   - More flexible for complex customizations

**Note**: Using `--ansible` only affects how base templates are created (Ansible instead of SSH). It does NOT impact the optional Packer customization phase, which uses Ansible playbooks regardless of which template creation method was chosen.

### Standalone Mode (Direct on Proxmox)
- Copy `build.sh` directly to your Proxmox host
- Execute locally without SSH: `./build.sh --local`
- Runs the same template creation process without the SSH connections

### Post-Template Customization (Optional)
After base templates are created (regardless of whether SSH or Ansible mode was used), Packer can optionally customize templates:

1. **Packer customization**:
   - `build.sh` with `--packer` flag runs universal.pkr.hcl against created templates
   - Uses Ansible provisioning internally via `image_customizations.yml` (or custom playbook with `--custom-ansible`)
   - Supports all 9 distros with single template file using distro parameter
   - Requires Proxmox API Token for authentication

## Repository Structure

- **Scripts/**
  - **build.sh**: Central orchestration script supporting interactive and CLI modes:
    - `--interactive`: Interactive mode with user prompts for all settings
    - `--packer`: Enable Packer customization phase
    - `--ansible`: Use Ansible instead of SSH/proxmox.sh for template creation (optional alternative)
    - `--rebuild`: Delete existing VMs before rebuilding (prevents accidental deletion without this flag)
  - **proxmox.sh**: Executed on Proxmox host to create base templates. Accepts CLI parameters:
    - `--vmid-base=NUM`: Starting VMID (default: 800)
    - `--proxmox-storage=NAME`: Storage pool name (default: local-lvm)
    - `--build=LIST`: Comma-separated distro list (default: all)
    - `--rebuild`: Delete existing VMs before building (safe by default without this flag)
    - `--run-packer`: Enable Packer customization phase
  - **proxmox-updated.sh**: Alias/copy of proxmox.sh for reference

- **Packer/**
  - **Templates/**: 
    - **universal.pkr.hcl**: Universal template supporting all 9 distros. Uses `distro` variable to configure behavior for: debian11, debian12, debian13, ubuntu2204, ubuntu2404, ubuntu2504, fedora41, rocky9
    - Individual distro files (debian11.pkr.hcl, etc.) are deprecated; use universal.pkr.hcl instead

- **Ansible/**
  - **Playbooks/**: 
    - **create_templates.yml**: Main playbook for creating templates via Ansible (alternative to SSH mode). Uses `Create_*` flags in vars.yml
    - **tasks/create_template.yml**: Reusable task for individual template creation
    - **image_customizations.yml**: Default Ansible playbook for post-creation template customization (detects OS family for package manager compatibility). This playbook is used by Packer when running with `--packer` flag unless overridden with `--custom-ansible`
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

2. **Run the Script**

   You can run the script from any Linux machine, including the Proxmox host itself. The script handles both remote (SSH) and local execution automatically.

   **The Easiest Way - Interactive Mode** (Recommended):
   ```bash
   ./Scripts/build.sh --interactive
   ```

   This will guide you through all configuration options interactively.

3. **Or: Run with CLI Arguments**

   Specify all settings as command-line arguments:

   ```bash
   ./Scripts/build.sh \
     --proxmox-host=pve.local \
     --proxmox-user=root \
     --proxmox-password="your_password" \
     --storage=local-lvm
   ```

### Interactive Mode Guide

The **Interactive Mode** (`./Scripts/build.sh --interactive`) is the easiest way to get started. It will prompt you for the following in order:

#### 1. Which templates do you want to generate?
Choose which Linux distributions to create templates for. Options include:
- `all` - Create templates for all supported distros
- `debian` - All Debian versions (11, 12, 13)
- `ubuntu` - All Ubuntu versions (22.04, 24.04, 25.04)
- `fedora` - All Fedora versions (41, 42)
- Individual names: `debian11`, `debian12`, `debian13`, `ubuntu2204`, `ubuntu2404`, `ubuntu2504`, `fedora41`, `fedora42`, `fedora43`, `rocky9`

Example: `debian12,ubuntu2404,fedora43` to create only Debian 12, Ubuntu 24.04, and Fedora 43 templates

#### 2. Do you want to customize the templates with Packer?
Choose whether to run the Packer customization phase after creating base templates:
- `Y` - Run Packer to further customize templates with additional packages, configurations, etc.
- `N` - Create base templates only (faster, basic Cloud-Init setup)

#### 3. Base VMID
Enter the starting VMID number for your templates (default: 800). The script will automatically assign sequential IDs based on distro offsets:
- Debian 11-13: base+1, base+2, base+3
- Ubuntu 22.04-25.04: base+11, base+12, base+13
- Fedora 41: base+21
- Rocky 9: base+31

If Packer is enabled, customized versions will use base+100 offset (e.g., 901, 902, 903 for Debian with Packer).

#### 4. Is the Proxmox server remote?
Choose how the script will connect to Proxmox:
- `Y` - Connect via SSH (default, works from any machine)
- `N` - Run locally on the Proxmox host itself (no SSH needed)

If you answer **Yes** (remote), you'll be asked for:
- **Proxmox Hostname or IP Address** - DNS name or IP of your Proxmox node
- **SSH Username** - SSH user on Proxmox (usually `root`)
- **SSH Privatekey Path** - Path to your SSH private key file, or leave blank to use password authentication
- **SSH Password** - Only prompted if you didn't specify a private key path

#### 5. Storage pool
Enter the Proxmox storage pool where templates will be stored (default: `local-lvm`). This is asked regardless of whether Proxmox is local or remote.

#### 6. VMID Preview and Rebuild Confirmation
The script displays all VMIDs that will be created:
- **Base templates** with asterisk (`*`) are temporary VMs created during the provisioning process
- **Packer customized** templates (without asterisk) are the final persistent templates
- You'll be asked if you want to delete existing VMs at these IDs before building (rebuild mode)

#### 7. Packer Configuration (if Packer was enabled)
If you chose to use Packer, you'll be prompted for:
- **Proxmox API Token ID** - Format: `username@realm!token_name` (e.g., `packer@pam!packer`)
- **Proxmox API Token Secret** - The secret generated in Proxmox for the token
- **Proxmox Host Node** - Which Proxmox node to use (default: `pve`)

### CLI/Command-Line Argument Mode

For automation, scripts, or CI/CD pipelines, specify all options as command-line arguments:

```bash
./Scripts/build.sh \
  --proxmox-host=pve.local \
  --proxmox-user=root \
  --proxmox-password="password" \
  --storage=local-lvm \
  --packer
```

**Available CLI Arguments**:
- `--interactive` - Prompt user for all settings interactively
- `--ansible` - Use Ansible to create templates (Ansible/Playbooks/create_templates.yml) instead of proxmox.sh
- `--packer` - Enable Packer customization phase
- `--rebuild` - Delete existing VMs before building (destructive)
- `--proxmox-host=HOSTNAME` - Proxmox hostname or IP address (default: pve.local)
- `--proxmox-user=USERNAME` - SSH username for Proxmox (default: root)
- `--proxmox-password=PASS` - SSH password for Proxmox authentication
- `--proxmox-key=PATH` - Path to SSH private key for authentication
- `--storage=POOL` - Proxmox storage pool name (default: local-lvm)
- `--local` - Run directly on Proxmox host (no SSH needed)
- `--templates=LIST` - Comma-separated list of templates to build (e.g., debian12,ubuntu2404, all, debian, ubuntu)
- `--custom-packerfile=PATH_OR_URL` - Path or URL to custom Packer template file (used with --packer)
- `--custom-ansible=PATH_OR_URL` - Path or URL to custom Ansible playbook for template customization (default: ./Ansible/Playbooks/image_customizations.yml)
- `--custom-ansible-varfile=PATH_OR_URL` - Path or URL to custom Ansible variables file (default: ./Ansible/Variables/vars.yml)
- `--packer-token-id=TOKEN` - Proxmox API Token ID for Packer (required with --packer, or prompted in interactive mode)
- `--packer-token-secret=SECRET` - Proxmox API Token Secret for Packer (required with --packer, or prompted in interactive mode)

**Examples**:

```bash
# Remote Proxmox with SSH password, no Packer
./Scripts/build.sh \
  --proxmox-host=pve.local \
  --proxmox-user=root \
  --proxmox-password="password"

# Remote Proxmox with SSH key and Packer
./Scripts/build.sh \
  --proxmox-host=pve.local \
  --proxmox-user=root \
  --proxmox-key=/home/user/.ssh/id_rsa \
  --packer

# Local Proxmox execution with Packer
./Scripts/build.sh \
  --local \
  --storage=local-lvm \
  --packer

# Build specific templates only
./Scripts/build.sh \
  --proxmox-host=pve.local \
  --proxmox-user=root \
  --proxmox-password="password" \
  --templates=debian12,ubuntu2404

# Build all Debian templates
./Scripts/build.sh \
  --proxmox-host=pve.local \
  --proxmox-user=root \
  --proxmox-password="password" \
  --templates=debian

# Using Ansible instead of proxmox.sh
./Scripts/build.sh \
  --proxmox-host=pve.local \
  --proxmox-user=root \
  --proxmox-password="password" \
  --ansible \
  --packer

# With custom Packer template (local path)
./Scripts/build.sh \
  --proxmox-host=pve.local \
  --proxmox-user=root \
  --proxmox-password="password" \
  --packer \
  --custom-packerfile=/path/to/custom.pkr.hcl

# With custom Packer template (URL)
./Scripts/build.sh \
  --proxmox-host=pve.local \
  --proxmox-user=root \
  --proxmox-password="password" \
  --packer \
  --custom-packerfile=https://example.com/custom.pkr.hcl

# With custom Ansible playbook (local path or URL)
./Scripts/build.sh \
  --proxmox-host=pve.local \
  --proxmox-user=root \
  --proxmox-password="password" \
  --packer \
  --custom-ansible=/path/to/custom_playbook.yml \
  --custom-ansible-varfile=https://example.com/vars.yml

# With Packer API tokens provided via CLI (fully automated, no interactive prompts)
./Scripts/build.sh \
  --proxmox-host=pve.local \
  --proxmox-user=root \
  --proxmox-password="password" \
  --packer \
  --packer-token-id="user@pam!token_id" \
  --packer-token-secret="your-secret-token"

# With all options specified
./Scripts/build.sh \
  --proxmox-host=pve.local \
  --proxmox-user=root \
  --proxmox-key=/home/user/.ssh/id_rsa \
  --storage=local-lvm \
  --templates=all \
  --packer \
  --packer-token-id="user@pam!token_id" \
  --packer-token-secret="your-secret-token" \
  --rebuild
```

## Usage Examples

### build.sh Script

The `build.sh` script is your main entry point and supports two primary modes:

#### Interactive Mode (Recommended)

**Simplest approach** - Just run and answer prompts. Note: `--interactive` **cannot be mixed** with other arguments:
```bash
./Scripts/build.sh --interactive
```

You'll be guided through:
1. Which templates to create
2. Whether to use Packer customization
3. Base VMID
4. Whether Proxmox is remote or local
5. SSH/authentication settings (if remote)
6. Storage pool
7. Rebuild confirmation with full VMID preview
8. Packer configuration (if enabled)

Note: Temporary build VMs are automatically cleaned up after template creation.

#### CLI/Command-Line Argument Mode

For automation, scripts, or CI/CD pipelines, specify all options as command-line arguments. **Do not use `--interactive`** with other arguments:

```bash
./Scripts/build.sh \
  --proxmox-host=pve.local \
  --proxmox-user=root \
  --proxmox-password="password" \
  --storage=local-lvm \
  --packer
```

#### Answerfile Mode

For repeatable configurations or team environments, use an answerfile (.env.local) to store your settings:

1. **Copy the sample answerfile**:
   ```bash
   cp .env.local.sample .env.local
   ```

2. **Edit `.env.local` with your settings**:
   ```bash
   nano .env.local
   ```

   Key parameters:
   - `PROXMOX_HOST` - Proxmox hostname or IP
   - `PROXMOX_HOST_NODE` - Node name (usually "pve")
   - `PROXMOX_SSH_USER` - SSH username (usually "root")
   - `PROXMOX_SSH_PASSWORD` - SSH password (or leave empty to use key)
   - `SSH_PRIVATE_KEY_PATH` - Path to SSH key file (optional, instead of password)
   - `PROXMOX_STORAGE_POOL` - Storage pool name
   - `nVMID` - Starting VMID
   - `BUILD_TEMPLATES` - Which templates ("all", "debian", "ubuntu", or comma-separated names)
   - `RUN_PACKER` - Enable Packer customization (true/false)
   - `PACKER_TOKEN_ID` - Proxmox API Token ID (if using Packer)
   - `PACKER_TOKEN_SECRET` - Proxmox API Token Secret (if using Packer)
   - Plus many more customization options (see `.env.local.sample` for full list)

3. **Run the script normally** - it will automatically load `.env.local`:
   ```bash
   ./Scripts/build.sh
   ```

   **Benefits of answerfile mode**:
   - Pre-configured settings ready to use
   - No interactive prompts needed
   - Easy to version control (with secrets protected)
   - Perfect for CI/CD pipelines or team environments
   - CLI arguments can still override answerfile values if needed

**Example `.env.local` file**:
```bash
# Copy this file to .env.local and customize for your environment
PROXMOX_HOST="pve.local"
PROXMOX_HOST_NODE="pve"
PROXMOX_SSH_USER="root"
PROXMOX_SSH_PASSWORD="your_password_here"
SSH_PRIVATE_KEY_PATH=""
PROXMOX_STORAGE_POOL="local-lvm"
nVMID=800
USE_ANSIBLE=false
RUN_PACKER=true
PACKER_TOKEN_ID="packer@pam!packer_token"
PACKER_TOKEN_SECRET="your_token_secret"
BUILD_TEMPLATES="all"
REBUILD=false
```

**Examples**:

```bash
# Remote Proxmox with SSH password, no Packer

The `proxmox.sh` script creates base templates. It's normally executed automatically by `build.sh`, but can be run directly:

**Remotely via SSH** (from build.sh):
```bash
./proxmox.sh --vmid-base=800 --proxmox-storage=local-lvm --build=debian12,ubuntu2404
```

**Locally on Proxmox host**:
```bash
# On your management machine:
scp proxmox.sh root@pve.local:/root/

# Then SSH into Proxmox and run:
ssh root@pve.local
./proxmox.sh --vmid-base=800 --proxmox-storage=local-lvm --build=debian12,ubuntu2404
```

**proxmox.sh CLI Options**:
- `--vmid-base=NUM` - Starting VMID (default: 800)
- `--proxmox-storage=NAME` - Storage pool name (default: local-lvm)
- `--build=LIST` - Comma-separated distro names (default: all)
  - Individual: `debian11`, `debian12`, `debian13`, `ubuntu2204`, `ubuntu2404`, `ubuntu2504`, `fedora41`, `rocky9`
  - Groups: `debian` (all Debian), `ubuntu` (all Ubuntu)
  - Example: `--build=debian12,ubuntu2404,fedora41`
- `--rebuild` - Delete existing VMs at target VMIDs before building
  - Without this flag (default): Existing VMs are preserved
  - With this flag: Old VMs are destroyed before creating new ones

**Example**:
```bash
./proxmox.sh --vmid-base=800 --proxmox-storage=local-lvm --build=debian12,ubuntu2404 --rebuild
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
| Fedora 42 | 822 |
| Fedora 43 | 823 |
| Rocky Linux 9 | 831 |

If using Packer customization, customized VMs get base VMID + 100 (e.g., Debian 12 → 902).

## Supported Distros

- Debian 11
- Debian 12
- Debian 13
- Ubuntu 22.04
- Ubuntu 24.04
- Ubuntu 25.04
- Fedora 41
- Fedora 42
- Fedora 43
- Rocky Linux 9

## Links

- [Packer Documentation](https://www.packer.io/docs)
- [Ansible Documentation](https://docs.ansible.com/)
- [Packer Proxmox-Clone](https://developer.hashicorp.com/packer/integrations/hashicorp/proxmox/latest/components/builder/clone)
