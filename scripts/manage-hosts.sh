#!/usr/bin/env bash
# Multi-Host Management Utility
# Manage, monitor, and configure multiple NixOS hosts

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configuration
FLAKE_PATH="${FLAKE_PATH:-.}"
HOSTS_DIR="${HOSTS_DIR:-hosts}"

# Helper functions
print_header() {
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║      Multi-Host Management Utility     ║${NC}"
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

# List all configured hosts with detailed information
list_hosts() {
    print_info "Analyzing configured hosts..."
    echo
    
    # Get hosts from flake
    local hosts=$(nix flake show "$FLAKE_PATH" --json 2>/dev/null | \
        jq -r '.nixosConfigurations | keys[]' 2>/dev/null || echo "")
    
    if [ -z "$hosts" ]; then
        print_error "No hosts found in flake configuration"
        return 1
    fi
    
    # Categorize hosts
    local workstations=()
    local servers=()
    local kiosks=()
    local others=()
    
    while IFS= read -r host; do
        [ -z "$host" ] && continue
        
        if [[ "$host" == *"workstation"* ]]; then
            workstations+=("$host")
        elif [[ "$host" == *"server"* ]]; then
            servers+=("$host")
        elif [[ "$host" == *"kiosk"* ]]; then
            kiosks+=("$host")
        else
            others+=("$host")
        fi
    done <<< "$hosts"
    
    # Display categorized hosts
    echo -e "${CYAN}Configured Hosts by Type:${NC}"
    echo "═══════════════════════════════════════"
    
    if [ ${#workstations[@]} -gt 0 ]; then
        echo -e "${MAGENTA}Workstations (${#workstations[@]}):${NC}"
        for h in "${workstations[@]}"; do
            local status="○"
            if ping -c 1 -W 1 "$h" &>/dev/null || ping -c 1 -W 1 "$h.local" &>/dev/null; then
                status="${GREEN}●${NC}"
            else
                status="${RED}○${NC}"
            fi
            echo -e "  $status $h"
        done
        echo
    fi
    
    if [ ${#servers[@]} -gt 0 ]; then
        echo -e "${MAGENTA}Servers (${#servers[@]}):${NC}"
        for h in "${servers[@]}"; do
            local status="○"
            if ping -c 1 -W 1 "$h" &>/dev/null || ping -c 1 -W 1 "$h.local" &>/dev/null; then
                status="${GREEN}●${NC}"
            else
                status="${RED}○${NC}"
            fi
            echo -e "  $status $h"
        done
        echo
    fi
    
    if [ ${#kiosks[@]} -gt 0 ]; then
        echo -e "${MAGENTA}Kiosks (${#kiosks[@]}):${NC}"
        for h in "${kiosks[@]}"; do
            local status="○"
            if ping -c 1 -W 1 "$h" &>/dev/null || ping -c 1 -W 1 "$h.local" &>/dev/null; then
                status="${GREEN}●${NC}"
            else
                status="${RED}○${NC}"
            fi
            echo -e "  $status $h"
        done
        echo
    fi
    
    if [ ${#others[@]} -gt 0 ]; then
        echo -e "${MAGENTA}Other (${#others[@]}):${NC}"
        for h in "${others[@]}"; do
            local status="○"
            if ping -c 1 -W 1 "$h" &>/dev/null || ping -c 1 -W 1 "$h.local" &>/dev/null; then
                status="${GREEN}●${NC}"
            else
                status="${RED}○${NC}"
            fi
            echo -e "  $status $h"
        done
        echo
    fi
    
    local total=$(echo "$hosts" | wc -l)
    echo "Total hosts: $total"
    echo "(${GREEN}●${NC} = online, ${RED}○${NC} = offline)"
}

# Check detailed status of a specific host
check_host_status() {
    local host="$1"
    
    echo -e "${CYAN}Host Status: $host${NC}"
    echo "═══════════════════════════════════════"
    
    # Check if host exists in flake
    if ! nix flake show "$FLAKE_PATH" --json 2>/dev/null | \
         jq -e ".nixosConfigurations.\"$host\"" &>/dev/null; then
        print_error "Host '$host' not found in configuration"
        return 1
    fi
    
    # Network connectivity
    echo -n "Network:       "
    if ping -c 1 -W 2 "$host" &>/dev/null || ping -c 1 -W 2 "$host.local" &>/dev/null; then
        echo -e "${GREEN}Online${NC}"
        local host_addr="$host"
        if ! ping -c 1 -W 1 "$host" &>/dev/null; then
            host_addr="$host.local"
        fi
        
        # SSH availability
        echo -n "SSH:           "
        if nc -z -w 2 "$host_addr" 22 &>/dev/null; then
            echo -e "${GREEN}Available${NC}"
            
            # Get system information via SSH
            if ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no "root@$host_addr" "true" &>/dev/null; then
                echo
                echo "System Information:"
                
                # NixOS version
                local nixos_ver=$(ssh -o ConnectTimeout=2 "root@$host_addr" "nixos-version" 2>/dev/null || echo "Unknown")
                echo "  NixOS:       $nixos_ver"
                
                # Kernel
                local kernel=$(ssh -o ConnectTimeout=2 "root@$host_addr" "uname -r" 2>/dev/null || echo "Unknown")
                echo "  Kernel:      $kernel"
                
                # Uptime
                local uptime=$(ssh -o ConnectTimeout=2 "root@$host_addr" "uptime -p" 2>/dev/null || echo "Unknown")
                echo "  Uptime:      $uptime"
                
                # Load average
                local load=$(ssh -o ConnectTimeout=2 "root@$host_addr" "cat /proc/loadavg | cut -d' ' -f1-3" 2>/dev/null || echo "Unknown")
                echo "  Load:        $load"
                
                # Memory usage
                local mem=$(ssh -o ConnectTimeout=2 "root@$host_addr" \
                    "free -h | grep Mem | awk '{print \$3 \" / \" \$2}'" 2>/dev/null || echo "Unknown")
                echo "  Memory:      $mem"
                
                # Disk usage
                local disk=$(ssh -o ConnectTimeout=2 "root@$host_addr" \
                    "df -h / | tail -1 | awk '{print \$3 \" / \" \$2 \" (\" \$5 \")\"}'" 2>/dev/null || echo "Unknown")
                echo "  Disk (/):    $disk"
                
                # Last rebuild
                local last_rebuild=$(ssh -o ConnectTimeout=2 "root@$host_addr" \
                    "stat -c %y /nix/var/nix/profiles/system 2>/dev/null | cut -d. -f1" 2>/dev/null || echo "Unknown")
                echo "  Last Rebuild: $last_rebuild"
            else
                echo "  (Cannot SSH as root)"
            fi
        else
            echo -e "${RED}Not available${NC}"
        fi
    else
        echo -e "${RED}Offline${NC}"
    fi
    
    # Build status
    echo
    echo -n "Build Status:  "
    if nix build --no-link --json "${FLAKE_PATH}#nixosConfigurations.$host.config.system.build.toplevel" &>/dev/null; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}Failed${NC}"
    fi
    
    # Configuration location
    echo
    echo "Configuration:"
    if [ -d "$HOSTS_DIR/$host" ]; then
        echo "  Path: $HOSTS_DIR/$host/"
        if [ -f "$HOSTS_DIR/$host/configuration.nix" ]; then
            echo "  Configuration: Present"
        else
            echo "  Configuration: ${RED}Missing${NC}"
        fi
        if [ -f "$HOSTS_DIR/$host/hardware-configuration.nix" ]; then
            echo "  Hardware Config: Present"
        else
            echo "  Hardware Config: ${RED}Missing${NC}"
        fi
    else
        echo "  Path: ${RED}Not found${NC}"
    fi
}

# Add a new host
add_host() {
    print_info "Add New Host Configuration"
    echo
    
    # Get host details
    read -p "Hostname: " hostname
    [ -z "$hostname" ] && { print_error "Hostname required"; return 1; }
    
    # Check if host already exists
    if [ -d "$HOSTS_DIR/$hostname" ]; then
        print_error "Host '$hostname' already exists"
        return 1
    fi
    
    echo
    echo "Host Type:"
    echo "  1) Workstation (Desktop with GUI)"
    echo "  2) Server (Headless system)"
    echo "  3) Kiosk (Limited desktop)"
    echo "  4) Minimal (Basic system)"
    echo "  5) Custom"
    echo
    read -p "Select type [1-5]: " host_type
    
    # Determine profiles to include
    local profiles=()
    case $host_type in
        1)  # Workstation
            profiles+=("desktop-gnome" "nvidia" "system-optimizations")
            ;;
        2)  # Server
            profiles+=("docker" "security-hardened")
            ;;
        3)  # Kiosk
            profiles+=("desktop-gnome" "security-hardened")
            ;;
        4)  # Minimal
            profiles+=("security-hardened")
            ;;
        5)  # Custom
            echo
            echo "Available profiles:"
            echo "  [ ] desktop-gnome"
            echo "  [ ] nvidia"
            echo "  [ ] docker"
            echo "  [ ] security-hardened"
            echo "  [ ] system-optimizations"
            echo
            read -p "Enter profiles (comma-separated): " custom_profiles
            IFS=',' read -ra profiles <<< "$custom_profiles"
            ;;
        *)
            print_error "Invalid choice"
            return 1
            ;;
    esac
    
    # Create host directory
    mkdir -p "$HOSTS_DIR/$hostname"
    
    # Generate configuration
    cat > "$HOSTS_DIR/$hostname/configuration.nix" << EOF
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../profiles/base.nix
EOF
    
    for profile in "${profiles[@]}"; do
        profile=$(echo "$profile" | xargs)  # Trim whitespace
        [ -z "$profile" ] && continue
        echo "    ../../profiles/$profile.nix" >> "$HOSTS_DIR/$hostname/configuration.nix"
    done
    
    cat >> "$HOSTS_DIR/$hostname/configuration.nix" << EOF
  ];

  networking.hostName = "$hostname";
  
  # System-specific configuration
  time.timeZone = "UTC";
  
  # Add users as needed
  # users.users.username = {
  #   isNormalUser = true;
  #   extraGroups = [ "wheel" ];
  # };
  
  system.stateVersion = "24.11";
}
EOF
    
    # Generate hardware configuration if on target machine
    if [ "$(hostname)" = "$hostname" ]; then
        print_info "Generating hardware configuration..."
        nixos-generate-config --show-hardware-config > "$HOSTS_DIR/$hostname/hardware-configuration.nix"
    else
        print_warning "Hardware configuration needs to be generated on the target machine"
        cat > "$HOSTS_DIR/$hostname/hardware-configuration.nix" << 'EOF'
# This file needs to be generated on the target machine
# Run: nixos-generate-config --show-hardware-config > hardware-configuration.nix
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ ];
  
  # Hardware configuration will go here
}
EOF
    fi
    
    print_success "Host configuration created at $HOSTS_DIR/$hostname/"
    
    echo
    print_info "Next steps:"
    echo "1. Add host to flake.nix:"
    echo
    echo "  nixosConfigurations.$hostname = nixpkgs.lib.nixosSystem {"
    echo "    system = \"x86_64-linux\";"
    echo "    modules = ["
    echo "      ./hosts/$hostname/configuration.nix"
    echo "      home-manager.nixosModules.home-manager"
    echo "      {"
    echo "        home-manager.useGlobalPkgs = true;"
    echo "        home-manager.useUserPackages = true;"
    echo "        home-manager.users.USERNAME = import ./home/users/USERNAME.nix;"
    echo "      }"
    echo "    ];"
    echo "  };"
    echo
    if [ "$(hostname)" != "$hostname" ]; then
        echo "2. Generate hardware configuration on target machine:"
        echo "   nixos-generate-config --show-hardware-config > hosts/$hostname/hardware-configuration.nix"
        echo
    fi
    echo "3. Test build: nix build .#nixosConfigurations.$hostname.config.system.build.toplevel"
    echo "4. Deploy: sudo nixos-rebuild switch --flake .#$hostname"
}

