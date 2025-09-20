# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Type

This is a **NixOS configuration repository** using Nix Flakes for personal system configuration with:
- Single-host NixOS system configuration
- Home Manager for user environment management
- Modular profile-based architecture
- Custom packages (cursor-appimage, yandex-music)
- Modern CLI tools and development environment

## Common Development Commands

### System Rebuild and Management
```bash
# Rebuild and switch to new configuration
sudo nixos-rebuild switch --flake .#nixos

# Test configuration without switching
sudo nixos-rebuild test --flake .#nixos

# Build configuration without activating
sudo nixos-rebuild build --flake .#nixos

# Check flake configuration for errors
nix flake check

# Show flake structure and outputs
nix flake show
```

### Flake Updates and Maintenance
```bash
# Update all flake inputs to latest versions
nix flake update

# Update specific input only
nix flake lock --update-input nixpkgs

# Garbage collection to free disk space
sudo nix-collect-garbage -d

# List system generations
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# Optimize nix store
nix-store --optimise
```

### Development
```bash
# Enter development shell with Nix tools
nix develop

# Format Nix files
nixpkgs-fmt <file.nix>

# Lint Nix files for common issues
statix check

# Find dead Nix code
deadnix
```

## Architecture Overview

### Flake Structure
- **flake.nix**: Main configuration for single host
- **flake.lock**: Pins all dependencies for reproducible builds

### Key Directories
- **hosts/**: Host-specific configurations
  - `default/`: Main host configuration with hardware config

- **profiles/**: Modular system profiles
  - `base.nix`: Core system settings
  - `desktop-gnome.nix`: GNOME desktop environment
  - `nvidia.nix`: NVIDIA GPU configuration
  - `docker.nix`: Docker runtime
  - `security-hardened.nix`: Security enhancements
  - `system-optimizations.nix`: Performance optimizations

- **home/**: Home Manager configurations
  - `minimal.nix`: Minimal user configuration
  - `users/semyenov.nix`: Primary user configuration
  - `profiles/`: Modular Home Manager profiles
    - `common.nix`: Basic home settings
    - `desktop.nix`: Desktop applications
    - `sysadmin.nix`: System administration tools

- **packages/**: Custom packages
  - `cursor-appimage.nix`: Cursor AI editor
  - `yandex-music.nix`: Yandex Music app

- **overlays/**: Package overlays
  - `default.nix`: Custom package modifications

### Configuration Patterns
1. **Flake Inputs**: nixpkgs stable (25.05), nixpkgs-unstable, home-manager (25.05)
2. **Profile-Based Architecture**: Modular profiles for easy feature composition
3. **Overlay System**: Unstable packages accessible via `unstable.<package>`
4. **Modern CLI Tools**: Comprehensive modern CLI replacements (bat, ripgrep, fd, lsd, etc.)
5. **Shell Aliases**: Configured to use modern tool replacements by default
6. **Home Manager Integration**: Runs as NixOS module with profile-based configurations

### Important Configuration Details
- **Primary User**: "semyenov" (UID: 1000, GID: 1000)
- **Default Shell**: Fish shell
- **System State Version**: 24.11 (for stateful data compatibility)
- **Experimental Features**: Flakes and nix-command enabled
- **Binary Caches**: nixos.org and nix-community configured
- **Garbage Collection**: Weekly automatic cleanup keeping 30 days
- **Auto-optimization**: Nix store auto-optimization enabled

## Current System Stack

### Desktop Environment
- GNOME with Wayland
- NVIDIA drivers with CUDA support
- PipeWire audio system
- RecMono Nerd Font as default monospace font

### Included Applications
- **Browsers**: Brave, Chromium
- **Media**: VLC, Spotify
- **Development**: Cursor AI, VS Code, Node.js, Bun
- **Communication**: Telegram Desktop, Thunderbird
- **Productivity**: Obsidian, LibreOffice
- **Custom**: Yandex Music, Nekoray proxy

### Development Tools
- **Version Control**: git, lazygit, delta, gitui
- **Containers**: Docker, docker-compose, lazydocker, dive
- **Kubernetes**: kubectl, k9s, helm, kind
- **Infrastructure**: terraform, ansible
- **Cloud CLIs**: AWS, GCP, Azure
- **Databases**: PostgreSQL, MySQL, Redis clients
- **Language Servers**: nil, nixd (both Nix LSPs)

### System Administration
- **Monitoring**: btop, htop, iotop, nethogs, bandwhich
- **Network**: nmap, tcpdump, wireshark, traceroute
- **Security**: lynis, aide, fail2ban
- **Backup**: restic, borgbackup, rsync
- **Modern CLI**: bat, ripgrep, fd, lsd, dust, duf, procs

## Adding New Features

### To modify the configuration:
1. Edit relevant files in `profiles/` or `home/profiles/`
2. Test with `sudo nixos-rebuild test --flake .#nixos`
3. Apply with `sudo nixos-rebuild switch --flake .#nixos`

### To add new packages:
1. Add to `environment.systemPackages` in appropriate profile
2. Or add to `home.packages` in user configuration
3. Custom packages go in `packages/` directory

## Important Notes

- Always use `nix flake check` before committing changes
- Run `nixpkgs-fmt` on modified files for consistent formatting
- The configuration is for personal use on a single host
- Shell aliases use modern tool replacements by default
- NVIDIA and Docker support are included in the base configuration