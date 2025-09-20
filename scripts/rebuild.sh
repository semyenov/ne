#!/usr/bin/env bash
# Multi-Host NixOS Rebuild Manager
# Manage and deploy NixOS configurations across multiple hosts

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
DEFAULT_HOST="${DEFAULT_HOST:-$(hostname)}"
REMOTE_BUILD="${REMOTE_BUILD:-false}"
PARALLEL_DEPLOY="${PARALLEL_DEPLOY:-false}"

# Available hosts (will be populated from flake)
declare -a HOSTS

# Helper functions
print_header() {
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║    Multi-Host NixOS Rebuild Manager    ║${NC}"
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

print_host() {
    echo -e "${MAGENTA}[$1]${NC} $2"
}

# Get all available hosts from flake
get_available_hosts() {
    local hosts_json=$(nix flake show "$FLAKE_PATH" --json 2>/dev/null | jq -r '.nixosConfigurations | keys[]' 2>/dev/null || echo "")
    
    if [ -z "$hosts_json" ]; then
        print_error "No hosts found in flake configuration"
        exit 1
    fi
    
    readarray -t HOSTS <<< "$hosts_json"
}

# Check if host is local or remote
is_local_host() {
    local host="$1"
    [[ "$host" == "$(hostname)" ]] || [[ "$host" == "localhost" ]]
}

# Check if host is reachable
check_host_reachable() {
    local host="$1"
    
    if is_local_host "$host"; then
        return 0
    fi
    
    # Try SSH connection
    if ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no "root@$host" "true" &>/dev/null; then
        return 0
    elif ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no "root@$host.local" "true" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Get host system info
get_host_info() {
    local host="$1"
    
    if is_local_host "$host"; then
        echo "$(nixos-version) | $(uname -r) | $(uptime -p)"
    else
        ssh -o ConnectTimeout=2 "root@$host" "echo \"\$(nixos-version) | \$(uname -r) | \$(uptime -p)\"" 2>/dev/null || echo "Unreachable"
    fi
}

# Show all hosts status
show_hosts_status() {
    print_info "Scanning configured hosts..."
    echo
    
    get_available_hosts
    
    echo -e "${CYAN}Host Status Overview:${NC}"
    echo "═══════════════════════════════════════════════════════════════════"
    printf "%-20s %-10s %-15s %-30s\n" "HOST" "STATUS" "TYPE" "INFO"
    echo "───────────────────────────────────────────────────────────────────"
    
    for host in "${HOSTS[@]}"; do
        [ -z "$host" ] && continue
        
        # Determine host type
        local type="Unknown"
        if [[ "$host" == *"workstation"* ]]; then
            type="Workstation"
        elif [[ "$host" == *"server"* ]]; then
            type="Server"
        elif [[ "$host" == *"kiosk"* ]]; then
            type="Kiosk"
        elif is_local_host "$host"; then
            type="Local"
        else
            type="Remote"
        fi
        
        # Check status
        if check_host_reachable "$host"; then
            local info=$(get_host_info "$host")
            printf "%-20s ${GREEN}%-10s${NC} %-15s %-30s\n" "$host" "Online" "$type" "${info:0:30}"
        else
            printf "%-20s ${RED}%-10s${NC} %-15s %-30s\n" "$host" "Offline" "$type" "Not reachable"
        fi
    done
    echo "═══════════════════════════════════════════════════════════════════"
    echo
}

# Select hosts for operation
select_hosts() {
    local operation="$1"
    local selected_hosts=()
    
    echo -e "${CYAN}Select hosts for $operation:${NC}"
    echo "  1) Current host only ($(hostname))"
    echo "  2) All hosts"
    echo "  3) All reachable hosts"
    echo "  4) Select specific hosts"
    echo "  5) Select by pattern"
    echo
    
    read -p "Choice [1-5]: " choice
    echo
    
    case $choice in
        1)
            selected_hosts=("$(hostname)")
            ;;
        2)
            get_available_hosts
            selected_hosts=("${HOSTS[@]}")
            ;;
        3)
            get_available_hosts
            for host in "${HOSTS[@]}"; do
                [ -z "$host" ] && continue
                if check_host_reachable "$host"; then
                    selected_hosts+=("$host")
                fi
            done
            ;;
        4)
            get_available_hosts
            echo "Available hosts:"
            for i in "${!HOSTS[@]}"; do
                [ -z "${HOSTS[$i]}" ] && continue
                echo "  $((i+1))) ${HOSTS[$i]}"
            done
            echo
            read -p "Enter host numbers (comma-separated): " selections
            IFS=',' read -ra INDICES <<< "$selections"
            for idx in "${INDICES[@]}"; do
                idx=$((idx-1))
                if [ $idx -ge 0 ] && [ $idx -lt ${#HOSTS[@]} ]; then
                    selected_hosts+=("${HOSTS[$idx]}")
                fi
            done
            ;;
        5)
            read -p "Enter pattern (e.g., 'workstation-*'): " pattern
            get_available_hosts
            for host in "${HOSTS[@]}"; do
                [ -z "$host" ] && continue
                if [[ "$host" == $pattern ]]; then
                    selected_hosts+=("$host")
                fi
            done
            ;;
        *)
            print_error "Invalid choice"
            return 1
            ;;
    esac
    
    if [ ${#selected_hosts[@]} -eq 0 ]; then
        print_error "No hosts selected"
        return 1
    fi
    
    echo "Selected hosts:"
    for host in "${selected_hosts[@]}"; do
        echo "  • $host"
    done
    echo
    
    echo "${selected_hosts[@]}"
}

# Build configuration for a host
build_for_host() {
    local host="$1"
    local action="$2"
    local extra_args="${@:3}"
    
    print_host "$host" "Starting $action..."
    
    local cmd=""
    if is_local_host "$host"; then
        # Local build
        cmd="nixos-rebuild $action --flake ${FLAKE_PATH}#${host}"
    else
        # Remote build
        if [ "$REMOTE_BUILD" == "true" ]; then
            cmd="nixos-rebuild $action --flake ${FLAKE_PATH}#${host} --target-host root@${host} --build-host root@${host}"
        else
            cmd="nixos-rebuild $action --flake ${FLAKE_PATH}#${host} --target-host root@${host}"
        fi
    fi
    
    # Add extra arguments
    if [ -n "$extra_args" ]; then
        cmd="$cmd $extra_args"
    fi
    
    # Add sudo for local operations that need it
    if is_local_host "$host" && [[ "$action" =~ ^(switch|boot|test)$ ]]; then
        cmd="sudo $cmd"
    fi
    
    # Execute build
    local log_file="/tmp/nixos-rebuild-${host}-$(date +%Y%m%d-%H%M%S).log"
    
    if $cmd &> "$log_file"; then
        print_host "$host" "${GREEN}Success${NC}"
        rm -f "$log_file"
        return 0
    else
        print_host "$host" "${RED}Failed${NC} (log: $log_file)"
        return 1
    fi
}

# Deploy to multiple hosts
deploy_multi() {
    local action="$1"
    shift
    local hosts=("$@")
    
    print_info "Deploying to ${#hosts[@]} host(s) with action: $action"
    echo
    
    # Confirm deployment
    echo "Deployment plan:"
    for host in "${hosts[@]}"; do
        echo "  • $host"
    done
    echo
    
    read -p "Continue? [y/N]: " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && return 1
    
    local failed_hosts=()
    local success_hosts=()
    
    if [ "$PARALLEL_DEPLOY" == "true" ] && [ ${#hosts[@]} -gt 1 ]; then
        print_info "Deploying in parallel..."
        echo
        
        # Start parallel builds
        for host in "${hosts[@]}"; do
            build_for_host "$host" "$action" &
        done
        
        # Wait for all builds
        wait
        
        # Check results (simplified for parallel)
        for host in "${hosts[@]}"; do
            if [ -f "/tmp/nixos-rebuild-${host}-"*.log ]; then
                failed_hosts+=("$host")
            else
                success_hosts+=("$host")
            fi
        done
    else
        # Sequential deployment
        for host in "${hosts[@]}"; do
            if build_for_host "$host" "$action"; then
                success_hosts+=("$host")
            else
                failed_hosts+=("$host")
            fi
        done
    fi
    
    # Summary
    echo
    echo "═══════════════════════════════════════════════════════════════════"
    echo "Deployment Summary"
    echo "═══════════════════════════════════════════════════════════════════"
    
    if [ ${#success_hosts[@]} -gt 0 ]; then
        echo -e "${GREEN}Successful (${#success_hosts[@]}):${NC}"
        for host in "${success_hosts[@]}"; do
            echo "  ✓ $host"
        done
    fi
    
    if [ ${#failed_hosts[@]} -gt 0 ]; then
        echo -e "${RED}Failed (${#failed_hosts[@]}):${NC}"
        for host in "${failed_hosts[@]}"; do
            echo "  ✗ $host"
        done
    fi
    echo "═══════════════════════════════════════════════════════════════════"
}

# Update flake inputs
update_flake() {
    print_info "Updating flake inputs..."
    echo
    
    # Show current inputs
    echo "Current inputs:"
    nix flake metadata "$FLAKE_PATH" --json | \
        jq -r '.locks.nodes | to_entries[] | select(.key != "root") | "  • \(.key): \(.value.locked.rev[:8] // "unknown")"'
    echo
    
    # Update options
    echo "Update options:"
    echo "  1) Update all inputs"
    echo "  2) Update specific input"
    echo "  3) Cancel"
    echo
    
    read -p "Select option [1-3]: " choice
    
    case $choice in
        1)
            if nix flake update "$FLAKE_PATH"; then
                print_success "All inputs updated!"
                
                # Show updated versions
                echo
                echo "New versions:"
                nix flake metadata "$FLAKE_PATH" --json | \
                    jq -r '.locks.nodes | to_entries[] | select(.key != "root") | "  • \(.key): \(.value.locked.rev[:8] // "unknown")"'
            else
                print_error "Update failed!"
            fi
            ;;
        2)
            echo
            echo "Available inputs:"
            nix flake metadata "$FLAKE_PATH" --json | \
                jq -r '.locks.nodes | to_entries[] | select(.key != "root") | .key' | \
                while read -r input; do echo "  • $input"; done
            echo
            
            read -p "Enter input name: " input_name
            if nix flake lock "$FLAKE_PATH" --update-input "$input_name"; then
                print_success "Input $input_name updated!"
            else
                print_error "Failed to update $input_name!"
            fi
            ;;
        *)
            print_info "Update cancelled"
            ;;
    esac
}

# Garbage collection on multiple hosts
gc_multi() {
    local hosts_str=$(select_hosts "garbage collection")
    [ -z "$hosts_str" ] && return 1
    
    IFS=' ' read -ra hosts <<< "$hosts_str"
    
    echo "Garbage collection options:"
    echo "  1) Delete older than 30 days"
    echo "  2) Delete older than 7 days"
    echo "  3) Delete all old generations"
    echo "  4) Cancel"
    echo
    
    read -p "Select option [1-4]: " choice
    
    local gc_cmd=""
    case $choice in
        1) gc_cmd="nix-collect-garbage --delete-older-than 30d" ;;
        2) gc_cmd="nix-collect-garbage --delete-older-than 7d" ;;
        3) gc_cmd="nix-collect-garbage -d" ;;
        *) return ;;
    esac
    
    for host in "${hosts[@]}"; do
        print_host "$host" "Running garbage collection..."
        
        if is_local_host "$host"; then
            sudo $gc_cmd
        else
            ssh "root@$host" "sudo $gc_cmd" 2>/dev/null || \
                print_host "$host" "${RED}Failed${NC}"
        fi
    done
    
    print_success "Garbage collection completed!"
}

