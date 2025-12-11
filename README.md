# Proxmox Packer Ansible CloudInit Templates - Proxmox P.A.C.T.
<img src="Images/th.jpg" alt="Application Logo" width="200"/>

P.A.C.T. stands for Packer Ansible CloudInit Templates, for Proxmox! P.A.C.T. creates a series of Linux VM Templates on your Proxmox instance from a variety of distros and versions. These templates will be preconfigured for CloudInit making it so that things like resizing the filesystem or forgetting your password can easily be handled from the Proxmox web interface. We will also preinstall the QEMU-GUEST-AGENT service so that the VMs interact with Proxmox without having the dreaded "Could not get a Lock" issue. These templates will also leverage both Packer and Ansible to generalize and update the images. These Ansible and Packer configurations are easily customized by the user to allow you to make your own custom templates using whichever tool is easiest for you.

## How it Works

On the Host:
1. The script runs from anywhere, downloading Ansible and Packer to the host it runs on.
2. Creates an SSH Connection to the Proxmox Host defined in Options.ini using the Authentication declared in .env.local
3. Uploads the Options.ini and Proxmox.sh to the Proxmox host

On Proxmox:
1. Checks the Options.ini file to see what templates should be downloaded.
2. Deletes an any existing template/VM at the VMID that its trying to build on
3. Downloads the qcow2 image for the distro
4. Builds a VM with CloudInit using this image.
5. Converts this VM to a template

On the Host
1. Runs the Packer file based on the distro for each template defined in Options.ini
2. Runs the Ansible playbook based on the distro for each templated defined in Options.ini
3. Converts the new VM to a template, and deletes the source template

## Repository Structure

- **.Github/**
  - **workflows/**: Contains Git workflow files for automating the build and deployment process. You can modify these for your Runners but no modifications should be required by default. I recommend running this with a Docker Runner and not a Host Runner.

- **Scripts/**
  - **build.sh**: Main script to orchestrate the build and deployment process.
  - **proxmox.sh**: This is the part of the script that will be executed on the remote Proxmox host.
  - **cleanup.sh**: This is the cleanup script that is run on the Proxmox host when the build is complete. 

- **Packer/**
  - **Templates/**: Contains the Packer template files (e.g., `debian11.pkr.hcl`) for building the template.
  - **Variables/**: Variables configuration file for Packer. Not currently in use by the default build, however there is a vars.json file in here that you can add variables to and will be imported into each packer build, makes for easier customization.

- **Ansible/**
  - **Playbooks/**: Contains Ansible playbooks for baseline configuration. The default playbooks have commented out examples of what you can do with it, the only thing the default playbooks do is update the Guest OS.
  - **Variables/**: Contains the variables file for adding your custom user accounts, public keys, or other customizations to your playbooks.
      - **motd/**: Contains files to be downloaded by the script to add some custom MOTD such as showing VM stats when you log in via SSH.

## Prerequisites

1. Make sure that you have a user account for Packer to use in Proxmox VE
2. Generate an API Token for that Proxmox User
3. Fill in your variables in the Options.ini file. Set the customizations as needed.
4. Create environment variable secrets, a secretfile or use Git Runner Secrets for the 2 Secret values needed (Proxmox API Token Secret and either SSH Password or Private Key for Proxmox)

## Usage
1. Make Changes to the Options file to setup the script to download the images that you want to download and configure.

     <b>nVMID</b>

    The project uses the nVMID for building the templates. By default 8xx IDs are for direct images with no customizations, 9xx IDs have been customized with Packer and Ansible. If you change the nVMID setting in the Options.ini file it will change the VMIDs of all templates. <u>Make sure not to overlap with your existing stuff or this will delete anything that exists on these VMIDs</u>. The Ansible Playbooks in the Ansible folder are just examples, feel free to populate these with your customizations. You should plan on not using anything within 200 VMIDs of $nVMID. Example numbering with the default nVMID = 800:
    - **VMID 801 | 901**: Debian 11
    - **VMID 802 | 902**: Debian 12 
    - **VMID 803 | 903**: Debian 13
    - **VMID 811 | 911**: Ubuntu 22.04
    - **VMID 812 | 912**: Ubuntu 24.04
    - **VMID 821 | 921**: Fedora 39
    - **VMID 822 | 922**: Fedora 40
    - **VMID 831 | 931**: Rocky 9

   <b> PROXMOX_SSH_AUTH_METHOD </b>
   
    This variable can be set to either 'password' or 'pubkey'. This will determine how the script connects to your Proxmox instance to make the changes to the host and build the templates. The API is used for Packer to do its thing but building the initial templates is done via SSH

   <b> PROXMOX_HOST </b>

    The DNS Resolved hostname or IP Address of the endpoint that we will connect to. This can be any Node in the Proxmox cluster or a VIP. Must have API Access available and must be resolvable by DNS if provided as a hostname instead of an IP.

   <b> PROXMOX_HOST_NODE </b>

    The ID of the Host Node that you want the templates built on. For example if you have a cluster that is at proxmox.mydomain.com and the nodes in the cluster are PVE1, PVE2, and PVE3. The value for this could be PVE1 or PVE2 or PVE3.   

   <b> PROXMOX_API_TOKEN_ID </b>

    The Proxmox API Token that you've generated for packer. Example: packer_user@pam!packer

  <b> PROXMOX_API_TOKEN_SECRET </b>
     The Proxmox API Token Secret that you've generated for packer.

   <b> PROXMOX_STORAGE_POOL </b>

    The Storage Pool that you want the Templates and VM disks stored on. For example local-lvm.


3. Decide between running manually or running via a Git Runner. Note: Running manually cannot be done from the Proxmox host without making major changes to the script since the script will use SSH to connect to the Proxmox instance.

4. Running Manually - Skip to Step 4 if using Git Runner

    i. Download the repo to the machine you intend to run the build from.

        
        git clone https://github.com/CircuitSlingerYT/Proxmox-PACT.git
        
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
- Ubuntu 22.04
- Ubuntu 24.04
- Fedora 41 (Fedora 39 and 40 are no longer supported)
- Rocky Linux 9
- CentOS 9

## Links

- [Packer Documentation](https://www.packer.io/docs)
- [Ansible Documentation](https://docs.ansible.com/)
- [Packer Proxmox-Clone](https://developer.hashicorp.com/packer/integrations/hashicorp/proxmox/latest/components/builder/clone)
