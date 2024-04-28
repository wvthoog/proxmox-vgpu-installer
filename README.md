This is a little Bash script that configures a Proxmox 7 or 8 server to use Nvidia vGPU's. 

For further instructions see my blogpost at https://wvthoog.nl/proxmox-7-vgpu-v3/

Changes in version 1.1
- Added new driver version
    16.2
    16.4
    17.0
- Added checks for multiple GPU's
- Created database to check for PCI ID's to determine if a GPU is natively supported
- Write config.txt always to script directory
- Use Docker for hosting FastAPI-DLS (licensing)
- Create Powershell (ps1) and Bash (sh) files to retrieve licenses from FastAPI-DLS