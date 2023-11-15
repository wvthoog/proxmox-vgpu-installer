#!/bin/bash

CONFIG_FILE="config.txt"

# Load configuration if exists
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Variables
LOG_FILE="debug.log"
DEBUG=false
STEP="${STEP:-1}"
URL="${URL:-}"
FILE="${FILE:-}"
DRIVER_VERSION="${DRIVER_VERSION:-}"
SCRIPT_VERSION=1.0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
ORANGE='\033[0;33m'
PURPLE='\033[0;35m'
GRAY='\033[0;37m'
NC='\033[0m' # No color

# Function to display usage information
display_usage() {
    echo -e "Usage: $0 [--debug] [--step <step_number>] [--url <url>] [--file <file>]"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)
            DEBUG=true
            shift
            ;;
        --step)
            STEP="$2"
            shift 2
            ;;
        --url)
            URL="$2"
            echo "URL=$URL" >> "$CONFIG_FILE"
            shift 2
            ;;
        --file)
            FILE="$2"
            echo "FILE=$FILE" >> "$CONFIG_FILE"
            shift 2
            ;;
        *)
            # Unknown option
            display_usage
            ;;
    esac
done

# Function to run a command with specified description and log level
run_command() {
    local description="$1"
    local log_level="$2"
    local command="$3"

    case "$log_level" in
        "info")
            echo -e "${GREEN}[+]${NC} ${description}"
            ;;
        "notification")
            echo -e "${YELLOW}[-]${NC} ${description}"
            ;;
        "error")
            echo -e "${RED}[!]${NC} ${description}"
            ;;
        *)
            echo -e "[?] ${description}"
            ;;
    esac

    if [ "$DEBUG" != "true" ]; then
        eval "$command" > /dev/null 2>> "$HOME/$LOG_FILE"
    else
        eval "$command"
    fi
}

# Check Proxmox version
pve_info=$(pveversion)
version=$(echo "$pve_info" | sed -n 's/^pve-manager\/\([0-9.]*\).*$/\1/p')
#version=7.4-15
kernel=$(echo "$pve_info" | sed -n 's/^.*kernel: \([0-9.-]*pve\).*$/\1/p')
major_version=$(echo "$version" | sed 's/\([0-9]*\).*/\1/')

