#!/bin/bash

# generate-iso.sh
# Creates a bootable ubuntu-mini-high ISO with the installer script

# Exit on error
set -e

# Enable debug output
set -x

# Logging setup
LOG_FILE="/var/log/ubuntu-mini-high-iso.log"
echo "Starting ISO generation at $(date)" >> "$LOG_FILE"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root" | tee -a "$LOG_FILE"
  exit 1
fi

# Install penguins-eggs if not present
if ! command -v eggs >/dev/null; then
  echo "Installing penguins-eggs..." | tee -a "$LOG_FILE"
  apt-get update | tee -a "$LOG_FILE"
  apt-get install -y wget curl | tee -a "$LOG_FILE"

  # Try downloading the latest penguins-eggs package from SourceForge
  LATEST_DEB_URL=$(curl -s https://sourceforge.net/projects/penguins-eggs/files/DEBS/ | grep -oP 'href="https://sourceforge.net/projects/penguins-eggs/files/DEBS/penguins-eggs_[0-9]+\.[0-9]+\.[0-9]+-[0-9]+_amd64\.deb/download"' | head -1 | cut -d'"' -f2)
  if [ -n "$LATEST_DEB_URL" ]; then
    echo "Downloading $LATEST_DEB_URL..." | tee -a "$LOG_FILE"
    wget -O /tmp/penguins-eggs.deb "$LATEST_DEB_URL" | tee -a "$LOG_FILE"
    dpkg -i /tmp/penguins-eggs.deb | tee -a "$LOG_FILE"
    apt-get install -f -y | tee -a "$LOG_FILE"
    rm /tmp/penguins-eggs.deb
  else
    echo "Failed to find penguins-eggs package on SourceForge. Trying PPA..." | tee -a "$LOG_FILE"
    apt-get install -y software-properties-common | tee -a "$LOG_FILE"
    curl -fsSL https://pieroproietti.github.io/penguins-eggs-ppa/KEY.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/penguins-eggs.gpg | tee -a "$LOG_FILE"
    echo "deb [arch=$(dpkg --print-architecture)] https://pieroproietti.github.io/penguins-eggs-ppa ./" > /etc/apt/sources.list.d/penguins-eggs.list
    apt-get update | tee -a "$LOG_FILE"
    if apt-get install -y penguins-eggs | tee -a "$LOG_FILE"; then
      echo "penguins-eggs installed via PPA" | tee -a "$LOG_FILE"
    else
      echo "PPA installation failed. Trying npm as fallback..." | tee -a "$LOG_FILE"
      apt-get install -y nodejs npm | tee -a "$LOG_FILE"
      npm install -g penguins-eggs | tee -a "$LOG_FILE"
    fi
  fi
fi

# Create working directory
WORK_DIR="/tmp/ubuntu-mini-high-iso"
mkdir -p "$WORK_DIR" | tee -a "$LOG_FILE"

# Download Ubuntu Minimal ISO or fallback to Server ISO
MINIMAL_ISO_URL="https://cdimage.ubuntu.com/ubuntu-mini-iso/noble/daily-live/current/noble-mini-iso-amd64.iso"
SERVER_ISO_URL="https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso"
ISO_PATH="$WORK_DIR/ubuntu-base.iso"

echo "Attempting to download Ubuntu Minimal ISO from $MINIMAL_ISO_URL..." | tee -a "$LOG_FILE"
if wget -O "$ISO_PATH" "$MINIMAL_ISO_URL" | tee -a "$LOG_FILE"; then
  echo "Ubuntu Minimal ISO downloaded successfully" | tee -a "$LOG_FILE"
else
  echo "Failed to download Minimal ISO. Falling back to Server ISO from $SERVER_ISO_URL..." | tee -a "$LOG_FILE"
  if ! wget -O "$ISO_PATH" "$SERVER_ISO_URL" | tee -a "$LOG_FILE"; then
    echo "Error: Failed to download both Minimal and Server ISOs. Exiting." | tee -a "$LOG_FILE"
    exit 1
  fi
  echo "Ubuntu Server ISO downloaded successfully" | tee -a "$LOG_FILE"
fi

# Verify ISO checksum (if available)
CHECKSUM_URL=$(dirname "$MINIMAL_ISO_URL")/SHA256SUMS
if curl -s "$CHECKSUM_URL" | grep "$(sha256sum "$ 0;" "$ISO_PATH" | cut -d' ' -f1)"; then
  echo "ISO checksum verified" | tee -a "$LOG_FILE"
else
  echo "Warning: ISO checksum verification failed or not available" | tee -a "$LOG_FILE"
fi

# Mount and extract ISO
mkdir -p "$WORK_DIR/mount" "$WORK_DIR/extract" | tee -a "$LOG_FILE"
mount -o loop "$ISO_PATH" "$WORK_DIR/mount" | tee -a "$LOG_FILE"
rsync -av "$WORK_DIR/mount/" "$WORK_DIR/extract/" | tee -a "$LOG_FILE"
umount "$WORK_DIR/mount" | tee -a "$LOG_FILE"

# Copy installer script to ISO
cp ubuntu-minimal-install.sh "$WORK_DIR/extract/install.sh" | tee -a "$LOG_FILE"
chmod +x "$WORK_DIR/extract/install.sh" | tee -a "$LOG_FILE"

# Modify GRUB configuration to include installer option
GRUB_CFG="$WORK_DIR/extract/boot/grub/grub.cfg"
if [ ! -f "$GRUB_CFG" ]; then
  echo "Error: GRUB configuration file ($GRUB_CFG) not found. Exiting." | tee -a "$LOG_FILE"
  exit 1
fi

# Backup original GRUB config
cp "$GRUB_CFG" "$GRUB_CFG.bak" | tee -a "$LOG_FILE"

# Add custom GRUB menu entry for ubuntu-mini-high installer
cat << EOF >> "$GRUB_CFG"

menuentry "Install ubuntu-mini-high" {
    set root=(cd0)
    linux /casper/vmlinuz boot=casper quiet splash --
    initrd /casper/initrd
    boot
}
EOF
echo "Added GRUB menu entry for ubuntu-mini-high" | tee -a "$LOG_FILE"

# Ensure GRUB timeout is set to show the menu
sed -i 's/timeout=0/timeout=10/' "$GRUB_CFG" | tee -a "$LOG_FILE"
echo "Set GRUB timeout to 10 seconds" | tee -a "$LOG_FILE"

# Generate new ISO with penguins-eggs
cd "$WORK_DIR/extract"
echo "Running penguins-eggs to generate ISO..." | tee -a "$LOG_FILE"
eggs produce --prefix ubuntu-mini-high --basename ubuntu-mini-high-v1.0.iso --release --nointeractive --verbose | tee -a "$LOG_FILE"

# Move the generated ISO from /home/eggs/ to the final location
ISO_SRC="/home/eggs/ubuntu-mini-high*.iso"
if ls $ISO_SRC >/dev/null 2>&1; then
  mv $ISO_SRC "/tmp/ubuntu-mini-high.iso" | tee -a "$LOG_FILE"
  echo "Moved ISO to /tmp/ubuntu-mini-high.iso" | tee -a "$LOG_FILE"
else
  echo "Error: No ISO found in /home/eggs/. Exiting." | tee -a "$LOG_FILE"
  exit 1
fi

# Clean up
rm -rf "$WORK_DIR" | tee -a "$LOG_FILE"

echo "ISO generated at /tmp/ubuntu-mini-high.iso" | tee -a "$LOG_FILE"
echo "ISO generation completed at $(date)" >> "$LOG_FILE"

exit 0
