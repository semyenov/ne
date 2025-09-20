#!/usr/bin/env bash
# Multi-Host NixOS Setup Script
# Bootstrap and configure multiple NixOS hosts

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Functions
print_header() {
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║    Multi-Host NixOS Setup Script       ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${YELLOW}→${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if running on NixOS
    if [ ! -f /etc/nixos/configuration.nix ] && [ ! -f /etc/NIXOS ]; then
        print_warning "Not running on NixOS, some features may be limited"
    fi
    
    # Check for required tools
    local missing_tools=()
    for tool in git jq nix; do
        if ! command -v $tool &>/dev/null; then
            missing_tools+=($tool)
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        echo "Install them first before running this script"
        exit 1
    fi
    
    # Check if flakes are enabled
    if ! nix flake --help &>/dev/null; then
        print_warning "Nix flakes not enabled"
        echo "Add the following to your configuration:"
        echo "  nix.settings.experimental-features = [ \"nix-command\" \"flakes\" ];"
    fi
    
    print_success "Prerequisites check complete"
}

# Initialize new repository
init_repository() {
    print_info "Initializing NixOS configuration repository..."
    
    # Check if already in a git repo
    if [ -d .git ]; then
        print_info "Already in a git repository"
    else
        git init
        print_success "Git repository initialized"
    fi
    
    # Create directory structure
    mkdir -p hosts profiles home/{users,profiles} packages overlays scripts
    
    print_success "Directory structure created"
}

# Setup host configuration
setup_host() {
    local hostname="${1:-$(hostname)}"
    local host_type="$2"
    
    print_info "Setting up host: $hostname"
    
    # Create host directory
    mkdir -p "hosts/$hostname"
    
    # Generate hardware configuration if on the actual host
    if [ "$(hostname)" = "$hostname" ]; then
        print_info "Generating hardware configuration..."
        nixos-generate-config --show-hardware-config > "hosts/$hostname/hardware-configuration.nix"
        print_success "Hardware configuration generated"
    else
        print_warning "Not on target host, creating placeholder hardware configuration"
        cat > "hosts/$hostname/hardware-configuration.nix" << 'EOF'
# Hardware configuration placeholder
# Generate this on the actual host with:
# nixos-generate-config --show-hardware-config > hardware-configuration.nix
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ ];
  
  # Add hardware configuration here
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
}
EOF
    fi
    
    # Create host configuration based on type
    cat > "hosts/$hostname/configuration.nix" << EOF
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../profiles/base.nix
EOF
    
    # Add profiles based on host type
    case "$host_type" in
        workstation)
            cat >> "hosts/$hostname/configuration.nix" << EOF
    ../../profiles/desktop-gnome.nix
    ../../profiles/nvidia.nix
    ../../profiles/system-optimizations.nix
EOF
            ;;
        server)
            cat >> "hosts/$hostname/configuration.nix" << EOF
    ../../profiles/docker.nix
    ../../profiles/security-hardened.nix
EOF
            ;;
        minimal)
            cat >> "hosts/$hostname/configuration.nix" << EOF
    ../../profiles/security-hardened.nix
EOF
            ;;
    esac
    
    cat >> "hosts/$hostname/configuration.nix" << EOF
  ];

  networking.hostName = "$hostname";
  time.timeZone = "UTC";
  
  # Enable the default user
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    initialPassword = "nixos";  # Change this!
  };

  system.stateVersion = "25.05";
}
EOF
    
    print_success "Host configuration created for $hostname"
}

# Create base profiles
create_base_profiles() {
    print_info "Creating base profiles..."
    
    # Base profile
    cat > profiles/base.nix << 'EOF'
{ config, lib, pkgs, ... }:

{
  # Nix configuration
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
      trusted-users = [ "@wheel" ];
    };
    
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  # Basic system packages
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    tmux
    curl
    wget
    tree
    ncdu
    iotop
    nethogs
  ];

  # Basic networking
  networking = {
    networkmanager.enable = true;
    firewall = {
      enable = true;
      allowPing = true;
    };
  };

  # Enable SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  # Basic localization
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";
}
EOF
    
    print_success "Base profile created"
}

# Create flake.nix
create_flake() {
    print_info "Creating flake.nix..."
    
    # Get list of hosts
    local hosts=(hosts/*/)
    
    cat > flake.nix << 'EOF'
{
  description = "Multi-Host NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, ... }@inputs:
    let
      system = "x86_64-linux";
      
      # Unstable packages overlay
      overlay-unstable = final: prev: {
        unstable = import nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };
      };
      
      # Function to create a host configuration
      mkHost = hostname: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/${hostname}/configuration.nix
          
          # Add overlays
          { nixpkgs.overlays = [ overlay-unstable ]; }
          
          # Add Home Manager
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users.nixos = import ./home/minimal.nix;
            };
          }
        ];
      };
    in {
      # NixOS configurations for each host
      nixosConfigurations = {
EOF
    
    # Add each host
    for host_dir in hosts/*/; do
        if [ -d "$host_dir" ]; then
            local hostname=$(basename "$host_dir")
            echo "        $hostname = mkHost \"$hostname\";" >> flake.nix
        fi
    done
    
    cat >> flake.nix << 'EOF'
      };
      
      # Development shell
      devShells.${system}.default = nixpkgs.legacyPackages.${system}.mkShell {
        packages = with nixpkgs.legacyPackages.${system}; [
          git
          nixpkgs-fmt
          statix
          deadnix
          nil
          nixd
        ];
        
        shellHook = ''
          echo "NixOS Multi-Host Development Environment"
          echo "Available commands:"
          echo "  ./scripts/rebuild.sh - Multi-host rebuild manager"
          echo "  ./scripts/manage-hosts.sh - Host management utility"
          echo "  nix flake check - Check flake configuration"
          echo "  nix flake update - Update flake inputs"
        '';
      };
    };
}
EOF
    
    print_success "flake.nix created"
}