# License the vGPU
configure_fastapi_dls() {
    if [[ $version == 8* ]]; then
        # Get the IP address of the Proxmox server (vmbr0)
        PROXMOX_IP=$(ip addr show vmbr0 | grep -o 'inet [0-9.]*' | awk '{print $2}')

        # Prompt the user for DLS_URL with default value 127.0.0.1
        echo -e "${YELLOW}[-]${NC} On which IP address should FastAPI-DLS listen? (press Enter for default)"
        read -p "Enter your choice (default is $PROXMOX_IP): " DLS_URL
        DLS_URL=${DLS_URL:-$PROXMOX_IP}

        # Prompt the user for DLS_PORT with default value 443
        echo -e "${YELLOW}[-]${NC} On which port should FastAPI-DLS listen? (press Enter for default)"
        read -p "Enter your choice (default is 8443): " DLS_PORT
        DLS_PORT=${DLS_PORT:-8443}

        # Remove a previous version of FastAPI-DLS if any
        run_command "Remove a previous version of FastAPI-DLS if any" "info" "apt remove --purge fastapi-dls -y && apt autoremove -y"
        #run_command "Run apt autoremove" "info" "apt autoremove -y"

        directory="/etc/fastapi-dls"

        # Check if the FastAPI-DLS directory exists and has files
        if [ -d "$directory" ] && [ -n "$(ls -A $directory)" ]; then
            rm -rf $directory

            echo -e "${GREEN}[+]${NC} Removing old FastAPI-DLS"
        else
            echo -e "${GREEN}[+]${NC} No old FastAPI-DLS files found in $directory"
        fi

        # APT Update
        run_command "Running APT Update" "info" "apt update"

        # Downloading FastAPI-DLS deb package
        run_command "Downloading FastAPI-DLS deb package" "info" "wget https://git.collinwebdesigns.de/oscar.krause/fastapi-dls/-/package_files/229/download -O $HOME/fastapi-dls_1.3.8_amd64.deb"

        # Installing FastAPI-DLS
        run_command "Installing FastAPI-DLS" "info" "dpkg -i $HOME/fastapi-dls_1.3.8_amd64.deb"

        # Running APT --fix-missing and creating certificate
        run_command "Running APT --fix-missing" "info" "echo -e 'Y\n\n\n\n\n\n\n' | apt install -f --fix-missing -y"

        # Change DLS_URL
        run_command "Changing DLS_URL to 0.0.0.0" "info" "sed -i '/^DLS_URL=/c\DLS_URL=$DLS_URL' $directory/env"

        # Change DLS_PORT
        run_command "Changing DLS_PORT to 8443" "info" "sed -i '/^DLS_PORT=/c\DLS_PORT=$DLS_PORT' $directory/env"

        # Daemon-reload
        run_command "Systemctl daemon-reload" "info" "systemctl daemon-reload"

        # Restart FastAPI-DLS Service
        run_command "Restart FastAPI-DLS Service" "info" "systemctl restart fastapi-dls.service"

        # Enable FastAPI-DLS Service
        run_command "Enable FastAPI-DLS Service" "info" "systemctl enable fastapi-dls.service"

        # Check the status of the fastapi-dls service
        status=$(systemctl status fastapi-dls 2>/dev/null | grep 'Active: active (running)')

        # Check if the status contains "Active: active (running)"
        if [[ "$status" == *"Active: active (running)"* ]]; then
            echo -e "${GREEN}[+]${NC} FastAPI-DLS successfully installed and running"
        else
            echo -e "${RED}[!]${NC} FastAPI-DLS is not running."
            echo -e "${RED}[!]${NC} Check: 'journalctl -u fastapi-dls.service -n 100'"
        fi

        # Function to prompt for user confirmation
        confirm_action() {
            local message="$1"
            echo -en "${YELLOW}[?]${NC} $message (y/n): "
            read confirmation
            if [ "$confirmation" = "y" ] || [ "$confirmation" = "Y" ]; then
                return 0
            else
                return 1
            fi
        }

        # Show Linux
        if confirm_action "Show which commands to run on a Linux VM to license the vGPU using the Shell?"; then
            echo ""
            echo 'curl --insecure -L -X GET https://'$PROXMOX_IP':'$DLS_PORT'/-/client-token -o /etc/nvidia/ClientConfigToken/client_configuration_token_$(date '\''+%d-%m-%Y-%H-%M-%S'\'').tok'
            echo "service nvidia-gridd restart"
            echo 'nvidia-smi -q | grep "License"'
            echo ""
        fi

        # Show Windows
        if confirm_action "Show which commands to run on a Windows VM to license the vGPU using Powershell?"; then
            echo ""
            echo 'curl.exe --insecure -L -X GET https://'$PROXMOX_IP':'$DLS_PORT'/-/client-token -o "C:\Program Files\NVIDIA Corporation\vGPU Licensing\ClientConfigToken\client_configuration_token_$(Get-Date -f '\''dd-MM-yy-hh-mm-ss'\'').tok"'
            echo "Restart-Service NVDisplay.ContainerLocalSystem"
            echo '& 'nvidia-smi' -q  | Select-String "License"'
            echo ""
        fi
    else
        echo -e "${RED}[!]${NC} Licensing only works on Proxmox 8.x (Bookworm)."
    fi

}

# Check for root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Please use sudo or execute as root user."
    exit 1
fi

# Welcome message and disclaimer
echo -e ""
echo -e "${GREEN}        __________  __  __   ____           __        ____          "
echo -e "${YELLOW} _   __${GREEN}/ ____/ __ \/ / / /  /  _/___  _____/ /_____ _/ / /__  _____ "
echo -e "${YELLOW}| | / /${GREEN} / __/ /_/ / / / /   / // __ \/ ___/ __/ __ ' / / / _\/ ___/ "
echo -e "${YELLOW}| |/ /${GREEN} /_/ / ____/ /_/ /  _/ // / / (__  ) /_/ /_/ / / /  __/ /     "
echo -e "${YELLOW}|___/${GREEN}\____/_/    \____/  /___/_/ /_/____/\__/\__,_/_/_/\___/_/      ${NC}"
echo -e "${BLUE}by wvthoog.nl${NC}"
echo -e ""
echo -e "Welcome to the Nvidia vGPU installer version $SCRIPT_VERSION for Proxmox"
echo -e "This system is running Proxmox version ${version} with kernel ${kernel}"
echo ""

