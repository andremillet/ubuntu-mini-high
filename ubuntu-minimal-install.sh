#!/bin/bash

# ubuntu-minimal-install.sh
# Minimal Ubuntu installer with Openbox, LUKS encryption, Plank dock, and TUI
# Hosted at: https://github.com/andremillet/ubuntu-mini-high/blob/main/ubuntu-minimal-install.sh

# Exit on error
set -e

# Logging function
log() {
    echo "[INFO] $1" | tee -a /var/log/ubuntu-mini-high-install.log
}

# Error handling function
handle_error() {
    echo "[ERROR] $1" >&2
    echo "Installation failed. Check /var/log/ubuntu-mini-high-install.log for details." >&2
    exit 1
}

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    handle_error "This script must be run as root."
fi

# Install dialog for TUI
apt-get update || handle_error "Failed to update package lists."
apt-get install -y dialog || handle_error "Failed to install dialog."

# TUI: Welcome message
dialog --title "Ubuntu Mini High Installer" --msgbox "Welcome to the Ubuntu Mini High installation!\nThis will set up a minimal Ubuntu system with Openbox, LUKS encryption, and a macOS Mojave-themed Plank dock." 10 60

# TUI: Select disk
DISKS=$(lsblk -d -o NAME,SIZE | grep -v loop | awk '{print $1 " (" $2 ")"}')
DISK=$(dialog --title "Select Installation Disk" --menu "Choose the disk to install Ubuntu Mini High:" 15 60 5 $DISKS 2>&1 >/dev/tty) || handle_error "Disk selection canceled."
DISK="/dev/$DISK"
log "Selected disk: $DISK"

# TUI: Confirm disk wipe
dialog --title "Confirm Disk Wipe" --yesno "WARNING: All data on $DISK will be erased. Continue?" 7 60 || handle_error "User canceled disk wipe."
log "User confirmed disk wipe."

# TUI: Set hostname
HOSTNAME=$(dialog --title "Set Hostname" --inputbox "Enter hostname for the system:" 8 40 "ubuntu-mini-high" 2>&1 >/dev/tty) || handle_error "Hostname input canceled."
log "Hostname set to: $HOSTNAME"

# TUI: Set username
USERNAME=$(dialog --title "Set Username" --inputbox "Enter username for the primary user:" 8 40 "user" 2>&1 >/dev/tty) || handle_error "Username input canceled."
log "Username set to: $USERNAME"

# TUI: Set user password
PASSWORD=$(dialog --title "Set Password" --passwordbox "Enter password for $USERNAME:" 8 40 2>&1 >/dev/tty) || handle_error "Password input canceled."
PASSWORD2=$(dialog --title "Confirm Password" --passwordbox "Confirm password for $USERNAME:" 8 40 2>&1 >/dev/tty) || handle_error "Password confirmation canceled."
if [ "$PASSWORD" != "$PASSWORD2" ]; then
    handle_error "Passwords do not match."
fi
log "User password set."

# TUI: Prompt for Steam installation
dialog --title "Install Steam" --yesno "Would you like to install Steam for gaming?" 7 60
STEAM_INSTALL=$?
log "Steam installation selection: $STEAM_INSTALL"

# Partition the disk: /boot, /, /home
log "Partitioning disk $DISK..."
parted -s "$DISK" mklabel gpt || handle_error "Failed to create GPT label."
parted -s "$DISK" mkpart primary fat32 1MiB 512MiB || handle_error "Failed to create /boot partition."
parted -s "$DISK" set 1 esp on || handle_error "Failed to set ESP flag."
parted -s "$DISK" mkpart primary ext4 512MiB 20GiB || handle_error "Failed to create / partition."
parted -s "$DISK" mkpart primary ext4 20GiB 100% || handle_error "Failed to create /home partition."
log "Disk partitioned successfully."

