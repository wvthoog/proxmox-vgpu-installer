#!/bin/bash

CONFIG_FILE="config.txt"

# Variables
LOG_FILE="debug.log"
DEBUG=false
STEP="${STEP:-1}"
URL="${URL:-}"
FILE="${FILE:-}"
DRIVER_VERSION="${DRIVER_VERSION:-}"
SCRIPT_VERSION=1.1
VGPU_DIR=$(pwd)
VGPU_SUPPORT="${VGPU_SUPPORT:-}"
DRIVER_VERSION="${DRIVER_VERSION:-}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
ORANGE='\033[0;33m'
PURPLE='\033[0;35m'
GRAY='\033[0;37m'
NC='\033[0m' # No color

if [ -f "$VGPU_DIR/$CONFIG_FILE" ]; then
    source "$VGPU_DIR/$CONFIG_FILE"
fi

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
            echo "URL=$URL" >> "$VGPU_DIR/$CONFIG_FILE"
            shift 2
            ;;
        --file)
            FILE="$2"
            echo "FILE=$FILE" >> "$VGPU_DIR/$CONFIG_FILE"
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
        eval "$command" > /dev/null 2>> "$VGPU_DIR/$LOG_FILE"
    else
        eval "$command"
    fi
}

# Check Proxmox version
pve_info=$(pveversion)
version=$(echo "$pve_info" | sed -n 's/^pve-manager\/\([0-9.]*\).*$/\1/p')
#version=7.4-15
#version=8.1.4
kernel=$(echo "$pve_info" | sed -n 's/^.*kernel: \([0-9.-]*pve\).*$/\1/p')
major_version=$(echo "$version" | sed 's/\([0-9]*\).*/\1/')

# Function to map filename to driver version and patch
map_filename_to_version() {
    local filename="$1"
    if [[ "$filename" =~ ^(NVIDIA-Linux-x86_64-535\.54\.06-vgpu-kvm\.run|NVIDIA-Linux-x86_64-535\.104\.06-vgpu-kvm\.run|NVIDIA-Linux-x86_64-535\.129\.03-vgpu-kvm\.run|NVIDIA-Linux-x86_64-535\.161\.05-vgpu-kvm\.run|NVIDIA-Linux-x86_64-550\.54\.10-vgpu-kvm\.run)$ ]]; then
        case "$filename" in
            NVIDIA-Linux-x86_64-535.54.06-vgpu-kvm.run)
                driver_version="16.0"
                driver_patch="535.54.06.patch"
                md5="b892f75f8522264bc176f5a555acb176"
                ;;
            NVIDIA-Linux-x86_64-535.104.06-vgpu-kvm.run)
                driver_version="16.1"
                driver_patch="535.104.06.patch"
                md5="1020ad5b89fa0570c27786128385ca48"
                ;;
            NVIDIA-Linux-x86_64-535.129.03-vgpu-kvm.run)
                driver_version="16.2"
                driver_patch="535.129.03.patch"
                md5="0048208a62bacd2a7dd12fa736aa5cbb"
                ;;
            NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run)
                driver_version="16.4"
                driver_patch="535.161.05.patch"
                md5="bad6e09aeb58942750479f091bb9c4b6"
                ;;
            NVIDIA-Linux-x86_64-550.54.10-vgpu-kvm.run)
                driver_version="17.0"
                driver_patch="550.54.10.patch"
                md5="5f5e312cbd5bb64946e2a1328a98c08d"
                ;;
        esac
        return 0  # Return true
    else
        return 1  # Return false
    fi
}

