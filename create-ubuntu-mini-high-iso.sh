#!/bin/bash

# create-ubuntu-mini-high-iso.sh
# Script to generate ubuntu-mini-high ISO using Cubic

# Exit on error
set -e

# Variables
PROJECT_DIR="$HOME/cubic-projects/ubuntu-mini-high"
ISO_URL="http://releases.ubuntu.com/noble/ubuntu-24.04-live-server-amd64.iso"
ISO_FILE="ubuntu-24.04-live-server-amd64.iso"
CUSTOM_ISO="ubuntu-mini-high.iso"
INSTALL_SCRIPT="ubuntu-minimal-install.sh"
GITHUB_REPO="https://raw.githubusercontent.com/andremillet/ubuntu-mini-high/main"

# Logging
LOG_FILE="/var/log/cubic-ubuntu-mini-high.log"
exec 1>>"$LOG_FILE" 2>&1
echo "Starting ISO creation at $(date)"

# Install Cubic
echo "Installing Cubic..."
sudo apt-add-repository ppa:cubic-wizard/release -y
sudo apt update
sudo apt install -y cubic

# Create project directory
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# Download Ubuntu Server ISO
if [ ! -f "$ISO_FILE" ]; then
    echo "Downloading Ubuntu Server ISO..."
    wget "$ISO_URL" -O "$ISO_FILE"
fi

# Start Cubic in automated mode
echo "Launching Cubic..."
cubic "$PROJECT_DIR" &

# Wait for Cubic to initialize
sleep 10

# Automate Cubic steps (simulating GUI interaction)
echo "Configuring Cubic project..."
echo "$ISO_FILE" > "$PROJECT_DIR/original-iso"
echo "ubuntu-mini-high" > "$PROJECT_DIR/custom-iso-name"
echo "noble" > "$PROJECT_DIR/release-name"

# Chroot commands to embed install script
cat << EOF > "$PROJECT_DIR/chroot-commands.sh"
#!/bin/bash
apt-get update
apt-get install -y curl
curl -O "$GITHUB_REPO/$INSTALL_SCRIPT" -o /usr/local/bin/$INSTALL_SCRIPT
chmod +x /usr/local/bin/$INSTALL_SCRIPT
echo "[Desktop Entry]" > /etc/xdg/autostart/ubuntu-mini-high.desktop
echo "Name=Ubuntu Mini High Installer" >> /etc/xdg/autostart/ubuntu-mini-high.desktop
echo "Exec=/usr/local/bin/$INSTALL_SCRIPT" >> /etc/xdg/autostart/ubuntu-mini-high.desktop
echo "Type=Application" >> /etc/xdg/autostart/ubuntu-mini-high.desktop
echo "Terminal=true" >> /etc/xdg/autostart/ubuntu-mini-high.desktop
EOF

chmod +x "$PROJECT_DIR/chroot-commands.sh"
sudo chroot "$PROJECT_DIR/chroot" /bin/bash /chroot-commands.sh

# Generate ISO
echo "Generating ISO..."
cubic --generate "$PROJECT_DIR" "$CUSTOM_ISO"

# Move ISO to project directory
mv "$PROJECT_DIR/$CUSTOM_ISO" "$PROJECT_DIR/../$CUSTOM_ISO"

# Clean up
echo "Cleaning up..."
rm -rf "$PROJECT_DIR"

echo "ISO created at $PROJECT_DIR/../$CUSTOM_ISO"
echo "ISO creation completed at $(date)" >> "$LOG_FILE"