# Interactive setup wizard
setup_wizard() {
    print_header
    
    echo -e "${CYAN}Welcome to Multi-Host NixOS Setup!${NC}"
    echo
    echo "This wizard will help you set up a NixOS configuration"
    echo "repository for managing multiple hosts."
    echo
    
    # Check prerequisites
    check_prerequisites
    echo
    
    # Initialize repository
    read -p "Initialize new repository? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        init_repository
    fi
    echo
    
    # Setup hosts
    echo -e "${CYAN}Host Configuration${NC}"
    echo "How many hosts would you like to configure?"
    read -p "Number of hosts [1]: " num_hosts
    num_hosts=${num_hosts:-1}
    
    for ((i=1; i<=num_hosts; i++)); do
        echo
        echo "Host $i configuration:"
        read -p "  Hostname [$(hostname)]: " hostname
        hostname=${hostname:-$(hostname)}
        
        echo "  Host type:"
        echo "    1) Workstation (Desktop with GUI)"
        echo "    2) Server (Headless)"
        echo "    3) Minimal (Basic system)"
        read -p "  Select type [1]: " host_type_choice
        
        case "$host_type_choice" in
            2) host_type="server" ;;
            3) host_type="minimal" ;;
            *) host_type="workstation" ;;
        esac
        
        setup_host "$hostname" "$host_type"
    done
    
    echo
    
    # Create profiles
    if [ ! -f profiles/base.nix ]; then
        create_base_profiles
    fi
    
    # Create minimal home configuration
    if [ ! -f home/minimal.nix ]; then
        print_info "Creating minimal home configuration..."
        cat > home/minimal.nix << 'EOF'
{ config, pkgs, ... }:

{
  home.stateVersion = "25.05";
  
  programs = {
    bash.enable = true;
    git.enable = true;
    
    direnv = {
      enable = true;
      enableBashIntegration = true;
      nix-direnv.enable = true;
    };
  };
  
  home.sessionVariables = {
    EDITOR = "vim";
  };
}
EOF
        print_success "Minimal home configuration created"
    fi
    
    # Create flake.nix
    create_flake
    
    echo
    
    # Make scripts executable
    if [ -f scripts/rebuild.sh ]; then
        chmod +x scripts/*.sh
        print_success "Scripts made executable"
    fi
    
    # Final steps
    echo
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Setup Complete!${NC}"
    echo
    echo "Next steps:"
    echo "1. Review and customize host configurations in hosts/"
    echo "2. Add user configurations in home/users/"
    echo "3. Test the configuration:"
    echo "   nix flake check"
    echo
    echo "4. Deploy to current host:"
    echo "   sudo nixos-rebuild switch --flake .#$(hostname)"
    echo
    echo "5. Use management scripts:"
    echo "   ./scripts/rebuild.sh - Manage rebuilds"
    echo "   ./scripts/manage-hosts.sh - Manage hosts"
    echo
    echo "Documentation:"
    echo "  • README.md - Project overview"
    echo "  • CLAUDE.md - AI assistant instructions"
    echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
}

# Quick setup for current host only
quick_setup() {
    print_header
    print_info "Quick setup for current host..."
    
    check_prerequisites
    init_repository
    
    # Determine host type
    if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
        host_type="workstation"
    else
        host_type="server"
    fi
    
    setup_host "$(hostname)" "$host_type"
    create_base_profiles
    
    # Simple single-host flake
    cat > flake.nix << 'EOF'
{
  description = "NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, ... }@inputs:
    let
      system = "x86_64-linux";
      hostname = "$(hostname)";
    in {
      nixosConfigurations.${hostname} = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/${hostname}/configuration.nix
          
          { 
            nixpkgs.overlays = [
              (final: prev: {
                unstable = import nixpkgs-unstable {
                  inherit system;
                  config.allowUnfree = true;
                };
              })
            ];
          }
        ];
      };
    };
}
EOF
    
    print_success "Quick setup complete!"
    echo
    echo "Build with: sudo nixos-rebuild switch --flake .#$(hostname)"
}

# Handle command-line arguments
case "${1:-}" in
    quick)
        quick_setup
        ;;
    wizard)
        setup_wizard
        ;;
    --help|-h)
        echo "Usage: $0 [COMMAND]"
        echo
        echo "Commands:"
        echo "  wizard    Run interactive setup wizard (default)"
        echo "  quick     Quick setup for current host only"
        echo
        echo "This script helps bootstrap a NixOS configuration repository"
        echo "for managing single or multiple hosts."
        ;;
    *)
        setup_wizard
        ;;
esac