# Remove a host
remove_host() {
    local host="$1"
    
    if [ -z "$host" ]; then
        read -p "Enter hostname to remove: " host
    fi
    
    [ -z "$host" ] && { print_error "Hostname required"; return 1; }
    
    print_warning "This will remove the host configuration for: $host"
    echo
    echo "This will delete:"
    [ -d "$HOSTS_DIR/$host" ] && echo "  • $HOSTS_DIR/$host/"
    echo "  • Entry from flake.nix (manual)"
    echo
    
    read -p "Are you sure? [y/N]: " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Cancelled"
        return 0
    fi
    
    # Remove host directory
    if [ -d "$HOSTS_DIR/$host" ]; then
        rm -rf "$HOSTS_DIR/$host"
        print_success "Removed $HOSTS_DIR/$host/"
    else
        print_warning "Host directory not found"
    fi
    
    print_info "Remember to remove the host entry from flake.nix manually"
}

# Clone host configuration
clone_host() {
    print_info "Clone Host Configuration"
    echo
    
    # List available hosts
    echo "Available hosts to clone from:"
    local hosts=$(nix flake show "$FLAKE_PATH" --json 2>/dev/null | \
        jq -r '.nixosConfigurations | keys[]' 2>/dev/null)
    
    local i=1
    declare -a host_array
    while IFS= read -r host; do
        [ -z "$host" ] && continue
        host_array+=("$host")
        echo "  $i) $host"
        ((i++))
    done <<< "$hosts"
    
    echo
    read -p "Select source host [1-$((i-1))]: " source_idx
    
    if [ "$source_idx" -lt 1 ] || [ "$source_idx" -ge "$i" ]; then
        print_error "Invalid selection"
        return 1
    fi
    
    local source_host="${host_array[$((source_idx-1))]}"
    
    read -p "New hostname: " new_host
    [ -z "$new_host" ] && { print_error "Hostname required"; return 1; }
    
    # Check if new host already exists
    if [ -d "$HOSTS_DIR/$new_host" ]; then
        print_error "Host '$new_host' already exists"
        return 1
    fi
    
    # Check source exists
    if [ ! -d "$HOSTS_DIR/$source_host" ]; then
        print_error "Source host directory not found"
        return 1
    fi
    
    print_info "Cloning $source_host → $new_host..."
    
    # Copy configuration
    cp -r "$HOSTS_DIR/$source_host" "$HOSTS_DIR/$new_host"
    
    # Update hostname in configuration
    if [ -f "$HOSTS_DIR/$new_host/configuration.nix" ]; then
        sed -i "s/networking.hostName = \"$source_host\"/networking.hostName = \"$new_host\"/g" \
            "$HOSTS_DIR/$new_host/configuration.nix"
    fi
    
    # Clear hardware configuration (needs to be regenerated)
    cat > "$HOSTS_DIR/$new_host/hardware-configuration.nix" << 'EOF'
# This file needs to be generated on the target machine
# Run: nixos-generate-config --show-hardware-config > hardware-configuration.nix
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ ];
  
  # Hardware configuration will go here
}
EOF
    
    print_success "Host configuration cloned to $HOSTS_DIR/$new_host/"
    print_warning "Remember to:"
    echo "  1. Generate hardware configuration on the target machine"
    echo "  2. Add the host to flake.nix"
    echo "  3. Customize the configuration as needed"
}

