#!/bin/bash

# Script Name: ubuntu-minimal-install.sh
# Description: Custom minimal Ubuntu installation with Openbox, disk encryption, NVIDIA support, and Steam compatibility

# --- Configuration Variables ---
TARGET_DISK=""
HOSTNAME="minimal-ubuntu"
USERNAME="user"
ENCRYPTION_PASS=""
INSTALL_NVIDIA=false
LOG_FILE="/tmp/ubuntu-minimal-install.log"

# --- Error Handling ---
set -e  # Exit on error
exec 2>> "$LOG_FILE"  # Redirect errors to log file

log() {
    echo "[$(date)] $1" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

# --- Checkpoint for Rollback ---
checkpoint() {
    log "Checkpoint: $1"
    echo "$1" > /tmp/install-checkpoint
}

rollback() {
    log "Rolling back from checkpoint: $(cat /tmp/install-checkpoint)"
    # Add rollback logic here (e.g., unmount partitions, remove files)
    exit 1
}

trap rollback ERR  # Trigger rollback on error

# --- TUI Functions ---
select_disk() {
    DISKS=$(lsblk -d -n -o NAME | grep -v loop)
    TARGET_DISK=$(whiptail --title "Select Disk" --menu "Choose the disk to install Ubuntu on:" 15 60 5 \
        $(for disk in $DISKS; do echo "/dev/$disk $disk"; done) 3>&1 1>&2 2>&3) || error_exit "Disk selection cancelled"
    log "Selected disk: $TARGET_DISK"
}

set_hostname() {
    HOSTNAME=$(whiptail --title "Set Hostname" --inputbox "Enter the hostname for your system:" 10 60 "$HOSTNAME" 3>&1 1>&2 2>&3) || error_exit "Hostname setup cancelled"
    log "Hostname set to: $HOSTNAME"
}

set_username() {
    USERNAME=$(whiptail --title "Set Username" --inputbox "Enter the username for your account:" 10 60 "$USERNAME" 3>&1 1>&2 2>&3) || error_exit "Username setup cancelled"
    log "Username set to: $USERNAME"
}

set_encryption_pass() {
    ENCRYPTION_PASS=$(whiptail --title "Set Encryption Password" --passwordbox "Enter the password for disk encryption:" 10 60 3>&1 1>&2 2>&3) || error_exit "Encryption password setup cancelled"
    log "Encryption password set"
}

nvidia_option() {
    if whiptail --title "NVIDIA Support" --yesno "Do you want to install NVIDIA drivers?" 10 60; then
        INSTALL_NVIDIA=true
        log "NVIDIA driver installation enabled"
    else
        INSTALL_NVIDIA=false
        log "NVIDIA driver installation disabled"
    fi
}

# --- Partitioning and Encryption ---
partition_disk() {
    log "Partitioning disk: $TARGET_DISK"
    checkpoint "Partitioning"

    # Create partitions: 1 for boot (unencrypted), 2 for root (encrypted), 3 for home (encrypted)
    parted -s "$TARGET_DISK" mklabel gpt
    parted -s "$TARGET_DISK" mkpart primary 1MiB 512MiB  # Boot
    parted -s "$TARGET_DISK" mkpart primary 512MiB 50GiB  # Root
    parted -s "$TARGET_DISK" mkpart primary 50GiB 100%    # Home
    parted -s "$TARGET_DISK" set 1 boot on

    # Format boot partition
    mkfs.ext4 "${TARGET_DISK}p1"

    # Encrypt root partition
    echo -n "$ENCRYPTION_PASS" | cryptsetup luksFormat "${TARGET_DISK}p2" -
    echo -n "$ENCRYPTION_PASS" | cryptsetup luksOpen "${TARGET_DISK}p2" cryptroot -
    mkfs.ext4 /dev/mapper/cryptroot

    # Encrypt home partition
    echo -n "$ENCRYPTION_PASS" | cryptsetup luksFormat "${TARGET_DISK}p3" -
    echo -n "$ENCRYPTION_PASS" | cryptsetup luksOpen "${TARGET_DISK}p3" crypthome -
    mkfs.ext4 /dev/mapper/crypthome

    log "Disk partitioning and encryption completed"
}

# --- Mount Partitions ---
mount_partitions() {
    log "Mounting partitions"
    checkpoint "Mounting"

    mount /dev/mapper/cryptroot /mnt
    mkdir /mnt/boot
    mount "${TARGET_DISK}p1" /mnt/boot
    mkdir /mnt/home
    mount /dev/mapper/crypthome /mnt/home

    log "Partitions mounted"
}

# --- Install Base System ---
install_base_system() {
    log "Installing base system"
    checkpoint "Base System Installation"

    # Use debootstrap to install a minimal Ubuntu system
    debootstrap noble /mnt http://archive.ubuntu.com/ubuntu/ || error_exit "Failed to install base system"

    # Mount necessary filesystems
    for dir in dev proc sys; do
        mount --bind "/$dir" "/mnt/$dir"
    done

    log "Base system installed"
}

# --- Configure System ---
configure_system() {
    log "Configuring system"
    checkpoint "System Configuration"

    # Set hostname
    echo "$HOSTNAME" > /mnt/etc/hostname
    echo "127.0.0.1 localhost $HOSTNAME" > /mnt/etc/hosts

    # Configure fstab
    echo "UUID=$(blkid -s UUID -o value ${TARGET_DISK}p1) /boot ext4 defaults 0 2" >> /mnt/etc/fstab
    echo "/dev/mapper/cryptroot / ext4 defaults 0 1" >> /mnt/etc/fstab
    echo "/dev/mapper/crypthome /home ext4 defaults 0 2" >> /mnt/etc/fstab

    # Configure crypttab
    echo "cryptroot ${TARGET_DISK}p2 none luks" >> /mnt/etc/crypttab
    echo "crypthome ${TARGET_DISK}p3 none luks" >> /mnt/etc/crypttab

    # Chroot and configure
    chroot /mnt /bin/bash -c "
        apt update
        apt install -y linux-image-generic grub-efi
        grub-install $TARGET_DISK
        update-grub

        # Install Openbox and minimal X server
        apt install -y openbox xorg xinit

        # Install network manager
        apt install -y network-manager

        # Set up user
        useradd -m -s /bin/bash $USERNAME
        echo '$USERNAME:$ENCRYPTION_PASS' | chpasswd
        usermod -aG sudo $USERNAME
    "

    log "System configuration completed"
}

# --- Install NVIDIA Drivers (if selected) ---
install_nvidia() {
    if [ "$INSTALL_NVIDIA" = true ]; then
        log "Installing NVIDIA drivers"
        checkpoint "NVIDIA Installation"

        chroot /mnt /bin/bash -c "
            apt install -y nvidia-driver nvidia-utils
        "

        log "NVIDIA drivers installed"
    fi
}

# --- Install Steam ---
install_steam() {
    log "Installing Steam"
    checkpoint "Steam Installation"

    chroot /mnt /bin/bash -c "
        apt install -y steam
    "

    log "Steam installed"
}

# --- Install Dock (Plank) ---
install_dock() {
    log "Installing dock (Plank)"
    checkpoint "Dock Installation"

    chroot /mnt /bin/bash -c "
        apt install -y plank
        # Configure Plank to autostart with Openbox
        mkdir -p /home/$USERNAME/.config/openbox
        echo 'plank &' >> /home/$USERNAME/.config/openbox/autostart
        chown -R $USERNAME:$USERNAME /home/$USERNAME/.config
    "

    log "Dock installed"
}

# --- Main Installation Process ---
main() {
    log "Starting installation process"

    # TUI Steps
    select_disk
    set_hostname
    set_username
    set_encryption_pass
    nvidia_option

    # Installation Steps
    partition_disk
    mount_partitions
    install_base_system
    configure_system
    install_nvidia
    install_steam
    install_dock

    log "Installation completed successfully"
    whiptail --title "Installation Complete" --msgbox "Ubuntu installation completed! Reboot to start using your system." 10 60
}

main
