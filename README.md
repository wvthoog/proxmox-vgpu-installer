This is a little Bash script that configures a Proxmox 7 or 8 server to use Nvidia vGPU's. 

For further instructions see my blogpost at https://wvthoog.nl/proxmox-7-vgpu-v3/

### create driver_file checksum

    sha256sum NVIDIA-Linux-x86_64-535.104.06-vgpu-kvm.run
    4c87bc5da281a268d2dfe9252159dcfb38f7fa832fedfe97568689bd035bf087  NVIDIA-Linux-x86_64-535.104.06-vgpu-kvm.run
