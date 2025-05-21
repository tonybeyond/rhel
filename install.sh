#!/bin/bash

# System Setup and Optimization Script
# Author: AI Assistant (modified for RHEL compatibility)
# Date: May 21, 2025

set -e

# Function to check for sudo privileges
check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run this script with sudo"
        exit 1
    fi
}

# Function to get the actual user
get_actual_user() {
    ACTUAL_USER=$(logname)
    if [ -z "$ACTUAL_USER" ] && [ -n "$SUDO_USER" ]; then
        ACTUAL_USER=$SUDO_USER
    elif [ -z "$ACTUAL_USER" ]; then
        echo "Could not determine the actual user. Exiting."
        exit 1
    fi
    USER_HOME=$(eval echo ~$ACTUAL_USER)
}

# Function to detect OS type and version
detect_os() {
    if grep -q -i "rhel" /etc/os-release; then
        OS_TYPE="rhel"
        OS_VERSION=$(grep -oP '(?<=VERSION_ID=")[^"]+' /etc/os-release)
        echo "Red Hat Enterprise Linux $OS_VERSION detected"
    elif grep -q -i "almalinux" /etc/os-release; then
        OS_TYPE="almalinux"
        OS_VERSION=$(grep -oP '(?<=VERSION_ID=")[^"]+' /etc/os-release)
        echo "AlmaLinux $OS_VERSION detected"
    elif grep -q -i "rocky" /etc/os-release; then
        OS_TYPE="rocky"
        OS_VERSION=$(grep -oP '(?<=VERSION_ID=")[^"]+' /etc/os-release)
        echo "Rocky Linux $OS_VERSION detected"
    else
        OS_TYPE="unknown"
        echo "Unknown OS type. Script may not work as expected."
    fi
    
    # Get major version (e.g., 8 or 9 from 8.10 or 9.4)
    OS_MAJOR_VERSION=$(echo $OS_VERSION | cut -d. -f1)
}

# Function to enable necessary repositories
enable_repos() {
    echo "Enabling necessary repositories..."
    
    # First ensure dnf-utils is installed for config-manager functionality
    dnf install -y dnf-utils
    
    if [ "$OS_TYPE" = "rhel" ]; then
        # For RHEL, we use subscription-manager
        echo "Setting up RHEL repositories..."
        
        # Check if system is registered
        if ! subscription-manager identity &>/dev/null; then
            echo "WARNING: System does not appear to be registered with Red Hat. Some repositories may not be available."
            echo "Please register using 'subscription-manager register' before continuing."
            read -p "Continue anyway? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
        
        # Enable CodeReady Builder repository for RHEL
        echo "Enabling CodeReady Builder repository..."
        if [ "$OS_MAJOR_VERSION" = "8" ]; then
            subscription-manager repos --enable "codeready-builder-for-rhel-8-$(arch)-rpms" || echo "Failed to enable CodeReady Builder repository. May need manual configuration."
        elif [ "$OS_MAJOR_VERSION" = "9" ]; then
            subscription-manager repos --enable "codeready-builder-for-rhel-9-$(arch)-rpms" || echo "Failed to enable CodeReady Builder repository. May need manual configuration."
        fi
    else
        # For AlmaLinux and Rocky Linux
        echo "Enabling CRB repository..."
        dnf config-manager --set-enabled crb
        
        if [ "$OS_TYPE" = "almalinux" ]; then
            echo "AlmaLinux detected. Enabling PLUS repository..."
            dnf config-manager --set-enabled plus
        elif [ "$OS_TYPE" = "rocky" ]; then
            echo "Rocky Linux detected. Enabling PLUS repository..."
            dnf config-manager --set-enabled plus
        fi
    fi
}

# Function to update the system
update_system() {
    echo "Updating system..."
    dnf update -y
    dnf upgrade -y
}