# Set up LUKS encryption for / and /home
log "Setting up LUKS encryption..."
cryptsetup luksFormat "${DISK}p2" || handle_error "Failed to format LUKS for /."
cryptsetup luksFormat "${DISK}p3" || handle_error "Failed to format LUKS for /home."
cryptsetup luksOpen "${DISK}p2" cryptroot || handle_error "Failed to open LUKS for /."
cryptsetup luksOpen "${DISK}p3" crypthome || handle_error "Failed to open LUKS for /home."
log "LUKS encryption set up."

# Format partitions
mkfs.vfat -F32 "${DISK}p1" || handle_error "Failed to format /boot."
mkfs.ext4 /dev/mapper/cryptroot || handle_error "Failed to format /."
mkfs.ext4 /dev/mapper/crypthome || handle_error "Failed to format /home."
log "Partitions formatted."

# Mount partitions
mount /dev/mapper/cryptroot /mnt || handle_error "Failed to mount /."
mkdir -p /mnt/boot /mnt/home
mount "${DISK}p1" /mnt/boot || handle_error "Failed to mount /boot."
mount /dev/mapper/crypthome /mnt/home || handle_error "Failed to mount /home."
log "Partitions mounted."

# Install base system
log "Installing base system..."
debootstrap noble /mnt http://archive.ubuntu.com/ubuntu/ || handle_error "Debootstrap failed."
log "Base system installed."

# Configure fstab
log "Configuring fstab..."
echo "UUID=$(blkid -s UUID -o value ${DISK}p1) /boot vfat defaults 0 2" >> /mnt/etc/fstab
echo "/dev/mapper/cryptroot / ext4 defaults 0 1" >> /mnt/etc/fstab
echo "/dev/mapper/crypthome /home ext4 defaults 0 2" >> /mnt/etc/fstab
log "fstab configured."

# Chroot into the new system
log "Chrooting into new system..."
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys
chroot /mnt /bin/bash << 'EOF'
set -e

# Set hostname
echo "$HOSTNAME" > /etc/hostname
echo "127.0.0.1 localhost $HOSTNAME" >> /etc/hosts

# Update package lists
apt-get update

# Install essential packages
apt-get install -y linux-generic openbox plank nvidia-driver-550 network-manager cryptsetup grub-efi-amd64 || exit 1

# Install Steam if selected
if [ "$STEAM_INSTALL" -eq 0 ]; then
    apt-get install -y steam
fi

# Set up user
useradd -m -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd

# Configure Openbox
mkdir -p /home/$USERNAME/.config/openbox
cp /usr/share/openbox/menu.xml /home/$USERNAME/.config/openbox/
echo "exec openbox-session" > /home/$USERNAME/.xinitrc
chown -R $USERNAME:$USERNAME /home/$USERNAME/.config /home/$USERNAME/.xinitrc

# Install and configure Plank with macOS Mojave theme
apt-get install -y wget unzip
wget https://www.gnome-look.org/p/1248226 -O /tmp/mojave-theme.zip
unzip /tmp/mojave-theme.zip -d /usr/share/plank/themes/
echo "[Plank]\ntheme=Mojave" > /home/$USERNAME/.config/plank/plank.ini
chown $USERNAME:$USERNAME /home/$USERNAME/.config/plank

# Configure autologin
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat << 'AUTOLOGIN' > /etc/systemd/system/getty@tty1.service.d/override.conf
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USERNAME --noclear %I $TERM
AUTOLOGIN
systemctl enable getty@tty1.service

# Install GRUB
grub-install --target=x86_64-efi --efi-directory=/boot
update-grub

# Configure crypttab
echo "cryptroot UUID=$(blkid -s UUID -o value ${DISK}p2) none luks" >> /etc/crypttab
echo "crypthome UUID=$(blkid -s UUID -o value ${DISK}p3) none luks" >> /etc/crypttab

exit
EOF
log "Chroot configuration completed."

# Unmount everything
umount /mnt/dev /mnt/proc /mnt/sys /mnt/boot /mnt/home /mnt
cryptsetup luksClose cryptroot
cryptsetup luksClose crypthome
log "Installation completed successfully."

dialog --title "Installation Complete" --msgbox "Ubuntu Mini High has been installed! Reboot to start using your system." 7 60