# Compare two host configurations
compare_hosts() {
    print_info "Compare Host Configurations"
    echo
    
    # List available hosts
    local hosts=$(nix flake show "$FLAKE_PATH" --json 2>/dev/null | \
        jq -r '.nixosConfigurations | keys[]' 2>/dev/null)
    
    echo "Available hosts:"
    local i=1
    declare -a host_array
    while IFS= read -r host; do
        [ -z "$host" ] && continue
        host_array+=("$host")
        echo "  $i) $host"
        ((i++))
    done <<< "$hosts"
    
    echo
    read -p "Select first host [1-$((i-1))]: " h1_idx
    read -p "Select second host [1-$((i-1))]: " h2_idx
    
    if [ "$h1_idx" -lt 1 ] || [ "$h1_idx" -ge "$i" ] || \
       [ "$h2_idx" -lt 1 ] || [ "$h2_idx" -ge "$i" ]; then
        print_error "Invalid selection"
        return 1
    fi
    
    local host1="${host_array[$((h1_idx-1))]}"
    local host2="${host_array[$((h2_idx-1))]}"
    
    echo
    echo -e "${CYAN}Comparing: $host1 vs $host2${NC}"
    echo "═══════════════════════════════════════"
    
    # Compare configuration files
    if [ -f "$HOSTS_DIR/$host1/configuration.nix" ] && \
       [ -f "$HOSTS_DIR/$host2/configuration.nix" ]; then
        echo
        echo "Configuration differences:"
        diff -u "$HOSTS_DIR/$host1/configuration.nix" \
                "$HOSTS_DIR/$host2/configuration.nix" | \
            grep "^[+-]" | grep -v "^[+-][+-][+-]" | head -20 || \
            echo "  No differences in configuration files"
    fi
    
    # Compare package lists (requires building)
    echo
    echo -n "Building configurations for package comparison..."
    
    local out1=$(nix build --no-link --print-out-paths \
        "${FLAKE_PATH}#nixosConfigurations.${host1}.config.system.build.toplevel" 2>/dev/null)
    local out2=$(nix build --no-link --print-out-paths \
        "${FLAKE_PATH}#nixosConfigurations.${host2}.config.system.build.toplevel" 2>/dev/null)
    
    if [ -n "$out1" ] && [ -n "$out2" ]; then
        echo " Done"
        echo
        echo "Package differences:"
        comm -3 <(nix-store -q --references "$out1" | grep -v "\.drv$" | sort) \
                <(nix-store -q --references "$out2" | grep -v "\.drv$" | sort) | \
            sed 's/^\t/  + /' | sed 's/^/  - /' | head -20
    else
        echo " ${RED}Failed${NC}"
        print_error "Could not build configurations for comparison"
    fi
}