# Function to install EPEL repository (updated for RHEL)
install_epel() {
    echo "Installing EPEL repository..."
    
    if [ "$OS_TYPE" = "rhel" ]; then
        # RHEL-specific EPEL installation
        if [ "$OS_MAJOR_VERSION" = "8" ]; then
            dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
        elif [ "$OS_MAJOR_VERSION" = "9" ]; then
            dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
        else
            echo "Unsupported RHEL version. EPEL installation may fail."
            dnf install -y epel-release
        fi
    else
        # For AlmaLinux and Rocky Linux
        if ! dnf list installed epel-release &>/dev/null; then
            dnf install -y epel-release
            echo "EPEL release package installed."
        else
            echo "epel-release is already installed."
        fi
    fi

    if ! dnf repolist enabled | grep -q -E '^epel\s'; then
        echo "EPEL repository not found in enabled repos. Attempting to enable it..."
        if dnf config-manager --set-enabled epel; then
            echo "EPEL repository explicitly enabled."
        else
            echo "WARNING: Failed to enable EPEL repository. 'eza' and other EPEL packages might not be found."
        fi
    fi
    
    echo "Refreshing DNF cache for EPEL repository..."
    if dnf makecache --repo=epel; then 
        echo "DNF cache refreshed for EPEL."
    else
        echo "WARNING: Failed to refresh DNF cache for EPEL. 'eza' might still not be found."
    fi
}

# Function to install common tools and utilities
install_common_tools() {
    echo "Installing common tools and utilities..."
    dnf install -y ntfs-3g libva libvdpau libva-devel libvdpau-devel neovim wget curl git btop tmux zsh neofetch fzf
    
    # Install GNOME extensions if not RHEL (may require different approach for RHEL)
    if [ "$OS_TYPE" != "rhel" ]; then
        dnf install -y gnome-shell-extension-pop-shell gnome-shell-extension-user-theme gnome-shell-extension-workspace-indicator gnome-shell-extension-dash-to-panel
    else
        echo "Skipping GNOME extensions installation on RHEL - may require manual installation"
    fi
}

install_ghostty_terminal() {
    echo "Installing Ghostty terminal..."
    if ! command -v ghostty &> /dev/null; then
        echo "Installing Ghostty using AppImage method..."
        # Create directory for AppImages
        APP_DIR="/opt/appimages"
        mkdir -p $APP_DIR
        
        # Download latest Ghostty AppImage
        GHOSTTY_APPIMAGE="$APP_DIR/Ghostty-x86_64.AppImage"
        wget -O $GHOSTTY_APPIMAGE "https://github.com/psadi/ghostty-appimage/releases/download/v1.0.1%2B4/Ghostty-1.0.1-x86_64.AppImage"
        chmod +x $GHOSTTY_APPIMAGE
        
        # Create symlink in /usr/local/bin
        ln -sf $GHOSTTY_APPIMAGE /usr/local/bin/ghostty
        
        # Set up Ghostty resources directory
        if [ -n "$ACTUAL_USER" ] && [ "$ACTUAL_USER" != "root" ]; then
            GHOSTTY_RESOURCES_DIR="$USER_HOME/.local/share/ghostty"
            su - $ACTUAL_USER -c "mkdir -p $GHOSTTY_RESOURCES_DIR"
            echo "export GHOSTTY_RESOURCES_DIR=$GHOSTTY_RESOURCES_DIR" >> "$USER_HOME/.zshrc"
            echo "export GHOSTTY_RESOURCES_DIR=$GHOSTTY_RESOURCES_DIR" >> "$USER_HOME/.bashrc"
        fi
        echo "Ghostty AppImage installed to $GHOSTTY_APPIMAGE and linked to /usr/local/bin/ghostty"
    else
        echo "Ghostty is already installed."
    fi
}

# Function to install and configure Flatpak
setup_flatpak() {
    echo "Setting up Flatpak..."
    dnf install -y flatpak
    
    if [ -n "$ACTUAL_USER" ] && [ "$ACTUAL_USER" != "root" ]; then
        su - $ACTUAL_USER -c 'flatpak remote-add --if-not-exists --user flathub https://flathub.org/repo/flathub.flatpakrepo'
    else
        flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    fi
}

