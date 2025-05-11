# Ubuntu-mini-high

**Ubuntu-mini-high** is a lightweight, customizable Ubuntu-based Linux distribution inspired by the minimalism of Arch Linux and the user-friendliness of Pop!_OS. It features a minimal installation with the Openbox window manager, a macOS Mojave-themed Plank dock, default LUKS disk encryption, and support for NVIDIA drivers and Steam. The installer uses a Text User Interface (TUI) for easy configuration, making it ideal for users seeking a bloat-free, gaming-ready system with a sleek interface.

This project includes two main scripts:
- `ubuntu-minimal-install.sh`: Configures a minimal Ubuntu system with your chosen settings.
- `generate-iso.sh`: Creates a bootable ISO with the installer script included.

Hosted at: [https://github.com/andremillet/ubuntu-mini-high](https://github.com/andremillet/ubuntu-mini-high)

## Features

- **Minimal Ubuntu Base**: Built on Ubuntu 24.04 (Noble Numbat) using `debootstrap` for a bloat-free system, inspired by Arch Linux and Pop!_OS.
- **Openbox Window Manager**: Lightweight and customizable, paired with `tint2` for a taskbar.
- **macOS Mojave Theme**: McMojave GTK theme and Plank dock styled like macOS Mojave ([source](https://www.gnome-look.org/p/1248226)).
- **LUKS Disk Encryption**: Default encryption for the root partition, with optional encryption for `/home`.
- **Separate /home Partition**: Configured by default for better data management.
- **NVIDIA Support**: Automatically detects and installs NVIDIA drivers (e.g., `nvidia-driver-550`) for gaming and performance.
- **Steam Compatibility**: Optional Steam installation prompted via TUI, ensuring gaming readiness.
- **Text User Interface (TUI)**: Dialog-based interface for selecting disks, encryption options, and Steam installation.
- **Error Recovery**: Partition table backups, detailed logging, and user confirmations for critical steps.
- **Bootable ISO**: Generate a custom ISO with the installer script using `penguins-eggs`.

## Requirements

- A system with Ubuntu 24.04 (Noble Numbat) or compatible for running `generate-iso.sh`.
- Root privileges (`sudo`) for script execution.
- Internet connection for downloading packages and the Ubuntu Minimal ISO.
- At least 4GB of RAM and 20GB of disk space for installation.
- For SSH users: Ensure you can monitor terminal output (e.g., via `tee debug.log`).
- For testing: A virtual machine (e.g., QEMU, VirtualBox) or USB drive to boot the ISO.

## Installation

### Step 1: Clone the Repository

Clone the project to your system:

    git clone https://github.com/andremillet/ubuntu-mini-high.git
    cd ubuntu-mini-high

### Step 2: Generate the ISO

Run the `generate-iso.sh` script to create a bootable ISO:

    sudo bash ./generate-iso.sh | tee debug.log

- The script downloads the Ubuntu Minimal ISO, integrates `ubuntu-minimal-install.sh`, and generates the ISO at `/tmp/ubuntu-mini-high.iso`.
- Monitor progress in `debug.log` or `/var/log/ubuntu-mini-high-iso.log`.
- If running via SSH, ensure non-interactive execution works (the script uses `--nointeractive` for `penguins-eggs`).

### Step 3: Test or Burn the ISO

Test the ISO in a virtual machine:

    qemu-system-x86_64 -cdrom /tmp/ubuntu-mini-high.iso -m 2G

Or burn it to a USB drive (replace `/dev/sdX` with your USB device):

    sudo dd if=/tmp/ubuntu-mini-high.iso of=/dev/sdX bs=4M status=progress && sync

### Step 4: Install Ubuntu-mini-high

1. Boot the ISO. Use the live CD credentials:
   - User: `live` / Password: `evolution`
   - Root: `root` / Password: `evolution`
2. Select the "Install ubuntu-mini-high" option from the GRUB menu.
3. In the live environment, run the installer manually:
       sudo /install.sh
4. Follow the TUI prompts to:
   - Select the installation disk (warning: this erases the disk).
   - Choose whether to encrypt the `/home` partition.
   - Decide whether to install Steam.
   - Confirm settings before proceeding.
5. After installation, reboot into your new system.

**Note**: The installer is not yet automated to run at boot. To automate, modify the GRUB entry or live system’s init scripts (see [Contributing](#contributing)).

## Scripts

### `ubuntu-minimal-install.sh`

- **Purpose**: Configures a minimal Ubuntu system with Openbox, Plank, LUKS encryption, and optional NVIDIA/Steam support.
- **Features**:
  - TUI for disk selection, encryption, and Steam.
  - Partitions: 512MB `/boot` (FAT32), 20GB `/` (ext4, encrypted), remainder `/home` (ext4, optionally encrypted).
  - Installs minimal Ubuntu via `debootstrap`.
  - Configures Openbox with a macOS Mojave-themed Plank dock.
  - Detects NVIDIA GPUs and installs drivers.
  - Logs actions to `/var/log/ubuntu-mini-high-install.log`.
  - Backs up partition table for recovery.

### `generate-iso.sh`

- **Purpose**: Creates a bootable ISO with the installer script.
- **Features**:
  - Downloads the Ubuntu Minimal ISO (or falls back to Server ISO).
  - Integrates `ubuntu-minimal-install.sh` as `/install.sh`.
  - Modifies GRUB to include an "Install ubuntu-mini-high" option.
  - Uses `penguins-eggs` for ISO generation, with non-interactive execution for SSH compatibility.
  - Logs to `/var/log/ubuntu-mini-high-iso.log` and supports real-time monitoring.

## Troubleshooting

- **ISO Generation Fails**:
  - Check `/var/log/ubuntu-mini-high-iso.log` and `debug.log` for errors.
  - Ensure `penguins-eggs` is installed (`command -v eggs`).
  - Run `eggs produce` manually for detailed output:
        cd /tmp/ubuntu-mini-high-iso/extract
        eggs produce --prefix ubuntu-mini-high --basename ubuntu-mini-high-v1.0.iso --release --nointeractive --verbose
  - Contact `penguins-eggs` support via [Telegram](https://t.me/penguins_eggs).

- **Installer Fails in Live Environment**:
  - Debug `/install.sh` manually:
        sudo /install.sh
  - Check `/var/log/ubuntu-mini-high-install.log` for errors.
  - Ensure the live system has enough RAM and disk space.

- **Jellyfin GPG Warning**:
  - Fix the deprecated keyring warning:
        sudo apt-key export repo.jellyfin.org | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/jellyfin.gpg

- **No ISO in `/tmp`**:
  - Check `/home/eggs/` for the generated ISO (e.g., `ubuntu-mini-high*.iso`):
        ls /home/eggs/
  - Move it manually if needed:
        mv /home/eggs/ubuntu-mini-high*.iso /tmp/ubuntu-mini-high.iso

## Contributing

Contributions are welcome! To contribute:

1. Fork the repository.
2. Create a branch (`git checkout -b feature/your-feature`).
3. Make changes and commit (`git commit -m "Add your feature"`).
4. Push to your fork (`git push origin feature/your-feature`).
5. Open a pull request.

**Ideas for Contributions**:
- Automate the installer to run at boot (e.g., modify `casper/filesystem.squashfs`).
- Add support for other window managers or themes.
- Enhance TUI with additional options (e.g., package selection).
- Improve error recovery with rollback mechanisms.
- Support alternative ISO generation tools (e.g., `Cubic`, `mkisofs`).

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Inspired by [Arch Linux](https://archlinux.org/) and [Pop!_OS](https://pop.system76.com/).
- McMojave theme by [vinceliuice](https://github.com/vinceliuice/Mojave-gtk-theme).
- Plank dock theme by [paulxfce](https://github.com/paulxfce/mcOS-Mojave-for-Plank-Dock).
- Powered by [penguins-eggs](https://github.com/pieroproietti/penguins-eggs).
- Ubuntu Minimal ISO from [cdimage.ubuntu.com](https://cdimage.ubuntu.com/).

## Contact

For issues, suggestions, or questions, open an issue on GitHub or contact the maintainer at [andremillet](https://github.com/andremillet).
