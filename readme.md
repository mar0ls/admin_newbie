# admin_newbie

Welcome to the **admin_newbie** repository! 
This repository contains installation and configuration scripts for Linux, mainly tested on Ubuntu 24. 
The goal is to make it easier for new system administrators to work with popular tools and applications.

## Table of Contents

- [Scripts](#Scripts)
- [How to Use](#How-to-Use)
- [Requirements](#Requirements)

## Scripts

This repository includes the following scripts:

1. **`i_want_docker_with_portainer.sh`**  
   Script to install Docker and Portainer.  
   [https://github.com/mar0ls/admin_newbie/blob/main/i_want_docker_with_portainer.sh](link_to_docker_script) 

2. **`i_want_nextcloud.sh`**  
   Script to install Nextcloud.  
   [https://github.com/mar0ls/admin_newbie/blob/main/i_want_nextcloud.sh](link_to_nextcloud_script) 

3. **`i_want_offload_off.sh`**  
   Script to disable offloading.  
   [https://github.com/mar0ls/admin_newbie/blob/main/i_want_offload_off.sh](link_to_offload_script) 

4. **`i_want_promisc_as_a_service.sh`**  
   Script to configure promiscuous mode as a service.  
   [https://github.com/mar0ls/admin_newbie/blob/main/i_want_promisc_as_a_service.sh](link_to_promisc_script) 

5. **`i_want_smb.sh`**  
   Script to install and configure an SMB server.  
   [https://github.com/mar0ls/admin_newbie/blob/main/i_want_smb.sh](link_to_smb_script) 

## How to Use

** To use any of the scripts, clone the repository and run the desired script in the terminal: **

```bash
git clone https://github.com/mar0ls/admin_newbie.git
cd admin_newbie
chmod +x <script_name>.sh
./<script_name>.sh
```
** If you only want to copy a single script instead of the entire repository, you can use curl or wget. Here’s how to do it: **

```bash
# Using curl
curl -O https://raw.githubusercontent.com/mar0ls/admin_newbie/main/i_want_{script_name}.sh
chmod +x <script_name>.sh
./<script_name>.sh

# Using wget
wget https://raw.githubusercontent.com/mar0ls/admin_newbie/main/i_want_{script_name}.sh
chmod +x <script_name>.sh
./<script_name>.sh
```

## Requirments
** Ubuntu 24 operating system but most scripts should work on Debian distributions. For other distributions minor adjustments will be necessary. **