install_flatpak_apps() {
    echo "Installing Flatpak applications..."
    
    FLATPAK_APPS=(
        "com.visualstudio.code"
        "org.standardnotes.standardnotes"
        "com.github.flxzt.rnote"
        "com.github.tchx84.Flatseal"
        "org.videolan.VLC"
        "com.mattjakeman.ExtensionManager"
        "io.github.brunofin.Cohesion"
        "com.notesnook.Notesnook"
        "com.belmoussaoui.Obfuscate"
    )

    INSTALL_CMD_PREFIX=""
    USER_FLAG=""
    if [ -n "$ACTUAL_USER" ] && [ "$ACTUAL_USER" != "root" ]; then
        INSTALL_CMD_PREFIX="su - $ACTUAL_USER -c '"
        USER_FLAG="--user"
        echo "Installing Flatpak applications for user $ACTUAL_USER..."
    else
        echo "Installing Flatpak applications system-wide..."
    fi

    for app_id in "${FLATPAK_APPS[@]}"; do
        if [ -n "$INSTALL_CMD_PREFIX" ]; then
            eval "${INSTALL_CMD_PREFIX}flatpak install -y $USER_FLAG flathub $app_id'"
        else
            flatpak install -y flathub $app_id
        fi
    done
    
    if [ -n "$ACTUAL_USER" ] && [ "$ACTUAL_USER" != "root" ]; then
        echo "Flatpak applications installed for user $ACTUAL_USER"
    else
        echo "Flatpak applications installed system-wide."
    fi
}

install_dev_tools() {
    echo "Installing development tools..."
    dnf groupinstall -y "Development Tools"
    dnf install -y python3 python3-pip nodejs npm
}

install_virt_tools() {
    echo "Installing virtualization host packages..."
    dnf groupinstall -y "Virtualization Host"
    dnf install -y virt-manager
}

install_brave_browser() {
    echo "Installing Brave browser..."
    if ! dnf list installed dnf-plugins-core &>/dev/null; then 
        dnf install -y dnf-plugins-core
    fi
    
    # Check if repository is already configured
    if [ ! -f "/etc/yum.repos.d/brave-browser.repo" ]; then
        dnf config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
        rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
    fi
    
    dnf install -y brave-browser
}

setup_firewall() {
    echo "Setting up firewall..."
    if ! dnf list installed firewalld &>/dev/null; then
        dnf install -y firewalld
    fi
    
    # Enable and start firewalld with proper error handling
    if ! systemctl is-enabled firewalld &>/dev/null; then
        systemctl enable firewalld || { echo "Failed to enable firewalld"; return 1; }
    fi
    
    if ! systemctl is-active firewalld &>/dev/null; then
        systemctl start firewalld || { echo "Failed to start firewalld"; return 1; }
    fi
    
    # Check current default zone before setting
    current_default=$(firewall-cmd --get-default-zone 2>/dev/null)
    if [ "$current_default" != "public" ]; then
        firewall-cmd --set-default-zone=public --permanent || { echo "Failed to set default zone"; return 1; }
    fi
    
    # Check if SSH service is already allowed
    if ! firewall-cmd --list-services | grep -q "ssh"; then
        firewall-cmd --add-service=ssh --permanent || { echo "Failed to add SSH service"; return 1; }
    fi
    
    # Always reload to apply changes
    firewall-cmd --reload || { echo "Failed to reload firewall"; return 1; }
    
    echo "Firewall configured successfully."
}