# License the vGPU
configure_fastapi_dls() {
    echo ""
    read -p "$(echo -e "${BLUE}[?]${NC} Do you want to license the vGPU? (y/n): ")" choice
    echo ""

    if [ "$choice" = "y" ]; then
        # Installing Docker-CE
        run_command "Installing Docker-CE" "info" "apt install ca-certificates curl -y; \
        curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc; \
        chmod a+r /etc/apt/keyrings/docker.asc; \
        echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \$(. /etc/os-release && echo \$VERSION_CODENAME) stable\" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null; \
        apt update; \
        apt install docker-ce docker-compose -y"

        # Docker pull FastAPI-DLS
        run_command "Docker pull FastAPI-DLS" "info" "docker pull collinwebdesigns/fastapi-dls:latest; \
        working_dir=/opt/docker/fastapi-dls/cert; \
        mkdir -p \$working_dir; \
        cd \$working_dir; \
        openssl genrsa -out \$working_dir/instance.private.pem 2048; \
        openssl rsa -in \$working_dir/instance.private.pem -outform PEM -pubout -out \$working_dir/instance.public.pem; \
        echo -e '\n\n\n\n\n\n\n' | openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout \$working_dir/webserver.key -out \$working_dir/webserver.crt; \
        docker volume create dls-db"

        # Get the timezone of the Proxmox server
        timezone=$(timedatectl | grep 'Time zone' | awk '{print $3}')

        # Get the hostname of the Proxmox server
        hostname=$(hostname -i)

        fastapi_dir=~/fastapi-dls
        mkdir -p $fastapi_dir

        # Ask for desired port number here
        echo ""
        read -p "$(echo -e "${BLUE}[?]${NC} Enter the desired port number for FastAPI-DLS (default is 8443): ")" portnumber
        portnumber=${portnumber:-8443}
        echo -e "${RED}[!]${NC} Don't use port 80 or 443 since Proxmox is using those ports"
        echo ""

        echo -e "${GREEN}[+]${NC} Generate Docker YAML compose file"
        # Generate the Docker Compose YAML file
        cat > "$fastapi_dir/docker-compose.yml" <<EOF
version: '3.9'

x-dls-variables: &dls-variables
  TZ: $timezone
  DLS_URL: $hostname
  DLS_PORT: $portnumber
  LEASE_EXPIRE_DAYS: 90  # 90 days is maximum
  DATABASE: sqlite:////app/database/db.sqlite
  DEBUG: "false"

services:
  wvthoog-fastapi-dls:
    image: collinwebdesigns/fastapi-dls:latest
    restart: always
    container_name: wvthoog-fastapi-dls
    environment:
      <<: *dls-variables
    ports:
      - "$portnumber:443"
    volumes:
      - /opt/docker/fastapi-dls/cert:/app/cert
      - dls-db:/app/database
    logging:  # optional, for those who do not need logs
      driver: "json-file"
      options:
        max-file: "5"
        max-size: "10m"

volumes:
  dls-db:
EOF
        # Issue docker-compose
        run_command "Running Docker Compose" "info" "docker-compose -f \"$fastapi_dir/docker-compose.yml\" up -d"

        # Create directory where license script (Windows/Linux are stored)
        mkdir -p $VGPU_DIR/licenses

        echo -e "${GREEN}[+]${NC} Generate FastAPI-DLS Windows/Linux executables"
        # Create .sh file for Linux
        cat > "$VGPU_DIR/licenses/license_linux.sh" <<EOF
#!/bin/bash

curl --insecure -L -X GET https://$hostname:$portnumber/-/client-token -o /etc/nvidia/ClientConfigToken/client_configuration_token_\$(date '+%d-%m-%Y-%H-%M-%S').tok
service nvidia-gridd restart
nvidia-smi -q | grep "License"
EOF

        # Create .ps1 file for Windows
        cat > "$VGPU_DIR/licenses/license_windows.ps1" <<EOF
curl.exe --insecure -L -X GET https://$hostname:$portnumber/-/client-token -o "C:\Program Files\NVIDIA Corporation\vGPU Licensing\ClientConfigToken\client_configuration_token_\$(Get-Date -f 'dd-MM-yy-hh-mm-ss').tok"
Restart-Service NVDisplay.ContainerLocalSystem
& 'nvidia-smi' -q  | Select-String "License"
EOF

        echo -e "${GREEN}[+]${NC} license_windows.ps1 and license_linux.sh created and stored in: $VGPU_DIR/licenses"
        echo -e "${YELLOW}[-]${NC} Copy these files to your Windows or Linux VM's and execute"
        echo ""
        echo "Exiting script."
        echo ""
        exit 0

        # Put the stuff below in here
    elif [ "$choice" = "n" ]; then
        echo ""
        echo "Exiting script."
        echo "Install the Docker container in a VM/LXC yourself."
        echo "By using this guide: https://git.collinwebdesigns.de/oscar.krause/fastapi-dls#docker"
        echo ""
        exit 0

        # Write instruction on how to setup Docker in a VM/LXC container
        # Echo .yml script and docker-compose instructions
    else
        echo -e "${RED}[!]${NC} Invalid choice. Please enter (y/n)."
        exit 1
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
    echo "4) Download vGPU drivers"
    echo "5) License vGPU"
    echo "6) Exit"
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
                if [ ! -f "$VGPU_DIR/$CONFIG_FILE" ]; then
                    echo "STEP=1" > "$VGPU_DIR/$CONFIG_FILE"
                fi
            elif [ "$choice" -eq 2 ]; then
                echo -e "${GREEN}Selected:${NC} Upgrade from previous vGPU installation"
            fi
            echo ""

            # Function to replace repository lines
            replace_repo_lines() {
                local old_repo="$1"
                local new_repo="$2"
                # Check /etc/apt/sources.list
                if grep -q "$old_repo" /etc/apt/sources.list; then
                    sed -i "s|$old_repo|$new_repo|" /etc/apt/sources.list
                fi
                # Check files under /etc/apt/sources.list.d/
                for file in /etc/apt/sources.list.d/*; do
                    if [ -f "$file" ]; then
                        if grep -q "$old_repo" "$file"; then
                            sed -i "s|$old_repo|$new_repo|" "$file"
                        fi
                    fi
                done
            }

            # Commands for new installation
            echo -e "${GREEN}[+]${NC} Making changes to APT for Proxmox version: ${RED}$major_version${NC}"
            case $major_version in
                8)
                    proxmox_repo="deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription"
                    ;;
                7)
                    proxmox_repo="deb http://download.proxmox.com/debian/pve bullseye pve-no-subscription"
                    ;;
                *)
                    echo -e "${RED}[!]${NC} Unsupported Proxmox version: ${YELLOW}$major_version${NC}"
                    exit 1
                    ;;
            esac

            # Replace repository lines
            replace_repo_lines "deb https://enterprise.proxmox.com/debian/pve bullseye pve-enterprise" "$proxmox_repo"
            replace_repo_lines "deb https://enterprise.proxmox.com/debian/pve bookworm pve-enterprise" "$proxmox_repo"
            replace_repo_lines "deb https://enterprise.proxmox.com/debian/ceph-quincy bookworm enterprise" "deb http://download.proxmox.com/debian/ceph-quincy bookworm no-subscription"

            # Check if Proxmox repository entry exists in /etc/apt/sources.list
            if ! grep -q "$proxmox_repo" /etc/apt/sources.list; then
                echo -e "${GREEN}[+]${NC} Adding Proxmox repository entry to /etc/apt/sources.list${NC}"
                echo "$proxmox_repo" >> /etc/apt/sources.list
            fi

            # # Comment Proxmox enterprise repository
            # echo -e "${GREEN}[+]${NC} Commenting Proxmox enterprise repository"
            # sed -i 's/^/#/' /etc/apt/sources.list.d/pve-enterprise.list

            # # Replace ceph-quincy enterprise for non-subscribtion
            # echo -e "${GREEN}[+]${NC} Set Ceph to no-subscription"
            # sed -i 's#^enterprise #no-subscription#' /etc/apt/sources.list.d/ceph.list

            # APT update/upgrade
            run_command "Running APT Update" "info" "apt update"

            # Prompt the user for confirmation
            echo ""
            read -p "$(echo -e "${BLUE}[?]${NC} Do you want to proceed with APT Dist-Upgrade ? (y/n): ")" confirmation
            echo ""

            # Check user's choice
            if [ "$confirmation" == "y" ]; then
                #echo "running apt dist-upgrade"
                run_command "Running APT Dist-Upgrade (...this might take some time)" "info" "apt dist-upgrade -y"
            else
                echo -e "${YELLOW}[-]${NC} Skipping APT Dist-Upgrade"
            fi          

            # APT installing packages
            # Downgrade kernel and headers for Nvidia drivers to install successfully
            # apt install proxmox-kernel-6.5 proxmox-headers-6.5
            # used to be pve-headers, but that will use latest version (which is currently 6.8)
            run_command "Installing packages" "info" "apt install -y git build-essential dkms proxmox-kernel-6.5 proxmox-headers-6.5 mdevctl megatools"

            # Pinning the kernel
            kernel_version_compare() {
                ver1=$1
                ver2=$2
                printf '%s\n' "$ver1" "$ver2" | sort -V -r | head -n 1
            }

            # Get the kernel list and filter for 6.5 kernels
            kernel_list=$(proxmox-boot-tool kernel list | grep "6.5")

            # Check if any 6.5 kernels are available
            if [[ -n "$kernel_list" ]]; then
                # Extract the highest version
                highest_version=""
                while read -r line; do
                    kernel_version=$(echo "$line" | awk '{print $1}')
                    if [[ -z "$highest_version" ]]; then
                        highest_version="$kernel_version"
                    else
                        highest_version=$(kernel_version_compare "$highest_version" "$kernel_version")
                    fi
                done <<< "$kernel_list"

                # Pin the highest 6.5 kernel
                run_command "Pinning kernel: $highest_version" "info" "proxmox-boot-tool kernel pin $highest_version"
            else
                echo -e "${RED}[!]${NC} No 6.5 kernels installed."
            fi

            # Running NVIDIA GPU checks
            query_gpu_info() {
            local gpu_device_id="$1"
            local query_result=$(sqlite3 gpu_info.db "SELECT * FROM gpu_info WHERE deviceid='$gpu_device_id';")
            echo "$query_result"
            }

            gpu_info=$(lspci -nn | grep -i 'NVIDIA Corporation' | grep -Ei '(VGA compatible controller|3D controller)')

            # Check if no NVIDIA GPU was found
            if [ -z "$gpu_info" ]; then
                read -p "$(echo -e "${RED}[!]${NC} No Nvidia GPU available in system, Continue? (y/n): ")" continue_choice
                if [ "$continue_choice" != "y" ]; then
                    echo "Exiting script."
                    exit 0
                fi

            # Check if only one NVIDIA GPU was found
            elif [ -n "$gpu_info" ] && [ $(echo "$gpu_info" | wc -l) -eq 1 ]; then
                # Extract device IDs from the output
                gpu_device_id=$(echo "$gpu_info" | grep -oE '\[10de:[0-9a-fA-F]{2,4}\]' | cut -d ':' -f 2 | tr -d ']')
                query_result=$(query_gpu_info "$gpu_device_id")

                if [[ -n "$query_result" ]]; then
                    vendor_id=$(echo "$query_result" | cut -d '|' -f 1)
                    description=$(echo "$query_result" | cut -d '|' -f 3)
                    vgpu=$(echo "$query_result" | cut -d '|' -f 4)
                    driver=$(echo "$query_result" | cut -d '|' -f 5 | tr ';' ',')
                    chip=$(echo "$query_result" | cut -d '|' -f 6)

                    if [[ -z "$chip" ]]; then
                        chip="Unknown"
                    fi

                    echo -e "${GREEN}[*]${NC} Found one Nvidia GPU in your system"
                    echo ""

                    # Write $driver to CONFIG_FILE. To be used to determine which driver to download in step 2

                    if [[ "$vgpu" == "No" ]]; then
                        echo "$description is not vGPU capable"
                        VGPU_SUPPORT="No"
                    elif [[ "$vgpu" == "Yes" ]]; then
                        echo "$description is vGPU capable through vgpu_unlock with driver version $driver"
                        VGPU_SUPPORT="Yes"
                        DRIVER_VERSION=$driver
                    elif [[ "$vgpu" == "Native" ]]; then
                        echo "$description supports native vGPU with driver version $driver"
                        VGPU_SUPPORT="Native"
                        DRIVER_VERSION=$driver
                    else
                        echo "$description of the $chip architecture and vGPU capability is unknown"
                        VGPU_SUPPORT="Unknown"
                    fi
                else
                    echo "Device ID: $gpu_device_id not found in the database."
                    VGPU_SUPPORT="Unknown"
                fi
                echo ""

            # If multiple NVIDIA GPU's were found
            else
                # Extract GPU devices from lspci -nn output
                gpu_devices=$(lspci -nn | grep -Ei '(VGA compatible controller|3D controller).*NVIDIA Corporation')

                # Declare associative array to store GPU PCI IDs and device IDs
                declare -A gpu_pci_groups

                # Iterate over each GPU device line
                while read -r device; do
                    pci_id=$(echo "$device" | awk '{print $1}')
                    pci_device_id=$(echo "$device" | grep -oE '\[10de:[0-9a-fA-F]{2,4}\]' | cut -d ':' -f 2 | tr -d ']')
                    gpu_pci_groups["$pci_id"]="$pci_device_id"
                done <<< "$gpu_devices"

                # Iterate over each VGA GPU device, query its info, and display it
                echo -e "${GREEN}[*]${NC} Found multiple Nvidia GPUs in your system"
                echo ""

                # Initialize VGPU_SUPPORT variable
                VGPU_SUPPORT="Unknown"

                index=1
                for pci_id in "${!gpu_pci_groups[@]}"; do
                    gpu_device_id=${gpu_pci_groups[$pci_id]}
                    query_result=$(query_gpu_info "$gpu_device_id")
                    
                    if [[ -n "$query_result" ]]; then
                        vendor_id=$(echo "$query_result" | cut -d '|' -f 1)
                        description=$(echo "$query_result" | cut -d '|' -f 3)
                        vgpu=$(echo "$query_result" | cut -d '|' -f 4)
                        driver=$(echo "$query_result" | cut -d '|' -f 5 | tr ';' ',')
                        chip=$(echo "$query_result" | cut -d '|' -f 6)

                        if [[ -z "$chip" ]]; then
                            chip="Unknown"
                        fi

                        #echo "Driver: $driver"                        
                        
                        case $vgpu in
                            No)
                                if [[ "$VGPU_SUPPORT" == "Unknown" ]]; then
                                    gpu_info="is not vGPU capable"
                                    VGPU_SUPPORT="No"
                                fi
                                ;;
                            Yes)
                                if [[ "$VGPU_SUPPORT" == "No" ]]; then
                                    gpu_info="is vGPU capable through vgpu_unlock with driver version $driver"
                                    VGPU_SUPPORT="Yes"
                                    echo "info1: $driver"  
                                elif [[ "$VGPU_SUPPORT" == "Unknown" ]]; then
                                    gpu_info="is vGPU capable through vgpu_unlock with driver version $driver"
                                    VGPU_SUPPORT="Yes"
                                    echo "info2: $driver"  
                                fi
                                ;;
                            Native)
                                if [[ "$VGPU_SUPPORT" == "No" ]]; then
                                    gpu_info="supports native vGPU with driver version $driver"
                                    VGPU_SUPPORT="Native"
                                elif [[ "$VGPU_SUPPORT" == "Yes" ]]; then
                                    gpu_info="supports native vGPU with driver version $driver"
                                    VGPU_SUPPORT="Native"
                                    # Implore the user to use the native vGPU card and pass through the other card(s)
                                elif [[ "$VGPU_SUPPORT" == "Unknown" ]]; then
                                    gpu_info="supports native vGPU with driver version $driver"
                                    VGPU_SUPPORT="Native"
                                fi
                                ;;
                            Unknown)
                                    gpu_info="is a unknown GPU"
                                    VGPU_SUPPORT="No"
                                ;;
                        esac

                        # Display GPU info
                        echo "$index: $description $gpu_info"
                    else
                        echo "$index: GPU Device ID: $gpu_device_id on PCI bus 0000:$pci_id (query result not found in database)"
                    fi
                    
                    ((index++))
                done

                echo ""

                # Prompt the user to select a GPU
                echo -e "${BLUE}[?]${NC} Select the GPU you want to enable vGPU for. All other GPUs will be passed through."
                read -p "$(echo -e "${BLUE}[?]${NC} Enter the corresponding number: ")" selected_index
                echo ""

                # Validate user input
                if [[ ! "$selected_index" =~ ^[1-$index]$ ]]; then
                    echo -e "${RED}[!]${NC} Invalid input. Please enter a number between 1 and $((index-1))."
                    exit 1
                fi

                # Get the PCI ID of the selected GPU
                index=1
                for pci_id in "${!gpu_pci_groups[@]}"; do
                    if [[ $index -eq $selected_index ]]; then
                        selected_pci_id=$pci_id
                        break
                    fi
                    ((index++))
                done

                gpu_device_id=${gpu_pci_groups[$selected_pci_id]}
                query_result=$(query_gpu_info "$gpu_device_id")

                if [[ -n "$query_result" ]]; then
                    description=$(echo "$query_result" | cut -d '|' -f 3)
                    echo -e "${GREEN}[*]${NC} You selected GPU: $description with Device ID: $gpu_device_id on PCI bus 0000:$selected_pci_id"
                    DRIVER_VERSION=$driver
                else
                    echo -e "${RED}[!]${NC} GPU Device ID: $gpu_device_id not found in the database."
                fi

                # Add all PCI bus IDs to a UDEV rule that were not selected
                echo ""
                read -p "$(echo -e "${BLUE}[?]${NC} Do you want me to enable pass through for all other GPU devices? (y/n): ")" enable_pass_through
                echo ""
                if [[ "$enable_pass_through" == "y" ]]; then
                    echo -e "${YELLOW}[-]${NC} Enabling passthrough for devices:"
                    echo ""
                    for pci_id in "${!gpu_pci_groups[@]}"; do
                        if [[ "$pci_id" != "$selected_pci_id" ]]; then
                            if [ ! -z "$(ls -A /sys/class/iommu)" ]; then
                                for iommu_dev in $(ls /sys/bus/pci/devices/0000:$pci_id/iommu_group/devices) ; do
                                    echo "PCI ID: $iommu_dev"
                                    echo "ACTION==\"add\", SUBSYSTEM==\"pci\", KERNELS==\"$iommu_dev\", DRIVERS==\"*\", ATTR{driver_override}=\"vfio-pci\"" >> /etc/udev/rules.d/90-vfio-pci.rules
                                done
                            fi
                        fi
                    done
                    echo ""
                elif [[ "$enable_pass_through" == "n" ]]; then
                    echo -e "${YELLOW}[-]${NC} Add these lines by yourself, and execute a modprobe vfio-pci afterwards or reboot the server at the end of the script"
                    echo ""
                else
                    echo -e "${RED}[!]${NC} Invalid input. Please enter (y/n)."
                fi
            fi

            #echo "VGPU_SUPPORT: $VGPU_SUPPORT"

            update_grub() {
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
                #echo "updating grub"
                run_command "Updating GRUB" "info" "update-grub"
            }

            if [ "$choice" -eq 1 ]; then
                # Check the value of VGPU_SUPPORT
                if [ "$VGPU_SUPPORT" = "No" ]; then
                    echo -e "${RED}[!]${NC} You don't have a vGPU capable card in your system"
                    echo "Exiting  script."
                    exit 1
                elif [ "$VGPU_SUPPORT" = "Yes" ]; then
                    # Download vgpu-proxmox
                    rm -rf $VGPU_DIR/vgpu-proxmox 2>/dev/null 
                    #echo "downloading vgpu-proxmox"
                    run_command "Downloading vgpu-proxmox" "info" "git clone https://gitlab.com/polloloco/vgpu-proxmox.git $VGPU_DIR/vgpu-proxmox"

                    # Download vgpu_unlock-rs
                    cd /opt
                    rm -rf vgpu_unlock-rs 2>/dev/null 
                    #echo "downloading vgpu_unlock-rs"
                    run_command "Downloading vgpu_unlock-rs" "info" "git clone https://github.com/mbilker/vgpu_unlock-rs.git"

                    # Download and source Rust
                    #echo "downloading rust"
                    run_command "Downloading Rust" "info" "curl https://sh.rustup.rs -sSf | sh -s -- -y --profile minimal"
                    #echo "source rust"
                    run_command "Source Rust" "info" "source $HOME/.cargo/env"

                    # Building vgpu_unlock-rs
                    cd vgpu_unlock-rs/
                    #echo "building vgpu_unlock-rs"
                    run_command "Building vgpu_unlock-rs" "info" "cargo build --release"

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
                    #echo "systemctl daemon-reload"
                    run_command "Systemctl daemon-reload" "info" "systemctl daemon-reload"
                    #echo "enable nvidia-vgpud.service"
                    run_command "Enable nvidia-vgpud.service" "info" "systemctl enable nvidia-vgpud.service"
                    #echo "enable nvidia-vgpu-mgr.service"
                    run_command "Enable nvidia-vgpu-mgr.service" "info" "systemctl enable nvidia-vgpu-mgr.service"
                    update_grub

                elif [ "$VGPU_SUPPORT" = "Native" ]; then
                    # Execute steps for "Native" VGPU_SUPPORT
                    update_grub
                fi
            # Removing previous installations of vgpu
            elif [ "$choice" -eq 2 ]; then
                #echo "removing nvidia driver"
                # Removing previous Nvidia driver
                run_command "Removing previous Nvidia driver" "notification" "nvidia-uninstall -s"
                # Removing previous vgpu_unlock-rs
                run_command "Removing previous vgpu_unlock-rs" "notification" "rm -rf /opt/vgpu_unlock-rs/ 2>/dev/null"
                # Removing vgpu-proxmox
                run_command "Removing vgpu-proxmox" "notification" "rm -rf $VGPU_DIR/vgpu-promox 2>/dev/null"
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

            #echo "updating initramfs"
            run_command "Updating initramfs" "info" "update-initramfs -u -k all"

            echo ""
            echo "Step 1 completed. Reboot your machine to resume the installation."
            echo ""
            echo "After reboot, run the script again to install the Nvidia driver."
            echo ""

            read -p "$(echo -e "${BLUE}[?]${NC} Reboot your machine now? (y/n): ")" reboot_choice
            if [ "$reboot_choice" = "y" ]; then
                echo "STEP=2" > "$VGPU_DIR/$CONFIG_FILE"
                echo "VGPU_SUPPORT=$VGPU_SUPPORT" >> "$VGPU_DIR/$CONFIG_FILE"
                echo "DRIVER_VERSION=$DRIVER_VERSION" >> "$VGPU_DIR/$CONFIG_FILE"
                reboot
            else
                echo "Exiting script. Remember to reboot your machine later."
                echo "STEP=2" > "$VGPU_DIR/$CONFIG_FILE"
                echo "VGPU_SUPPORT=$VGPU_SUPPORT" >> "$VGPU_DIR/$CONFIG_FILE"
                echo "DRIVER_VERSION=$DRIVER_VERSION" >> "$VGPU_DIR/$CONFIG_FILE"
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
                #echo "removing previous nvidia driver"
                run_command "Removing previous Nvidia driver" "notification" "nvidia-uninstall -s"
            fi

            # Removing previous vgpu_unlock-rs
            if confirm_action "Do you want to remove vgpu_unlock-rs?"; then
                #echo "removing previous vgpu_unlock-rs"
                run_command "Removing previous vgpu_unlock-rs" "notification" "rm -rf /opt/vgpu_unlock-rs"
            fi

            # Removing vgpu-proxmox
            if confirm_action "Do you want to remove vgpu-proxmox?"; then
                #echo "removing vgpu-proxmox"
                run_command "Removing vgpu-proxmox" "notification" "rm -rf $VGPU_DIR/vgpu-promox"
            fi

            # Removing FastAPI-DLS
            if confirm_action "Do you want to remove vGPU licensing?"; then
                run_command "Removing FastAPI-DLS" "notification" "docker rm -f -v wvthoog-fastapi-dls"
            fi
            
            echo ""
            
            exit 0
            ;;
        4)  
            echo ""
            echo "This will download the Nvidia vGPU drivers"         
            echo ""
            echo -e "${GREEN}[+]${NC} Downloading Nvidia vGPU drivers"

            # Offer to download vGPU driver versions based on Proxmox version
            if [[ "$major_version" == "8" ]]; then
                echo -e "${GREEN}[+]${NC} You are running Proxmox version $version"
                echo -e "${GREEN}[+]${NC} Highly recommended that you download driver 17.0 or 16.x"
            elif [[ "$major_version" == "7" ]]; then
                echo -e "${GREEN}[+]${NC} You are running Proxmox version $version"
                echo -e "${GREEN}[+]${NC} Highly recommended that you download driver 16.x"
            fi

            echo ""
            echo "Select vGPU driver version:"
            echo ""
            echo "1: 17.0 (550.54.10)"
            echo "2: 16.4 (535.161.05)"
            echo "3: 16.2 (535.129.03)"
            echo "4: 16.1 (535.104.06)"
            echo "5: 16.0 (535.54.06)"
            echo ""

            read -p "Enter your choice: " driver_choice

            # Validate the chosen filename against the compatibility map
            case $driver_choice in
                1) driver_filename="NVIDIA-Linux-x86_64-550.54.10-vgpu-kvm.run" ;;
                2) driver_filename="NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run" ;;
                3) driver_filename="NVIDIA-Linux-x86_64-535.129.03-vgpu-kvm.run" ;;
                4) driver_filename="NVIDIA-Linux-x86_64-535.104.06-vgpu-kvm.run" ;;
                5) driver_filename="NVIDIA-Linux-x86_64-535.54.06-vgpu-kvm.run" ;;
                *) 
                    echo "Invalid choice. Please enter a valid option."
                    exit 1
                    ;;
            esac

            # Check if the selected filename is compatible
            if ! map_filename_to_version "$driver_filename"; then
                echo "Invalid choice. No patches available for your vGPU driver version."
                exit 1
            fi

            # Set the driver version based on the filename
            map_filename_to_version "$driver_filename"

            # Todo: add bittorrent download option
       
            # Set the driver URL
            case "$driver_version" in
                17.0)
                    driver_url="https://mega.nz/file/JjtyXRiC#cTIIvOIxu8vf-RdhaJMGZAwSgYmqcVEKNNnRRJTwDFI"
                    ;;
                16.4)
                    driver_url="https://mega.nz/file/RvsyyBaB#7fe_caaJkBHYC6rgFKtiZdZKkAvp7GNjCSa8ufzkG20"
                    ;;
                16.2)
                    driver_url="https://mega.nz/file/EyEXTbbY#J9FUQL1Mo4ZpNyDijStEH4bWn3AKwnSAgJEZcxUnOiQ"
                    ;;
                16.1)
                    driver_url="https://mega.nz/file/wy1WVCaZ#Yq2Pz_UOfydHy8nC_X_nloR4NIFC1iZFHqJN0EiAicU"
                    ;;
                16.0)
                    driver_url="https://mega.nz/file/xrNCCAaT#UuUjqRap6urvX4KA1m8-wMTCW5ZwuWKUj6zAB4-NPSo"
                    ;;
            esac

            echo -e "${YELLOW}[-]${NC} Driver version: $driver_filename"

            # Check if $driver_filename exists
            if [ -e "$driver_filename" ]; then
                mv "$driver_filename" "$driver_filename.bak"
                echo -e "${YELLOW}[-]${NC} Moved $driver_filename to $driver_filename.bak"
            fi
                  
            # Download and install the selected vGPU driver version
            echo -e "${GREEN}[+]${NC} Downloading vGPU $driver_filename host driver using megadl"
            megadl "$driver_url"

            # Check if download is successful
            if [ $? -ne 0 ]; then
                echo "Download failed."
                exit 1
            fi

            # Check MD5 hash of the downloaded file
            downloaded_md5=$(md5sum "$driver_filename" | awk '{print $1}')
            if [ "$downloaded_md5" != "$md5" ]; then
                echo -e "${RED}[!]${NC} MD5 checksum mismatch. Downloaded file is corrupt."
                echo ""
                read -p "$(echo -e "${BLUE}[?]${NC} Do you want to continue? (y/n): ")" choice
                echo ""
                if [ "$choice" != "y" ]; then
                    echo "Exiting script."
                    exit 1
                fi
            else
                echo -e "${GREEN}[+]${NC} MD5 checksum matched. Downloaded file is valid."
            fi

            exit 0
            ;;
        5)  
            echo ""
            echo "This will setup a FastAPI-DLS Nvidia vGPU licensing server on this Proxmox server"         
            echo ""

            configure_fastapi_dls
            
            exit 0
            ;;
        6)
            echo ""
            echo "Exiting script."
            exit 0
            ;;
        *)
            echo ""
            echo "Invalid choice. Please enter 1, 2, 3, 4, 5 or 6."
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
                echo "Exiting script."
                exit 0
            fi
        fi

        if [ -n "$URL" ]; then
            echo -e "${GREEN}[+]${NC} Downloading vGPU host driver using curl"
            # Extract filename from URL
            driver_filename=$(extract_filename_from_url "$URL")
            
            # Download the file using curl
            run_command "Downloading $driver_filename" "info" "curl -s -o $driver_filename -L $URL"
            
            if [[ "$driver_filename" == *.zip ]]; then
                # Extract the zip file
                unzip -q "$driver_filename"
                # Look for .run file inside
                run_file=$(find . -name '*.run' -type f -print -quit)
                if [ -n "$run_file" ]; then
                    # Map filename to driver version and patch
                    if map_filename_to_version "$run_file"; then
                        driver_filename="$run_file"
                    else
                        echo -e "${RED}[!]${NC} Unrecognized filename inside the zip file. Exiting."
                        exit 1
                    fi
                else
                    echo -e "${RED}[!]${NC} No .run file found inside the zip. Exiting."
                    exit 1
                fi
            fi
            
            # Check if it's a .run file
            if [[ "$driver_filename" =~ \.run$ ]]; then
                # Map filename to driver version and patch
                if map_filename_to_version "$driver_filename"; then
                    echo -e "${GREEN}[+]${NC} Compatible filename found: $driver_filename"
                else
                    echo -e "${RED}[!]${NC} Unrecognized filename: $driver_filename. Exiting."
                    exit 1
                fi
            else
                echo -e "${RED}[!]${NC} Invalid file format. Only .zip and .run files are supported. Exiting."
                exit 1
            fi

        elif [ -n "$FILE" ]; then
            echo -e "${GREEN}[+]${NC} Using $FILE as vGPU host driver"
            # Map filename to driver version and patch
            if map_filename_to_version "$FILE"; then
                # If the filename is recognized
                driver_filename="$FILE"
                echo -e "${YELLOW}[-]${NC} Driver version: $driver_filename"
            else
                # If the filename is not recognized
                echo -e "${RED}[!]${NC} No patches available for your vGPU driver version"
                exit 1
            fi
        else

            contains_version() {
                local version="$1"
                if [[ "$DRIVER_VERSION" == *"$version"* ]]; then
                    return 0
                else
                    return 1
                fi
            }

            # Offer to download vGPU driver versions based on Proxmox version and supported driver
            if [[ "$major_version" == "8" ]]; then
                echo -e "${YELLOW}[-]${NC} You are running Proxmox version $version"
                if contains_version "17" && contains_version "16"; then
                    echo -e "${YELLOW}[-]${NC} Your Nvidia GPU is supported by driver versions 17.0 and 16.x"
                elif contains_version "17"; then
                    echo -e "${YELLOW}[-]${NC} Your Nvidia GPU is supported by driver version 17.0"
                elif contains_version "16"; then
                    echo -e "${YELLOW}[-]${NC} Your Nvidia GPU is supported by driver version 16.x"
                fi
            elif [[ "$major_version" == "7" ]]; then
                echo -e "${YELLOW}[-]${NC} You are running Proxmox version $version"
                if contains_version "17" && contains_version "16"; then
                    echo -e "${YELLOW}[-]${NC} Your Nvidia GPU is supported by driver versions 17.0 and 16.x"
                elif contains_version "16"; then
                    echo -e "${YELLOW}[-]${NC} Your Nvidia GPU is supported by driver version 16.x"
                fi
            fi

            echo ""
            echo "Select vGPU driver version:"
            echo ""
            echo "1: 17.0 (550.54.10)"
            echo "2: 16.4 (535.161.05)"
            echo "3: 16.2 (535.129.03)"
            echo "4: 16.1 (535.104.06)"
            echo "5: 16.0 (535.54.06)"
            echo ""

            read -p "Enter your choice: " driver_choice

            echo ""

            # Validate the chosen filename against the compatibility map
            case $driver_choice in
                1) driver_filename="NVIDIA-Linux-x86_64-550.54.10-vgpu-kvm.run" ;;
                2) driver_filename="NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run" ;;
                3) driver_filename="NVIDIA-Linux-x86_64-535.129.03-vgpu-kvm.run" ;;
                4) driver_filename="NVIDIA-Linux-x86_64-535.104.06-vgpu-kvm.run" ;;
                5) driver_filename="NVIDIA-Linux-x86_64-535.54.06-vgpu-kvm.run" ;;
                *) 
                    echo "Invalid choice. Please enter a valid option."
                    exit 1
                    ;;
            esac

            # Check if the selected filename is compatible
            if ! map_filename_to_version "$driver_filename"; then
                echo "Invalid choice. No patches available for your vGPU driver version."
                exit 1
            fi

            # Set the driver version based on the filename
            map_filename_to_version "$driver_filename"
            
            # Set the driver URL if not provided
            if [ -z "$URL" ]; then
                case "$driver_version" in
                    17.0)
                        driver_url="https://mega.nz/file/JjtyXRiC#cTIIvOIxu8vf-RdhaJMGZAwSgYmqcVEKNNnRRJTwDFI"
                        ;;
                    16.4)
                        driver_url="https://mega.nz/file/RvsyyBaB#7fe_caaJkBHYC6rgFKtiZdZKkAvp7GNjCSa8ufzkG20"
                        ;;
                    16.2)
                        driver_url="https://mega.nz/file/EyEXTbbY#J9FUQL1Mo4ZpNyDijStEH4bWn3AKwnSAgJEZcxUnOiQ"
                        ;;
                    16.1)
                        driver_url="https://mega.nz/file/wy1WVCaZ#Yq2Pz_UOfydHy8nC_X_nloR4NIFC1iZFHqJN0EiAicU"
                        ;;
                    16.0)
                        driver_url="https://mega.nz/file/xrNCCAaT#UuUjqRap6urvX4KA1m8-wMTCW5ZwuWKUj6zAB4-NPSo"
                        ;;
                esac
            fi

            echo -e "${YELLOW}[-]${NC} Driver version: $driver_filename"

            # Check if $driver_filename exists
            if [ -e "$driver_filename" ]; then
                mv "$driver_filename" "$driver_filename.bak"
                echo -e "${YELLOW}[-]${NC} Moved $driver_filename to $driver_filename.bak"
            fi
                
            # Download and install the selected vGPU driver version
            echo -e "${GREEN}[+]${NC} Downloading vGPU $driver_filename host driver using megadl"
            megadl "$driver_url"

            # Check if download is successful
            if [ $? -ne 0 ]; then
                echo -e "${RED}[!]${NC} Download failed."
                exit 1
            fi

            # Check MD5 hash of the downloaded file
            downloaded_md5=$(md5sum "$driver_filename" | awk '{print $1}')
            if [ "$downloaded_md5" != "$md5" ]; then
                echo -e "${RED}[!]${NC}  MD5 checksum mismatch. Downloaded file is corrupt."
                echo ""
                read -p "$(echo -e "${BLUE}[?]${NC}Do you want to continue? (y/n): ")" choice
                echo ""
                if [ "$choice" != "y" ]; then
                    echo "Exiting script."
                    exit 1
                fi
            else
                echo -e "${GREEN}[+]${NC} MD5 checksum matched. Downloaded file is valid."
            fi
        fi

        # Make driver executable
        chmod +x $driver_filename

        # Patch and install the driver only if vGPU is not native
        if [ "$VGPU_SUPPORT" = "Yes" ]; then
            # Add custom to original filename
            custom_filename="${driver_filename%.run}-custom.run"

            # Check if $custom_filename exists
            if [ -e "$custom_filename" ]; then
                mv "$custom_filename" "$custom_filename.bak"
                echo -e "${YELLOW}[-]${NC} Moved $custom_filename to $custom_filename.bak"
            fi

            # Patch and install the driver
            run_command "Patching driver" "info" "./$driver_filename --apply-patch $VGPU_DIR/vgpu-proxmox/$driver_patch"
            # Run the patched driver installer
            run_command "Installing patched driver" "info" "./$custom_filename --dkms -m=kernel -s"
        elif [ "$VGPU_SUPPORT" = "Native" ] || [ "$VGPU_SUPPORT" = "Native" ] || [ "$VGPU_SUPPORT" = "Unknown" ]; then
            # Run the regular driver installer
            run_command "Installing native driver" "info" "./$driver_filename --dkms -m=kernel -s"
        else
            echo -e "${RED}[!]${NC} Unknown or unsupported GPU: $VGPU_SUPPORT"
            echo ""
            echo "Exiting script."
            echo ""
            exit 1
        fi

        echo -e "${GREEN}[+]${NC} Driver installed successfully."

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
        run_command "Enable nvidia-vgpud.service" "info" "systemctl enable --now nvidia-vgpud.service"
        run_command "Enable nvidia-vgpu-mgr.service" "info" "systemctl enable --now nvidia-vgpu-mgr.service"

        # Check DRIVER_VERSION against specific driver filenames
        if [ "$driver_filename" == "NVIDIA-Linux-x86_64-550.54.10-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 550.54.10"
            echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU17.0/NVIDIA-Linux-x86_64-550.54.14-grid.run"
            echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU17.0/551.61_grid_win10_win11_server2022_dch_64bit_international.exe"
        elif [ "$driver_filename" == "NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 535.161.05"
            echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.4/NVIDIA-Linux-x86_64-535.161.07-grid.run"
            echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.4/538.33_grid_win10_win11_server2019_server2022_dch_64bit_international.exe"
        elif [ "$driver_filename" == "NVIDIA-Linux-x86_64-535.129.03-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 535.129.03"
            echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.2/NVIDIA-Linux-x86_64-535.129.03-grid.run"
            echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.2/537.70_grid_win10_win11_server2019_server2022_dch_64bit_international.exe"
        elif [ "$driver_filename" == "NVIDIA-Linux-x86_64-535.104.06-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 535.104.06"
            echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.1/NVIDIA-Linux-x86_64-535.104.05-grid.run"
            echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.1/537.13_grid_win10_win11_server2019_server2022_dch_64bit_international.exe"
        elif [ "$driver_filename" == "NVIDIA-Linux-x86_64-535.54.06-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 535.54.06"
            echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.0/NVIDIA-Linux-x86_64-535.54.03-grid.run"
            echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.0/536.25_grid_win10_win11_server2019_server2022_dch_64bit_international.exe"
        else
            echo -e "${RED}[!]${NC} Unknown driver version: $driver_filename"
        fi

        echo ""
        echo "Step 2 completed and installation process is now finished."
        echo ""
        echo "List all available mdevs by typing: mdevctl types and choose the one that fits your needs and VRAM capabilities"
        echo "Login to your Proxmox server over http/https. Click the VM and go to Hardware."
        echo "Under Add choose PCI Device and assign the desired mdev type to your VM"
        echo ""
        echo "Removing the config.txt file."
        echo ""

        rm -f "$VGPU_DIR/$CONFIG_FILE" 

        # Option to license the vGPU
        configure_fastapi_dls
        ;;
    *)
        echo "Invalid installation step. Please check the script."
        exit 1
        ;;
esac