# Generate host inventory report
generate_inventory() {
    local report_file="host-inventory-$(date +%Y%m%d-%H%M%S).md"
    
    print_info "Generating host inventory report..."
    
    {
        echo "# NixOS Host Inventory Report"
        echo "Generated: $(date)"
        echo
        echo "## Summary"
        
        # Get all hosts
        local hosts=$(nix flake show "$FLAKE_PATH" --json 2>/dev/null | \
            jq -r '.nixosConfigurations | keys[]' 2>/dev/null || echo "")
        
        local total=0
        local online=0
        local offline=0
        
        while IFS= read -r host; do
            [ -z "$host" ] && continue
            ((total++))
            
            if ping -c 1 -W 1 "$host" &>/dev/null || \
               ping -c 1 -W 1 "$host.local" &>/dev/null; then
                ((online++))
            else
                ((offline++))
            fi
        done <<< "$hosts"
        
        echo "- Total Hosts: $total"
        echo "- Online: $online"
        echo "- Offline: $offline"
        echo
        echo "## Hosts"
        echo
        echo "| Hostname | Status | Type | Last Seen | Notes |"
        echo "|----------|--------|------|-----------|-------|"
        
        while IFS= read -r host; do
            [ -z "$host" ] && continue
            
            local status="Offline"
            local last_seen="N/A"
            local host_type="Unknown"
            
            # Determine type
            if [[ "$host" == *"workstation"* ]]; then
                host_type="Workstation"
            elif [[ "$host" == *"server"* ]]; then
                host_type="Server"
            elif [[ "$host" == *"kiosk"* ]]; then
                host_type="Kiosk"
            fi
            
            # Check status
            if ping -c 1 -W 1 "$host" &>/dev/null || \
               ping -c 1 -W 1 "$host.local" &>/dev/null; then
                status="**Online**"
                last_seen="Now"
            fi
            
            echo "| $host | $status | $host_type | $last_seen | |"
        done <<< "$hosts"
        
        echo
        echo "## Configuration Details"
        echo
        echo "- Flake Path: \`$FLAKE_PATH\`"
        echo "- Hosts Directory: \`$HOSTS_DIR\`"
        echo "- Last Flake Update: $(stat -c %y "$FLAKE_PATH/flake.lock" 2>/dev/null | cut -d. -f1 || echo "Unknown")"
        
    } > "$report_file"
    
    print_success "Inventory report saved to $report_file"
}