optimize_system() {
    echo "Optimizing system performance..."
    systemctl disable bluetooth.service --now 2>/dev/null || echo "Bluetooth service not found or already disabled."
    systemctl disable cups.service --now 2>/dev/null || echo "CUPS service not found or already disabled."
    
    grep -qxF "vm.swappiness=10" /etc/sysctl.conf || echo "vm.swappiness=10" >> /etc/sysctl.conf
    grep -qxF "net.ipv4.tcp_fastopen = 3" /etc/sysctl.conf || echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.conf
    grep -qxF "net.ipv4.tcp_slow_start_after_idle = 0" /etc/sysctl.conf || echo "net.ipv4.tcp_slow_start_after_idle = 0" >> /etc/sysctl.conf
    sysctl -p
}

setup_zsh() {
    if ! command -v zsh &> /dev/null; then
        echo "ZSH not found, attempting to install via common_tools. If it fails, ensure zsh is available."
    fi
    if ! command -v zsh &> /dev/null; then
        echo "ZSH is still not installed. Skipping ZSH setup."
        return
    fi

    echo "Setting up ZSH for user $ACTUAL_USER..."
    if id "$ACTUAL_USER" &>/dev/null; then
        chsh -s $(which zsh) $ACTUAL_USER

        if [ -n "$ACTUAL_USER" ] && [ "$ACTUAL_USER" != "root" ]; then
            if [ ! -d "$USER_HOME/.oh-my-zsh" ]; then
                su - $ACTUAL_USER -c 'sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended'
            else
                echo "Oh My Zsh already installed for $ACTUAL_USER."
            fi
            
            ZSH_CUSTOM_PLUGINS_DIR="${USER_HOME}/.oh-my-zsh/custom/plugins"
            # Corrected su - for mkdir
            if [ ! -d "$ZSH_CUSTOM_PLUGINS_DIR" ]; then 
                 su - $ACTUAL_USER -c "mkdir -p $ZSH_CUSTOM_PLUGINS_DIR"
            fi
            
            if [ ! -d "${ZSH_CUSTOM_PLUGINS_DIR}/zsh-syntax-highlighting" ]; then
                 su - $ACTUAL_USER -c "git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM_PLUGINS_DIR}/zsh-syntax-highlighting"
            else
                echo "zsh-syntax-highlighting already installed for $ACTUAL_USER."
            fi
           
            if [ ! -d "${ZSH_CUSTOM_PLUGINS_DIR}/zsh-autocomplete" ]; then
                su - $ACTUAL_USER -c "git clone --depth 1 -- https://github.com/marlonrichert/zsh-autocomplete.git ${ZSH_CUSTOM_PLUGINS_DIR}/zsh-autocomplete"
            else
                echo "zsh-autocomplete already installed for $ACTUAL_USER."
            fi
            
            echo "Downloading and replacing .zshrc file for user $ACTUAL_USER..."
            su - $ACTUAL_USER -c 'curl -fsSL -o ~/.zshrc https://raw.githubusercontent.com/tonybeyond/almalinux/main/.zshrc'
            echo "ZSH setup complete with custom .zshrc file for user $ACTUAL_USER"
        else
             echo "Skipping Oh My Zsh and user-specific ZSH config for root or if ACTUAL_USER is not set."
        fi
    else
        echo "User $ACTUAL_USER not found. Skipping ZSH setup for this user."
    fi
}

cleanup() {
    echo "Cleaning up..."
    dnf clean all
    echo "Vacuuming journal to keep last 7 days..."
    journalctl --vacuum-time=7d
}

# Main function
main() {
    check_sudo
    get_actual_user
    detect_os

    echo "Ensuring dnf-utils (for dnf config-manager) is installed..."
    dnf install -y dnf-utils 

    enable_repos
    update_system
    install_epel
    install_common_tools
    install_ghostty_terminal
    setup_flatpak
    install_flatpak_apps
    install_brave_browser
    install_dev_tools
    install_virt_tools
    setup_firewall
    optimize_system
    setup_zsh
    cleanup

    echo "System setup and optimization complete!"
    echo "Flatpak applications installed."
    echo "You may need to log out and log back in for ZSH changes to take full effect for user $ACTUAL_USER."
    echo "Please reboot your system to apply all changes if kernel or core libraries were updated."
}

# Run the main function
main
