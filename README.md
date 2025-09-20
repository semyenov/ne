# NixOS Configuration

A clean, modular NixOS configuration using Nix Flakes for reproducible system setup.

## 🚀 Quick Start

```bash
# Clone this repository
git clone <repository-url> ~/nixos-config
cd ~/nixos-config

# Build and switch to the configuration
sudo nixos-rebuild switch --flake .#nixos

# Update flake inputs
nix flake update

# Check configuration
nix flake check
```

## 📁 Project Structure

```
.
├── flake.nix              # Main flake configuration
├── flake.lock             # Locked dependencies
│
├── hosts/                 # Host-specific configurations
│   └── default/          # Default host configuration
│       ├── configuration.nix
│       └── hardware-configuration.nix
│
├── profiles/             # Modular system profiles
│   ├── base.nix         # Core system settings
│   ├── desktop-gnome.nix # GNOME desktop environment
│   ├── nvidia.nix       # NVIDIA GPU drivers
│   ├── docker.nix       # Docker containerization
│   ├── security-hardened.nix # Security enhancements
│   └── system-optimizations.nix # Performance tweaks
│
├── home/                 # Home Manager configurations
│   ├── minimal.nix      # Minimal user configuration
│   ├── users/           # User-specific configs
│   │   └── semyenov.nix # Primary user configuration
│   └── profiles/        # Home Manager profiles
│       ├── common.nix   # Common user settings
│       ├── desktop.nix  # Desktop applications
│       └── sysadmin.nix # System administration tools
│
├── packages/            # Custom packages
│   ├── cursor-appimage.nix # Cursor AI editor
│   └── yandex-music.nix    # Yandex Music app
│
└── overlays/            # Package overlays
    └── default.nix      # Custom package modifications
```

## 🎯 Features

### System Features
- **Modular Configuration**: Clean separation of concerns with profiles
- **NVIDIA Support**: Full NVIDIA GPU drivers with CUDA support
- **Modern Desktop**: GNOME with Wayland support
- **Development Tools**: Comprehensive development environment
- **Security Hardening**: Optional security enhancements
- **Performance Optimizations**: System-level performance tweaks

### Included Software

#### Desktop Applications
- Brave, Chromium browsers
- VLC, Spotify media players
- OBS Studio for streaming
- Obsidian for note-taking
- LibreOffice suite
- Cursor AI editor
- Yandex Music
- Telegram Desktop
- Nekoray proxy client

#### Development Tools
- Git with modern tools (lazygit, delta, gitui)
- Node.js, Bun runtimes
- Docker & Docker Compose
- Kubernetes tools (kubectl, k9s, helm)
- Cloud CLIs (AWS, GCP, Azure)
- Database clients (PostgreSQL, MySQL, Redis)
- Modern CLI replacements (bat, ripgrep, fd, lsd, etc.)

#### System Administration
- Monitoring: btop, htop, iotop, nethogs, bandwhich
- Network: nmap, tcpdump, wireshark, traceroute
- Security: lynis, aide, fail2ban
- Backup: restic, borgbackup, rsync
- Container: docker, lazydocker, dive
- Infrastructure: terraform, ansible, packer

### Language Servers
- `nil` - Fast Nix language server
- `nixd` - Evaluation-based Nix language server

## 🔧 Configuration

### Primary User
- Username: `semyenov`
- UID: 1000
- Shell: Fish shell
- Groups: wheel, networkmanager, audio, video, docker, libvirtd

### System Settings
- **Hostname**: nixos
- **Timezone**: UTC
- **Locale**: en_US.UTF-8
- **State Version**: 24.11
- **Experimental Features**: flakes, nix-command

### Shell Aliases
Modern CLI tool replacements are configured:
- `ls` → `lsd` (better ls)
- `cat` → `bat` (syntax highlighting)
- `grep` → `rg` (ripgrep)
- `find` → `fd` (faster find)
- `sed` → `sd` (simpler sed)
- `du` → `dust` (better disk usage)
- `df` → `duf` (better df)
- `ps` → `procs` (better ps)
- `top` → `btm` (bottom)
- `dig` → `dog` (better dig)

## 🛠️ Common Commands

```bash
# System Management
sudo nixos-rebuild switch --flake .#nixos  # Apply configuration
sudo nixos-rebuild test --flake .#nixos    # Test without switching
sudo nixos-rebuild build --flake .#nixos   # Build without activating

# Flake Management
nix flake update                # Update all inputs
nix flake update nixpkgs        # Update specific input
nix flake check                 # Verify configuration
nix flake show                  # Display flake structure

# Maintenance
sudo nix-collect-garbage -d     # Clean old generations
sudo nix-store --optimise       # Optimize store
nix-env --list-generations      # List generations

# Development
nix develop                     # Enter development shell
nixpkgs-fmt .                   # Format Nix files
statix check                    # Lint Nix code
deadnix                         # Find dead code
```

## 📦 Custom Packages

This configuration includes two custom packages:
- **cursor-appimage**: Cursor AI code editor
- **yandex-music**: Yandex Music desktop application

These are available through the overlay and can be installed in user profiles.

## 🔐 Security Notes

The optional `security-hardened` profile provides:
- Firewall with strict rules
- SSH hardening (no root, no password auth)
- Kernel security parameters
- Audit daemon configuration
- Sudo restrictions

## 📈 Performance

The `system-optimizations` profile includes:
- I/O scheduler tuning
- CPU governor optimization
- Memory management improvements
- Network stack tuning
- SSD optimizations

## 📝 License

This configuration is provided as-is for personal use.