# Compare configurations across hosts
compare_hosts() {
    print_info "Comparing host configurations..."
    echo
    
    get_available_hosts
    
    if [ ${#HOSTS[@]} -lt 2 ]; then
        print_error "Need at least 2 hosts to compare"
        return 1
    fi
    
    echo "Select first host:"
    for i in "${!HOSTS[@]}"; do
        echo "  $((i+1))) ${HOSTS[$i]}"
    done
    read -p "Choice: " h1_idx
    h1_idx=$((h1_idx-1))
    
    echo "Select second host:"
    for i in "${!HOSTS[@]}"; do
        echo "  $((i+1))) ${HOSTS[$i]}"
    done
    read -p "Choice: " h2_idx
    h2_idx=$((h2_idx-1))
    
    local host1="${HOSTS[$h1_idx]}"
    local host2="${HOSTS[$h2_idx]}"
    
    print_info "Comparing $host1 vs $host2..."
    echo
    
    # Build both configurations
    local out1=$(nix build --no-link --print-out-paths "${FLAKE_PATH}#nixosConfigurations.${host1}.config.system.build.toplevel" 2>/dev/null)
    local out2=$(nix build --no-link --print-out-paths "${FLAKE_PATH}#nixosConfigurations.${host2}.config.system.build.toplevel" 2>/dev/null)
    
    if [ -z "$out1" ] || [ -z "$out2" ]; then
        print_error "Failed to build configurations for comparison"
        return 1
    fi
    
    # Compare package lists
    echo "Package differences:"
    diff -u <(nix-store -q --references "$out1" | sort) \
            <(nix-store -q --references "$out2" | sort) | \
            grep "^[+-]" | head -20 || echo "  No significant differences"
    
    echo
}

# Main menu
show_menu() {
    print_header
    
    echo -e "${CYAN}Current Configuration:${NC}"
    echo "  Flake Path: $FLAKE_PATH"
    echo "  Default Host: $DEFAULT_HOST"
    echo "  Parallel Deploy: $PARALLEL_DEPLOY"
    echo "  Remote Build: $REMOTE_BUILD"
    echo
    
    echo "Operations:"
    echo "  1) Show all hosts status"
    echo "  2) Deploy to host(s)"
    echo "  3) Update flake inputs"
    echo "  4) Garbage collection"
    echo "  5) Compare hosts"
    echo "  6) Rollback host"
    echo "  7) Settings"
    echo "  8) Exit"
    echo
}

# Settings menu
settings_menu() {
    echo -e "${CYAN}Settings:${NC}"
    echo "  1) Toggle parallel deployment (current: $PARALLEL_DEPLOY)"
    echo "  2) Toggle remote build (current: $REMOTE_BUILD)"
    echo "  3) Change default host (current: $DEFAULT_HOST)"
    echo "  4) Back"
    echo
    
    read -p "Select option [1-4]: " choice
    
    case $choice in
        1)
            if [ "$PARALLEL_DEPLOY" == "true" ]; then
                PARALLEL_DEPLOY="false"
            else
                PARALLEL_DEPLOY="true"
            fi
            print_success "Parallel deployment: $PARALLEL_DEPLOY"
            ;;
        2)
            if [ "$REMOTE_BUILD" == "true" ]; then
                REMOTE_BUILD="false"
            else
                REMOTE_BUILD="true"
            fi
            print_success "Remote build: $REMOTE_BUILD"
            ;;
        3)
            get_available_hosts
            echo "Available hosts:"
            for i in "${!HOSTS[@]}"; do
                echo "  $((i+1))) ${HOSTS[$i]}"
            done
            read -p "Select new default: " idx
            idx=$((idx-1))
            if [ $idx -ge 0 ] && [ $idx -lt ${#HOSTS[@]} ]; then
                DEFAULT_HOST="${HOSTS[$idx]}"
                print_success "Default host: $DEFAULT_HOST"
            fi
            ;;
        *)
            return
            ;;
    esac
}