# Interactive menu
show_menu() {
    print_header
    
    echo "Host Management Operations:"
    echo "  1) List all hosts"
    echo "  2) Check host status"
    echo "  3) Add new host"
    echo "  4) Remove host"
    echo "  5) Clone host"
    echo "  6) Compare hosts"
    echo "  7) Generate inventory"
    echo "  8) Exit"
    echo
}

# Handle command-line arguments
if [ $# -gt 0 ]; then
    case "$1" in
        list)
            list_hosts
            exit 0
            ;;
        status)
            [ -z "$2" ] && { print_error "Hostname required"; exit 1; }
            check_host_status "$2"
            exit 0
            ;;
        add)
            add_host
            exit 0
            ;;
        remove)
            remove_host "$2"
            exit 0
            ;;
        clone)
            clone_host
            exit 0
            ;;
        compare)
            compare_hosts
            exit 0
            ;;
        inventory)
            generate_inventory
            exit 0
            ;;
        --help|-h)
            echo "Usage: $0 [COMMAND] [OPTIONS]"
            echo
            echo "Commands:"
            echo "  list                List all configured hosts"
            echo "  status <host>       Check status of specific host"
            echo "  add                 Add new host configuration"
            echo "  remove <host>       Remove host configuration"
            echo "  clone               Clone existing host configuration"
            echo "  compare             Compare two host configurations"
            echo "  inventory           Generate inventory report"
            echo
            echo "Or run without arguments for interactive menu"
            exit 0
            ;;
        *)
            print_error "Unknown command: $1"
            echo "Run $0 --help for usage"
            exit 1
            ;;
    esac
fi

# Interactive menu loop
while true; do
    show_menu
    read -p "Select option [1-8]: " choice
    echo
    
    case $choice in
        1)
            list_hosts
            ;;
        2)
            read -p "Enter hostname: " host
            [ -n "$host" ] && check_host_status "$host"
            ;;
        3)
            add_host
            ;;
        4)
            remove_host
            ;;
        5)
            clone_host
            ;;
        6)
            compare_hosts
            ;;
        7)
            generate_inventory
            ;;
        8)
            print_info "Goodbye!"
            exit 0
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
    
    echo
    read -p "Press Enter to continue..."
    clear
done