# Main installation process
case $STEP in
    1)
    echo "Select an option:"
    echo ""
    echo "1) New vGPU installation"
    echo "2) Upgrade vGPU installation"
    echo "3) Remove vGPU installation"
    echo "4) License vGPU"
    echo "5) Exit"
    echo ""
    read -p "Enter your choice: " choice

    case $choice in
        1|2)
            echo ""
            echo "You are currently at step ${STEP} of the installation process"
            echo ""
            if [ "$choice" -eq 1 ]; then
                echo -e "${GREEN}Selected:${NC} New vGPU installation"
                # Check if config file exists, if not, create it
                if [ ! -f "$CONFIG_FILE" ]; then
                    echo "STEP=1" > "$CONFIG_FILE"
                fi
            elif [ "$choice" -eq 2 ]; then
                echo -e "${GREEN}Selected:${NC} Upgrade from previous vGPU installation"
            fi
            echo ""

            # Commands for new installation
            echo -e "${GREEN}[+]${NC} Making changes to APT for Proxmox version: ${RED}$major_version${NC}"
            # Check if major_version is 8 and configure repository accordingly
            if [ "$major_version" -eq 8 ]; then
                proxmox_repo="deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription"
            # Check if major_version is 7 and configure repository accordingly
            elif [ "$major_version" -eq 7 ]; then
                proxmox_repo="deb http://download.proxmox.com/debian/pve bullseye pve-no-subscription"
            # Handle other cases if necessary
            else
                echo -e "${RED}[!]${NC} Unsupported Proxmox version: ${YELLOW}$major_version${NC}"
                exit 1
            fi

            # Check if Proxmox repository entry exists in /etc/apt/sources.list
            if ! grep -q "$proxmox_repo" /etc/apt/sources.list; then
                echo -e "${GREEN}[+]${NC} Adding Proxmox repository entry to /etc/apt/sources.list${NC}"
                echo "$proxmox_repo" >> /etc/apt/sources.list
            fi

            # Remove Proxmox enterprise repository
            echo -e "${GREEN}[+]${NC} Removing Proxmox enterprise repository"
            rm /etc/apt/sources.list.d/pve-enterprise.list 2>/dev/null

            # Remove ceph-quincy repository
            echo -e "${GREEN}[+]${NC} Removing ceph-quincy repository"
            rm /etc/apt/sources.list.d/ceph.list 2>/dev/null

            # APT update/upgrade
            run_command "Running APT Update" "info" "apt update"

            # Prompt the user for confirmation
            echo ""
            read -p "Do you want to proceed with APT Dist-Upgrade ? (y/n): " confirmation
            echo ""

            # Check user's choice
            if [ "$confirmation" == "y" ]; then
                run_command "Running APT Dist-Upgrade (...this might take some time)" "info" "apt dist-upgrade -y"
            else
                echo -e "${YELLOW}[-]${NC} Skipping apt Dist-Upgrade"
            fi          

            # APT installing packages
            run_command "Installing packages" "info" "apt install -y git build-essential dkms pve-headers mdevctl megatools"

            # Removing previous installations of vgpu
            if [ "$choice" -eq 2 ]; then
                # Removing previous Nvidia driver
                run_command "Removing previous Nvidia driver" "notification" "nvidia-uninstall -s"
                # Removing previous vgpu_unlock-rs
                run_command "Removing previous vgpu_unlock-rs" "notification" "rm -rf /opt/vgpu_unlock-rs/ 2>/dev/null"
                # Removing vgpu-proxmox
                run_command "Removing vgpu-proxmox" "notification" "rm -rf $HOME/vgpu-promox 2>/dev/null"
            fi

            # Download vgpu-proxmox
            rm -rf $HOME/vgpu-proxmox 2>/dev/null 
            run_command "Downloading vgpu-proxmox" "info" "git clone https://gitlab.com/polloloco/vgpu-proxmox.git $HOME/vgpu-proxmox"

            # Download vgpu_unlock-rs
            cd /opt
            rm -rf vgpu_unlock-rs 2>/dev/null 
            run_command "Downloading vgpu_unlock-rs" "info" "git clone https://github.com/mbilker/vgpu_unlock-rs.git "

            # Download and source Rust
            run_command "Downloading Rust" "info" "curl https://sh.rustup.rs -sSf | sh -s -- -y --profile minimal"
            run_command "Source Rust" "info" "source $HOME/.cargo/env"

            # Building vgpu_unlock-rs
            cd vgpu_unlock-rs/
            run_command "Building vgpu_unlock-rs" "info" "cargo build --release"

            if [ "$choice" -eq 1 ]; then
                # Creating vgpu directory and toml file
                echo -e "${GREEN}[+]${NC} Creating vGPU files and directories"
                mkdir -p /etc/vgpu_unlock
                touch /etc/vgpu_unlock/profile_override.toml

                # Creating systemd folders
                echo -e "${GREEN}[+]${NC} Creating systemd folders"
                mkdir -p /etc/systemd/system/{nvidia-vgpud.service.d,nvidia-vgpu-mgr.service.d}

                # Adding vgpu_unlock-rs library
                echo -e "${GREEN}[+]${NC} Adding vgpu_unlock-rs library"
                echo -e "[Service]\nEnvironment=LD_PRELOAD=/opt/vgpu_unlock-rs/target/release/libvgpu_unlock_rs.so" > /etc/systemd/system/nvidia-vgpud.service.d/vgpu_unlock.conf
                echo -e "[Service]\nEnvironment=LD_PRELOAD=/opt/vgpu_unlock-rs/target/release/libvgpu_unlock_rs.so" > /etc/systemd/system/nvidia-vgpu-mgr.service.d/vgpu_unlock.conf
               
                # Systemctl
                run_command "Systemctl daemon-reload" "info" "systemctl daemon-reload"
                run_command "Enable nvidia-vgpud.service" "info" "systemctl enable nvidia-vgpud.service"
                run_command "Enable nvidia-vgpu-mgr.service" "info" "systemctl enable nvidia-vgpu-mgr.service"

                # Checking CPU architecture
                echo -e "${GREEN}[+]${NC} Checking CPU architecture"
                vendor_id=$(cat /proc/cpuinfo | grep vendor_id | awk 'NR==1{print $3}')

                if [ "$vendor_id" = "AuthenticAMD" ]; then
                    echo -e "${GREEN}[+]${NC} Your CPU vendor id: ${YELLOW}${vendor_id}"
                    # Check if the required options are already present in GRUB_CMDLINE_LINUX_DEFAULT
                    if grep -q "amd_iommu=on iommu=pt" /etc/default/grub; then
                        echo -e "${YELLOW}[-]${NC} AMD IOMMU options are already set in GRUB_CMDLINE_LINUX_DEFAULT"
                    else
                        sed -i '/GRUB_CMDLINE_LINUX_DEFAULT/s/"$/ amd_iommu=on iommu=pt"/' /etc/default/grub
                        echo -e "${GREEN}[+]${NC} AMD IOMMU options added to GRUB_CMDLINE_LINUX_DEFAULT"
                    fi
                elif [ "$vendor_id" = "GenuineIntel" ]; then
                    echo -e "${GREEN}[+]${NC} Your CPU vendor id: ${YELLOW}${vendor_id}${NC}"
                    # Check if the required options are already present in GRUB_CMDLINE_LINUX_DEFAULT
                    if grep -q "intel_iommu=on iommu=pt" /etc/default/grub; then
                        echo -e "${YELLOW}[-]${NC} Intel IOMMU options are already set in GRUB_CMDLINE_LINUX_DEFAULT"
                    else
                        sed -i '/GRUB_CMDLINE_LINUX_DEFAULT/s/"$/ intel_iommu=on iommu=pt"/' /etc/default/grub
                        echo -e "${GREEN}[+]${NC} Intel IOMMU options added to GRUB_CMDLINE_LINUX_DEFAULT"
                    fi
                else
                    echo -e "${RED}[!]${NC} Unknown CPU architecture. Unable to configure GRUB"
                    exit 1
                fi           
                # Update GRUB
                run_command "Updating GRUB" "info" "update-grub"
            fi

            # Check if the specified lines are present in /etc/modules
            if grep -Fxq "vfio" /etc/modules && grep -Fxq "vfio_iommu_type1" /etc/modules && grep -Fxq "vfio_pci" /etc/modules && grep -Fxq "vfio_virqfd" /etc/modules; then
                echo -e "${YELLOW}[-]${NC} Kernel modules already present"
            else
                echo -e "${GREEN}[+]${NC} Enabling kernel modules"
                echo -e "vfio\nvfio_iommu_type1\nvfio_pci\nvfio_virqfd" >> /etc/modules
            fi

            # Check if /etc/modprobe.d/blacklist.conf exists
            if [ -f "/etc/modprobe.d/blacklist.conf" ]; then
                # Check if "blacklist nouveau" is present in /etc/modprobe.d/blacklist.conf
                if grep -q "blacklist nouveau" /etc/modprobe.d/blacklist.conf; then
                    echo -e "${YELLOW}[-]${NC} Nouveau already blacklisted"
                else
                    echo -e "${GREEN}[+]${NC} Blacklisting nouveau"
                    echo "blacklist nouveau" >> /etc/modprobe.d/blacklist.conf
                fi
            else
                echo -e "${GREEN}[+]${NC} Blacklisting nouveau"
                echo "blacklist nouveau" >> /etc/modprobe.d/blacklist.conf
            fi

            run_command "Updating initramfs" "info" "update-initramfs -u -k all"

            echo ""
            echo "Step 1 completed. Reboot your machine to resume the installation."
            echo ""
            echo "After reboot, run the script again to install the Nvidia driver."
            echo ""

            read -p "Reboot your machine now? (y/n): " reboot_choice
            if [ "$reboot_choice" = "y" ]; then
                echo "STEP=2" > "$HOME/$CONFIG_FILE"
                reboot
            else
                echo "Exiting the script. Remember to reboot your machine later."
                echo "STEP=2" > "$HOME/$CONFIG_FILE"
                exit 0
            fi
            ;;

        3)           
            echo ""
            echo "Clean vGPU installation"
            echo ""

            # Function to prompt for user confirmation
            confirm_action() {
                local message="$1"
                echo -en "${GREEN}[?]${NC} $message (y/n): "
                read confirmation
                if [ "$confirmation" = "y" ] || [ "$confirmation" = "Y" ]; then
                    return 0  # Return success
                else
                    return 1  # Return failure
                fi
            }

            # Removing previous Nvidia driver
            if confirm_action "Do you want to remove the previous Nvidia driver?"; then
                run_command "Removing previous Nvidia driver" "notification" "nvidia-uninstall -s"
            fi

            # Removing previous vgpu_unlock-rs
            if confirm_action "Do you want to remove vgpu_unlock-rs?"; then
                run_command "Removing previous vgpu_unlock-rs" "notification" "rm -rf /opt/vgpu_unlock-rs"
            fi

            # Removing vgpu-proxmox
            if confirm_action "Do you want to remove vgpu-proxmox?"; then
                run_command "Removing vgpu-proxmox" "notification" "rm -rf $HOME/vgpu-promox"
            fi

            # Removing FastAPI-DLS
            if confirm_action "Do you want to remove vGPU licensing?"; then
                run_command "Removing FastAPI-DLS" "notification" "apt remove fastapi-dls -y"
                run_command "Autoremoving obsolete packages" "notification" "apt autoremove -y"
            fi

            exit 0
            ;;
        4)  
            echo ""
            echo "This will setup a FastAPI-DLS Nvidia vGPU licensing server on this Promox server"         
            echo ""
            echo -e "${GREEN}[+]${NC} Licensing vGPU"

            configure_fastapi_dls
            
            exit 0
            ;;
        5)
            echo ""
            echo "Exiting the script."
            exit 0
            ;;
        *)
            echo ""
            echo "Invalid choice. Please enter 1, 2, 3, 4, or 5."
            echo ""
            ;;
        esac
    ;;
    2)
        # Step 2: Commands for the second reboot of a new installation or upgrade
        echo ""
        echo "You are currently at step ${STEP} of the installation process"
        echo ""
        echo "Proceeding with the installation"
        echo ""

        # Check if IOMMU / DMAR is enabled
        if dmesg | grep -e IOMMU | grep -q "Detected AMD IOMMU"; then
            echo -e "${GREEN}[+]${NC} AMD IOMMU Enabled"
        elif dmesg | grep -e DMAR | grep -q "IOMMU enabled"; then
            echo -e "${GREEN}[+]${NC} Intel IOMMU Enabled"
        else
            vendor_id=$(cat /proc/cpuinfo | grep vendor_id | awk 'NR==1{print $3}')
            if [ "$vendor_id" = "AuthenticAMD" ]; then
                echo -e "${RED}[!]${NC} AMD IOMMU Disabled"
                echo -e ""
                echo -e "Please make sure you have IOMMU enabled in the BIOS"
                echo -e "and make sure that this line is present in /etc/default/grub"
                echo -e "GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt""
                echo ""
            elif [ "$vendor_id" = "GenuineIntel" ]; then
                echo -e "${RED}[!]${NC} Intel IOMMU Disabled"
                echo -e ""
                echo -e "Please make sure you have VT-d enabled in the BIOS"
                echo -e "and make sure that this line is present in /etc/default/grub"
                echo -e "GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt""
                echo ""
            else
                echo -e "${RED}[!]${NC} Unknown CPU architecture."
                echo ""
                exit 1
            fi   
            echo -n -e "${RED}[!]${NC} IOMMU is disabled. Do you want to continue anyway? (y/n): "
            read -r continue_choice
            if [ "$continue_choice" != "y" ]; then
                echo "Exiting the script."
                exit 0
            fi
        fi

        # Get GPU information using lspci, filter, and extract with sed
        gpu_info=$(lspci -nnd 10de: | grep '\[03' | grep -v '^$')

        # Check if gpu_info is empty
        if [ -z "$gpu_info" ]; then
            echo -n -e "${RED}[!]${NC} No Nvidia GPU available in system, Continue? (y/n): "
            read -r continue_choice
            if [ "$continue_choice" != "y" ]; then
                echo "Exiting the script."
                exit 0
            fi

        elif [ $(echo "$gpu_info" | wc -l) -eq 1 ]; then
            gpu_architecture=$(echo "$gpu_info" | sed -n 's/.*\[0300\]: NVIDIA Corporation \([a-zA-Z0-9]*\) .*/\1/p')
            gpu_name=$(echo "$gpu_info" | sed -n 's/.*\[\(.*\)\] \[10de:.*\] .*/\1/p')
            echo -e "${GREEN}[+]${NC} You have a \"$gpu_name\" available in your system from the \"$gpu_architecture\" architecture"
        else
            # Arrays to store GPU names and architectures
            gpu_names=()
            gpu_architectures=()

            # Loop through gpu_info and extract GPU names and architectures
            while IFS= read -r line; do
                gpu_name=$(echo "$line" | sed -n 's/.*\[\(.*\)\] \[10de:.*\] .*/\1/p')
                gpu_architecture=$(echo "$line" | sed -n 's/.*NVIDIA Corporation \([a-zA-Z0-9]*\) .*/\1/p')
                gpu_names+=("$gpu_name")
                gpu_architectures+=("$gpu_architecture")
            done <<< "$gpu_info"

            echo -en "${GREEN}[+]${NC} You have a "
            for ((i = 0; i < ${#gpu_names[@]}; i++)); do
                echo -n "${gpu_names[i]} of the ${gpu_architectures[i]} architecture"
                if [ $i -lt $((${#gpu_names[@]} - 1)) ]; then
                    echo -n " and a "
                fi
            done
            echo -n " available in your system"
            echo
        fi

        # Function to extract filename from URL
        extract_filename_from_url() {
            echo "$1" | awk -F"/" '{print substr($NF, 1, index($NF, "?") ? index($NF, "?")-1 : length($NF))}'
        }

        if [ -n "$URL" ]; then
            echo -e "${GREEN}[+]${NC} Downloading vGPU host driver using curl"
            # Extract filename from URL
            driver_filename=$(extract_filename_from_url "$URL")
            # Check if the filename matches the specified patterns
            if [[ "$driver_filename" =~ ^(NVIDIA-Linux-x86_64-535\.104\.06-vgpu-kvm\.run|NVIDIA-Linux-x86_64-535\.54\.06-vgpu-kvm\.run|NVIDIA-Linux-x86_64-525\.85\.07-vgpu-kvm\.run|NVIDIA-Linux-x86_64-525\.60\.12-vgpu-kvm\.run)$ ]]; then
                # Set driver version based on filename
                case "$driver_filename" in
                    NVIDIA-Linux-x86_64-535.104.06-vgpu-kvm.run)
                        driver_version="16.1"
                        driver_patch="535.104.06.patch"
                        ;;
                    NVIDIA-Linux-x86_64-535.54.06-vgpu-kvm.run)
                        driver_version="16.0"
                        driver_patch="535.54.06.patch"
                        ;;
                    NVIDIA-Linux-x86_64-525.85.07-vgpu-kvm.run)
                        driver_version="15.1"
                        driver_patch="525.85.07.patch"
                        ;;
                    NVIDIA-Linux-x86_64-525.60.12-vgpu-kvm.run)
                        driver_version="15.0"
                        driver_patch="525.60.12.patch"
                        ;;
                esac
                # Download the file using curl
                run_command "Downloading $driver_filename" "info" "curl -s -o $driver_filename -L $URL"
            else
                echo -e "${RED}[!]${NC} Invalid filename in the URL. Exiting."
                exit 1
            fi

        elif [ -n "$FILE" ]; then
            echo -e "${GREEN}[+]${NC} Using $FILE as vGPU host driver"
            if [[ $FILE == "NVIDIA-Linux-x86_64-535.104.06-vgpu-kvm.run" ]]; then
                driver_version="16.1"
                driver_filename=$FILE
                driver_patch="535.104.06.patch"
            elif [[ $FILE == "NVIDIA-Linux-x86_64-535.54.06-vgpu-kvm.run" ]]; then
                driver_version="16.0"
                driver_filename=$FILE
                driver_patch="535.54.06.patch"
            elif [[ $FILE == "NVIDIA-Linux-x86_64-525.85.07-vgpu-kvm.run" ]]; then
                driver_version="15.1"
                driver_filename=$FILE
                driver_patch="525.85.07.patch"
            elif [[ $FILE == "NVIDIA-Linux-x86_64-525.60.12-vgpu-kvm.run" ]]; then
                driver_version="15.0"
                driver_filename=$FILE
                driver_patch="525.60.12.patch"
            else
                echo "No patches available for your vGPU driver version"
                exit 1
            fi
        
            echo -e "${YELLOW}[-]${NC} Driver version: $driver_filename"

        else
            # Offer to download vGPU driver versions based on Proxmox version
            if [[ "$major_version" == "8" ]]; then
                echo -e "${GREEN}[+]${NC} You are running Promxox version $version"
                echo -e "${GREEN}[+]${NC} Highly recommended that you install driver 16.1"
            elif [[ "$major_version" == "7" ]]; then
                echo -e "${GREEN}[+]${NC} You are running Promxox version $version"
                echo -e "${GREEN}[+]${NC} Highly recommended that you install driver 15.1"
            fi

            echo ""
            echo "Select vGPU driver version:"
            echo ""
            echo "1: 16.1 (535.104.06)"
            echo "2: 16.0 (535.54.06)"
            echo "3: 15.1 (525.85.07)"
            echo "4: 15.0 (525.60.12)"
            echo ""

            read -p "Enter your choice: " driver_choice

            case $driver_choice in
                1)
                    driver_version="16.1"
                    if [ -n "$URL" ]; then
                        driver_url="$URL"
                    else
                        driver_url="https://mega.nz/file/wy1WVCaZ#Yq2Pz_UOfydHy8nC_X_nloR4NIFC1iZFHqJN0EiAicU"
                    fi
                    driver_filename="NVIDIA-Linux-x86_64-535.104.06-vgpu-kvm.run"
                    driver_patch="535.104.06.patch"
                    ;;
                2)
                    driver_version="16.0"
                    if [ -n "$URL" ]; then
                        driver_url="$URL"
                    else
                        driver_url="https://mega.nz/file/xrNCCAaT#UuUjqRap6urvX4KA1m8-wMTCW5ZwuWKUj6zAB4-NPSo"
                    fi                
                    driver_filename="NVIDIA-Linux-x86_64-535.54.06-vgpu-kvm.run"
                    driver_patch="535.54.06.patch"
                    ;;
                3)
                    driver_version="15.1"
                    if [ -n "$URL" ]; then
                        driver_url="$URL"
                    else
                        driver_url="https://mega.nz/file/h6UVwS4a#ieGy_Q28p5v0TGrNCO0BuCFTTqXH9VXO2Jx-fgWTvZc"
                    fi                   
                    driver_filename="NVIDIA-Linux-x86_64-525.85.07-vgpu-kvm.run"
                    driver_patch="525.85.07.patch"
                    ;;
                4)
                    driver_version="15.0"
                    if [ -n "$URL" ]; then
                        driver_url="$URL"
                    else
                        driver_url="https://mega.nz/file/FzVlRZ4T#-mCwwGee9UVo34NuDuT-kQ-y9kbEswlwu7ii8KnfBbM"
                    fi                  
                    driver_filename="NVIDIA-Linux-x86_64-525.60.12-vgpu-kvm.run"
                    driver_patch="525.60.12.patch"
                    ;;
                *)
                    echo "Invalid choice. Please enter a valid option."
                    # Show the menu again
                    echo ""
                    echo "Select vGPU driver version:"
                    echo "1: 16.1 (535.104.06)"
                    echo "2: 16.0 (535.54.06)"
                    echo "3: 15.1 (525.85.07)"
                    echo "4: 15.0 (525.60.12)"
                    echo ""
                    read -p "Enter your choice: " driver_choice
                    # continue  # Restart the loop
                    ;;
            esac

            # Check if $driver_filename exists
            if [ -e "$driver_filename" ]; then
                mv "$driver_filename" "$driver_filename.bak"
                echo -e "${YELLOW}[-]${NC} Moved $driver_filename to $driver_filename.bak"
            fi

            # Check if $custom_filename exists
            if [ -e "$custom_filename" ]; then
                mv "$custom_filename" "$custom_filename.bak"
                echo -e "${YELLOW}[-]${NC} Moved $custom_filename to $custom_filename.bak"
            fi
            
            # Download and install the selected vGPU driver version
            echo -e "${GREEN}[+]${NC} Downloading vGPU $driver_filename host driver using megadl"
            megadl "$driver_url"
        fi

        # Make driver executable
        chmod +x $driver_filename
        
        # Patch and install the driver
        run_command "Patching driver" "info" "./$driver_filename --apply-patch ~/vgpu-proxmox/$driver_patch"

        # Add custom to original filename
        custom_filename="${driver_filename%.run}-custom.run"

        # Run the patched driver installer
        run_command "Installing driver" "info" "./$custom_filename --dkms -s"

        #echo -e "${GREEN}[+]${NC} Driver installed successfully."

        echo -e "${GREEN}[+]${NC} Nvidia driver version: $driver_filename"

        nvidia_smi_output=$(nvidia-smi vgpu 2>&1)

        # Extract version from FILE
        FILE_VERSION=$(echo "$driver_filename" | grep -oP '\d+\.\d+\.\d+')

        if [[ "$nvidia_smi_output" == *"NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver."* ]] || [[ "$nvidia_smi_output" == *"No supported devices in vGPU mode"* ]]; then
            echo -e "${RED}[+]${NC} Nvidia driver not properly loaded"
        elif [[ "$nvidia_smi_output" == *"Driver Version: $FILE_VERSION"* ]]; then
            echo -e "${GREEN}[+]${NC} Nvidia driver properly loaded, version matches $FILE_VERSION"
        else
            echo -e "${GREEN}[+]${NC} Nvidia driver properly loaded"
        fi

        # Start nvidia-services
        run_command "Enable nvidia-vgpud.service" "info" "systemctl start nvidia-vgpud.service"
        run_command "Enable nvidia-vgpu-mgr.service" "info" "systemctl start nvidia-vgpu-mgr.service"

        # Check DRIVER_VERSION against specific driver filenames
        if [ "$driver_filename" == "NVIDIA-Linux-x86_64-535.104.06-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 535.104.06"
            echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.1/NVIDIA-Linux-x86_64-535.104.05-grid.run"
            echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.1/537.13_grid_win10_win11_server2019_server2022_dch_64bit_international.exe"
        elif [ "$driver_filename" == "NVIDIA-Linux-x86_64-535.54.06-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 535.54.06"
            echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.0/NVIDIA-Linux-x86_64-535.54.03-grid.run"
            echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.0/536.25_grid_win10_win11_server2019_server2022_dch_64bit_international.exe"
        elif [ "$driver_filename" == "NVIDIA-Linux-x86_64-525.85.07-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 525.85.07"
            echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU15.1/NVIDIA-Linux-x86_64-525.85.05-grid.run"
            echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU15.1/528.24_grid_win10_win11_server2019_server2022_dch_64bit_international.exe"
        elif [ "$driver_filename" == "NVIDIA-Linux-x86_64-525.60.12-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 525.60.12"
            echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU15.0/NVIDIA-Linux-x86_64-525.60.13-grid.run"
            echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU15.0/527.41_grid_win10_win11_server2019_server2022_dch_64bit_international.exe"
        else
            echo -e "${RED}[!]${NC} Unknown driver version: $driver_filename"
        fi

        echo ""
        echo "Step 2 completed and installation process is now finished."
        echo ""
        echo "List all available mdevs by typing: mdevctl types"
        echo "and choose one that fits your needs and VRAM capabilities"
        echo "then login to your Proxmox server over http/https. Click the VM"
        echo "and go to Hardware. Then under Add choose PCI Device and assign the"
        echo "desired mdev type to your VM"
        echo ""
        echo "Removing the config.txt file."
        echo ""

        rm -f "$CONFIG_FILE"  # Remove config file on completion

        # Prompt the user if they want to license the vGPU
        echo -n -e "${GREEN}[?]${NC} Do you want to license the vGPU? (y/n): "
        read license_choice

        if [ "$license_choice" = "y" ] || [ "$license_choice" = "Y" ]; then
            configure_fastapi_dls
        elif [ "$license_choice" = "n" ] || [ "$license_choice" = "N" ]; then
            exit 0
        else
            echo "Invalid choice. Please enter 'y' or 'n'."
            exit 1
        fi
        ;;
    *)
        echo "Invalid installation step. Please check the script."
        rm -f "$CONFIG_FILE"  # Remove config file
        exit 1
        ;;
esac
