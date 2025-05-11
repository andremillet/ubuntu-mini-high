#!/bin/bash

# ubuntu-minimal-install.sh
# Ubuntu-mini-high installer for a minimal Ubuntu with Openbox, LUKS encryption, and macOS Mojave theme

# Exit on error
set -e

# Logging setup
LOG_FILE="/var/log/ubuntu-mini-high-install.log"
exec 1>>"$LOG_FILE" 2>&1
echo "Starting ubuntu-mini-high installation at $(date)"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Check for live environment (Desktop ISO uses /cdrom/casper)
if [ -d /cdrom/casper ]; then
  echo "Detected live environment, adjusting for compatibility..."
  # Ensure writable /tmp
  mount -o remount,rw /tmp 2>/dev/null || true
  # Unmount any conflicting mounts
  umount /mnt/* 2>/dev/null || true
fi

# Verify required tools are installed
for cmd in dialog debootstrap parted cryptsetup; do
  if ! command -v $cmd >/dev/null; then
    echo "Error: $cmd is not installed. Please install it and try again."
    exit 1
  fi
done

# Default variables
DISK=""
ENCRYPT_HOME="no"
STEAM_INSTALL="no"

# TUI: Welcome screen
dialog --title "Ubuntu-mini-high Installer" --msgbox "Welcome to the ubuntu-mini-high installer!\nThis will set up a minimal Ubuntu with Openbox, LUKS encryption, and a macOS Mojave-like theme." 10 60

# TUI: Select disk
DISKS=$(lsblk -d -n -o NAME | grep -E '^sd|^nvme')
DISK=$(dialog --title "Select Disk" --menu "Choose the disk to install Ubuntu on (WARNING: This will erase the disk!)" 15 60 5 \
  $DISKS 2>&1 >/dev/tty)
if [ -z "$DISK" ]; then
  dialog --msgbox "No disk selected. Exiting." 6 40
  exit 1
fi
DISK="/dev/$DISK"

# TUI: Encrypt /home partition?
ENCRYPT_HOME=$(dialog --title "Encrypt /home" --yesno "Do you want to encrypt the /home partition separately?" 7 50 && echo "yes" || echo "no")

# TUI: Install Steam?
STEAM_INSTALL=$(dialog --title "Install Steam" --yesno "Do you want to install Steam?" 7 50 && echo "yes" || echo "no")

# Confirm settings
dialog --title "Confirm Settings" --yesno "Disk: $DISK\nEncrypt /home: $ENCRYPT_HOME\nInstall Steam: $STEAM_INSTALL\n\nProceed with installation?" 10 60
if [ $? -ne 0 ]; then
  dialog --msgbox "Installation cancelled." 6 40
  exit 1
fi

# Backup partition table (error recovery)
sfdisk --dump "$DISK" > /tmp/partition_table_backup
echo "Partition table backed up to /tmp/partition_table_backup"

# Partition the disk: 512MB /boot, 20GB /, remainder /home
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart primary fat32 1MiB 513MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary ext4 513MiB 20513MiB
parted -s "$DISK" mkpart primary ext4 20513MiB 100%
partprobe "$DISK"

# Setup LUKS encryption for root
cryptsetup luksFormat "${DISK}p2"
cryptsetup open "${DISK}p2" cryptroot
mkfs.ext4 /dev/mapper/cryptroot

# Setup /home partition (encrypted or not)
if [ "$ENCRYPT_HOME" = "yes" ]; then
  cryptsetup luksFormat "${DISK}p3"
  cryptsetup open "${DISK}p3" crypthome
  mkfs.ext4 /dev/mapper/crypthome
else
  mkfs.ext4 "${DISK}p3"
fi

# Format /boot
mkfs.vfat "${DISK}p1"

# Mount partitions
mount /dev/mapper/cryptroot /mnt
mkdir -p /mnt/boot /mnt/home
mount "${DISK}p1" /mnt/boot
if [ "$ENCRYPT_HOME" = "yes" ]; then
  mount /dev/mapper/crypthome /mnt/home
else
  mount "${DISK}p3" /mnt/home
fi

# Install minimal Ubuntu (Noble)
apt-get update
apt-get install -y debootstrap
debootstrap noble /mnt http://archive.ubuntu.com/ubuntu/
echo "Minimal Ubuntu base installed"

# Configure fstab
UUID_BOOT=$(blkid -s UUID -o value "${DISK}p1")
UUID_ROOT=$(blkid -s UUID -o value "${DISK}p2")
UUID_HOME=$(blkid -s UUID -o value "${DISK}p3")
cat << EOF > /mnt/etc/fstab
UUID=$UUID_BOOT /boot vfat defaults 0 2
/dev/mapper/cryptroot / ext4 defaults 0 1
/dev/mapper/crypthome /home ext4 defaults 0 2
EOF

# Chroot setup
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys
cp /etc/resolv.conf /mnt/etc/resolv.conf

# Install kernel, GRUB, and essential packages
chroot /mnt apt-get update
chroot /mnt apt-get install -y linux-generic grub-efi-amd64 openbox obconf plank tint2 nitrogen
chroot /mnt grub-install "$DISK"
chroot /mnt update-grub

# Install NVIDIA drivers if detected
if lspci | grep -i nvidia >/dev/null; then
  chroot /mnt apt-get install -y nvidia-driver-550
  echo "NVIDIA drivers installed"
fi

# Install Steam if selected
if [ "$STEAM_INSTALL" = "yes" ]; then
  chroot /mnt apt-get install -y steam
  echo "Steam installed"
fi

# Install McMojave theme and Plank dock theme
chroot /mnt apt-get install -y git
chroot /mnt git clone https://github.com/vinceliuice/Mojave-gtk-theme.git /tmp/Mojave-gtk-theme
chroot /mnt /tmp/Mojave-gtk-theme/install.sh
chroot /mnt git clone https://github.com/paulxfce/mcOS-Mojave-for-Plank-Dock.git /tmp/mcOS-Mojave-Plank
chroot /mnt cp -r /tmp/mcOS-Mojave-Plank/McOS-Mojave /usr/share/plank/themes/

# Configure Openbox autostart
mkdir -p /mnt/etc/xdg/openbox
cat << EOF > /mnt/etc/xdg/openbox/autostart
tint2 &
plank &
nitrogen --restore &
EOF

# Set up user
chroot /mnt useradd -m -s /bin/bash user
chroot /mnt passwd user

# Clean up
umount /mnt/dev /mnt/proc /mnt/sys /mnt/boot /mnt/home /mnt
if [ "$ENCRYPT_HOME" = "yes" ]; then
  cryptsetup close crypthome
fi
cryptsetup close cryptroot

# Finalize
dialog --title "Installation Complete" --msgbox "Ubuntu-mini-high installation complete! Reboot to start using your system." 6 60
echo "Installation completed successfully at $(date)" >> "$LOG_FILE"

exit 0
