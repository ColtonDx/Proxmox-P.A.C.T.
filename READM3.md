1. Ensure that you have credentials with SSH access to Proxmox. This is required to deploy the Template Build script.
2. If you intend to deploy the Packer customizations you will need a user account with PVEAdmin permissions and an API Token
   a. Datacenter > Users
   b. Add a user
   c. Datacenter > API Tokens
         Select the user account
         Create the ID
         Click ok and copy the secret
   d. Datacenter > Permissions
         Create a user permission
         Create it at /
         Role: PVEAdmin