# Rollback a host
rollback_host() {
    local hosts_str=$(select_hosts "rollback")
    [ -z "$hosts_str" ] && return 1
    
    IFS=' ' read -ra hosts <<< "$hosts_str"
    
    print_warning "This will rollback selected hosts to their previous generation"
    read -p "Continue? [y/N]: " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && return
    
    for host in "${hosts[@]}"; do
        print_host "$host" "Rolling back..."
        
        if is_local_host "$host"; then
            if sudo nixos-rebuild --rollback switch; then
                print_host "$host" "${GREEN}Rolled back${NC}"
            else
                print_host "$host" "${RED}Failed${NC}"
            fi
        else
            if ssh "root@$host" "nixos-rebuild --rollback switch" 2>/dev/null; then
                print_host "$host" "${GREEN}Rolled back${NC}"
            else
                print_host "$host" "${RED}Failed${NC}"
            fi
        fi
    done
}

# Handle command-line arguments
if [ $# -gt 0 ]; then
    case "$1" in
        status)
            show_hosts_status
            exit 0
            ;;
        deploy)
            shift
            if [ $# -eq 0 ]; then
                hosts_str=$(select_hosts "deployment")
                [ -z "$hosts_str" ] && exit 1
                IFS=' ' read -ra hosts_array <<< "$hosts_str"
                deploy_multi "switch" "${hosts_array[@]}"
            else
                action="${1:-switch}"
                shift
                deploy_multi "$action" "$@"
            fi
            exit $?
            ;;
        update)
            update_flake
            exit 0
            ;;
        gc)
            gc_multi
            exit 0
            ;;
        compare)
            compare_hosts
            exit 0
            ;;
        --help|-h)
            echo "Usage: $0 [COMMAND] [OPTIONS]"
            echo
            echo "Commands:"
            echo "  status              Show all hosts status"
            echo "  deploy [ACTION] [HOSTS...]  Deploy to specific hosts"
            echo "  update              Update flake inputs"
            echo "  gc                  Run garbage collection"
            echo "  compare             Compare host configurations"
            echo
            echo "Actions for deploy:"
            echo "  switch    Build and activate configuration"
            echo "  test      Test configuration without making permanent"
            echo "  boot      Update boot configuration only"
            echo "  build     Build configuration without activating"
            echo
            echo "Environment variables:"
            echo "  FLAKE_PATH         Path to flake (default: .)"
            echo "  DEFAULT_HOST       Default host (default: current hostname)"
            echo "  PARALLEL_DEPLOY    Enable parallel deployment (default: false)"
            echo "  REMOTE_BUILD       Build on remote hosts (default: false)"
            echo
            echo "Examples:"
            echo "  $0 status"
            echo "  $0 deploy switch workstation-001 server-001"
            echo "  $0 deploy test"
            echo
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
            show_hosts_status
            ;;
        2)
            echo "Select action:"
            echo "  1) Switch"
            echo "  2) Test"
            echo "  3) Boot"
            echo "  4) Build"
            echo
            read -p "Action [1-4]: " action_choice
            
            case $action_choice in
                1) action="switch" ;;
                2) action="test" ;;
                3) action="boot" ;;
                4) action="build" ;;
                *) continue ;;
            esac
            
            hosts_str=$(select_hosts "deployment")
            if [ -n "$hosts_str" ]; then
                IFS=' ' read -ra hosts_array <<< "$hosts_str"
                deploy_multi "$action" "${hosts_array[@]}"
            fi
            ;;
        3)
            update_flake
            ;;
        4)
            gc_multi
            ;;
        5)
            compare_hosts
            ;;
        6)
            rollback_host
            ;;
        7)
            settings_menu
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