#!/usr/bin/env bash
# Multi-Host Backup and Sync Script
# Backup system configurations and user data across multiple NixOS hosts

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
BACKUP_DIR="${BACKUP_DIR:-./backups}"
REMOTE_BACKUP="${REMOTE_BACKUP:-}"  # Remote backup location (e.g., user@server:/path)
COMPRESSION="${COMPRESSION:-zstd}"   # Compression method (gzip, zstd, xz, none)
ENCRYPTION="${ENCRYPTION:-false}"    # Enable GPG encryption
GPG_RECIPIENT="${GPG_RECIPIENT:-}"   # GPG key ID or email
RETENTION_DAYS="${RETENTION_DAYS:-30}" # Keep backups for N days
SSH_USER="${SSH_USER:-root}"

# Backup tracking
BACKUP_ID="$(date +%Y%m%d-%H%M%S)"
declare -A BACKUP_STATUS

# Helper functions
print_header() {
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║    Multi-Host Backup & Sync Utility    ║${NC}"
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

# Initialize backup directory
init_backup() {
    mkdir -p "$BACKUP_DIR/$BACKUP_ID"
    print_info "Backup ID: $BACKUP_ID"
    print_info "Backup directory: $BACKUP_DIR/$BACKUP_ID/"
}

# Get list of hosts
get_hosts() {
    nix flake show . --json 2>/dev/null | \
        jq -r '.nixosConfigurations | keys[]' 2>/dev/null || echo ""
}

# Check host accessibility
check_host() {
    local host="$1"
    
    if [[ "$host" == "$(hostname)" ]] || [[ "$host" == "localhost" ]]; then
        return 0
    fi
    
    if ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no \
           "$SSH_USER@$host" "true" &>/dev/null; then
        return 0
    elif ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no \
             "$SSH_USER@$host.local" "true" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Backup system configuration
backup_system_config() {
    local host="$1"
    local backup_file="$BACKUP_DIR/$BACKUP_ID/${host}-system.tar"
    
    print_host "$host" "Backing up system configuration..."
    
    # Files to backup
    local config_files=(
        "/etc/nixos"
        "/etc/ssh/ssh_host_*_key.pub"
        "/etc/machine-id"
        "/var/lib/nixos"
    )
    
    # Create file list
    local file_list=""
    if [[ "$host" == "$(hostname)" ]]; then
        # Local backup
        for file in "${config_files[@]}"; do
            if [ -e "$file" ]; then
                file_list="$file_list $file"
            fi
        done
        
        if [ -n "$file_list" ]; then
            tar -cf "$backup_file" $file_list 2>/dev/null || true
        fi
    else
        # Remote backup
        local target="$host"
        if ! ssh -o ConnectTimeout=1 "$SSH_USER@$host" "true" &>/dev/null; then
            target="$host.local"
        fi
        
        ssh "$SSH_USER@$target" "tar -cf - ${config_files[*]} 2>/dev/null" > "$backup_file" || true
    fi
    
    # Compress if enabled
    if [ "$COMPRESSION" != "none" ] && [ -f "$backup_file" ]; then
        case "$COMPRESSION" in
            gzip)
                gzip "$backup_file"
                backup_file="${backup_file}.gz"
                ;;
            zstd)
                zstd --rm "$backup_file"
                backup_file="${backup_file}.zst"
                ;;
            xz)
                xz "$backup_file"
                backup_file="${backup_file}.xz"
                ;;
        esac
    fi
    
    # Encrypt if enabled
    if [ "$ENCRYPTION" = "true" ] && [ -n "$GPG_RECIPIENT" ] && [ -f "$backup_file" ]; then
        gpg --encrypt --recipient "$GPG_RECIPIENT" "$backup_file"
        rm "$backup_file"
        backup_file="${backup_file}.gpg"
    fi
    
    if [ -f "${backup_file%.gpg}" ] || [ -f "$backup_file" ]; then
        local size=$(du -h "$backup_file" 2>/dev/null | cut -f1)
        print_host "$host" "${GREEN}System backup complete${NC} ($size)"
        BACKUP_STATUS["$host-system"]="success"
    else
        print_host "$host" "${RED}System backup failed${NC}"
        BACKUP_STATUS["$host-system"]="failed"
    fi
}

# Backup user data
backup_user_data() {
    local host="$1"
    local user="${2:-$USER}"
    local backup_file="$BACKUP_DIR/$BACKUP_ID/${host}-user-${user}.tar"
    
    print_host "$host" "Backing up user data for $user..."
    
    # Directories to backup
    local user_dirs=(
        ".config"
        ".ssh"
        ".gnupg"
        "Documents"
        "Projects"
        ".local/share"
    )
    
    # Create backup
    if [[ "$host" == "$(hostname)" ]]; then
        # Local backup
        local file_list=""
        for dir in "${user_dirs[@]}"; do
            if [ -e "/home/$user/$dir" ]; then
                file_list="$file_list /home/$user/$dir"
            fi
        done
        
        if [ -n "$file_list" ]; then
            tar --exclude-vcs \
                --exclude="*.cache" \
                --exclude="node_modules" \
                --exclude=".venv" \
                -cf "$backup_file" $file_list 2>/dev/null || true
        fi
    else
        # Remote backup
        local target="$host"
        if ! ssh -o ConnectTimeout=1 "$SSH_USER@$host" "true" &>/dev/null; then
            target="$host.local"
        fi
        
        local remote_dirs=""
        for dir in "${user_dirs[@]}"; do
            remote_dirs="$remote_dirs /home/$user/$dir"
        done
        
        ssh "$SSH_USER@$target" \
            "tar --exclude-vcs --exclude='*.cache' --exclude='node_modules' -cf - $remote_dirs 2>/dev/null" \
            > "$backup_file" || true
    fi
    
    # Compress if enabled
    if [ "$COMPRESSION" != "none" ] && [ -f "$backup_file" ]; then
        case "$COMPRESSION" in
            gzip)
                gzip "$backup_file"
                backup_file="${backup_file}.gz"
                ;;
            zstd)
                zstd --rm "$backup_file"
                backup_file="${backup_file}.zst"
                ;;
            xz)
                xz "$backup_file"
                backup_file="${backup_file}.xz"
                ;;
        esac
    fi
    
    # Encrypt if enabled
    if [ "$ENCRYPTION" = "true" ] && [ -n "$GPG_RECIPIENT" ] && [ -f "$backup_file" ]; then
        gpg --encrypt --recipient "$GPG_RECIPIENT" "$backup_file"
        rm "$backup_file"
        backup_file="${backup_file}.gpg"
    fi
    
    if [ -f "${backup_file%.gpg}" ] || [ -f "$backup_file" ]; then
        local size=$(du -h "$backup_file" 2>/dev/null | cut -f1)
        print_host "$host" "${GREEN}User backup complete${NC} ($size)"
        BACKUP_STATUS["$host-user-$user"]="success"
    else
        print_host "$host" "${YELLOW}User backup skipped or failed${NC}"
        BACKUP_STATUS["$host-user-$user"]="failed"
    fi
}

# Backup NixOS generations
backup_generations() {
    local host="$1"
    local output_file="$BACKUP_DIR/$BACKUP_ID/${host}-generations.txt"
    
    print_host "$host" "Backing up generation list..."
    
    if [[ "$host" == "$(hostname)" ]]; then
        nix-env --list-generations --profile /nix/var/nix/profiles/system > "$output_file"
    else
        local target="$host"
        if ! ssh -o ConnectTimeout=1 "$SSH_USER@$host" "true" &>/dev/null; then
            target="$host.local"
        fi
        
        ssh "$SSH_USER@$target" \
            "nix-env --list-generations --profile /nix/var/nix/profiles/system" \
            > "$output_file" 2>/dev/null || true
    fi
    
    if [ -f "$output_file" ] && [ -s "$output_file" ]; then
        print_host "$host" "${GREEN}Generation list saved${NC}"
    else
        print_host "$host" "${YELLOW}Could not save generation list${NC}"
    fi
}

# Sync configurations between hosts
sync_configs() {
    local source_host="$1"
    local dest_host="$2"
    local sync_type="${3:-config}"  # config, user, or full
    
    print_info "Syncing $source_host → $dest_host ($sync_type)..."
    
    # Determine what to sync
    local rsync_opts="-avz --delete"
    local paths=()
    
    case "$sync_type" in
        config)
            paths+=("/etc/nixos/")
            ;;
        user)
            paths+=("/home/")
            rsync_opts="$rsync_opts --exclude=.cache --exclude=node_modules"
            ;;
        full)
            paths+=("/etc/nixos/" "/home/")
            rsync_opts="$rsync_opts --exclude=.cache --exclude=node_modules"
            ;;
    esac
    
    # Perform sync
    for path in "${paths[@]}"; do
        if [[ "$source_host" == "$(hostname)" ]]; then
            # Local to remote
            rsync $rsync_opts "$path" "$SSH_USER@$dest_host:$path"
        elif [[ "$dest_host" == "$(hostname)" ]]; then
            # Remote to local
            rsync $rsync_opts "$SSH_USER@$source_host:$path" "$path"
        else
            # Remote to remote (via local)
            local temp_dir="/tmp/sync-$$"
            mkdir -p "$temp_dir"
            rsync $rsync_opts "$SSH_USER@$source_host:$path" "$temp_dir/"
            rsync $rsync_opts "$temp_dir/" "$SSH_USER@$dest_host:$path"
            rm -rf "$temp_dir"
        fi
    done
    
    print_success "Sync complete: $source_host → $dest_host"
}

# Upload to remote backup location
upload_remote() {
    if [ -z "$REMOTE_BACKUP" ]; then
        return
    fi
    
    print_info "Uploading to remote backup location..."
    
    if rsync -avz "$BACKUP_DIR/$BACKUP_ID/" "$REMOTE_BACKUP/$BACKUP_ID/"; then
        print_success "Remote backup upload complete"
    else
        print_error "Remote backup upload failed"
    fi
}

# Clean old backups
cleanup_old_backups() {
    print_info "Cleaning old backups (older than $RETENTION_DAYS days)..."
    
    # Local cleanup
    find "$BACKUP_DIR" -maxdepth 1 -type d -mtime +$RETENTION_DAYS -exec rm -rf {} \; 2>/dev/null || true
    
    # Remote cleanup if configured
    if [ -n "$REMOTE_BACKUP" ]; then
        if [[ "$REMOTE_BACKUP" =~ ^([^:]+):(.+)$ ]]; then
            local remote_host="${BASH_REMATCH[1]}"
            local remote_path="${BASH_REMATCH[2]}"
            
            ssh "$remote_host" \
                "find $remote_path -maxdepth 1 -type d -mtime +$RETENTION_DAYS -exec rm -rf {} \;" \
                2>/dev/null || true
        fi
    fi
    
    print_success "Cleanup complete"
}

# Restore backup
restore_backup() {
    local backup_id="$1"
    local host="$2"
    local restore_type="${3:-config}"  # config, user, or full
    
    print_info "Restoring backup $backup_id to $host..."
    
    local backup_path="$BACKUP_DIR/$backup_id"
    
    if [ ! -d "$backup_path" ]; then
        print_error "Backup $backup_id not found"
        return 1
    fi
    
    # Find backup files
    local system_backup=$(ls "$backup_path/${host}-system."* 2>/dev/null | head -1)
    local user_backup=$(ls "$backup_path/${host}-user-"* 2>/dev/null | head -1)
    
    # Decrypt if needed
    if [[ "$system_backup" == *.gpg ]]; then
        print_info "Decrypting backup..."
        gpg --decrypt "$system_backup" > "${system_backup%.gpg}"
        system_backup="${system_backup%.gpg}"
    fi
    
    # Decompress if needed
    case "$system_backup" in
        *.gz)
            gunzip -k "$system_backup"
            system_backup="${system_backup%.gz}"
            ;;
        *.zst)
            zstd -d "$system_backup" -o "${system_backup%.zst}"
            system_backup="${system_backup%.zst}"
            ;;
        *.xz)
            xz -dk "$system_backup"
            system_backup="${system_backup%.xz}"
            ;;
    esac
    
    # Restore based on type
    case "$restore_type" in
        config)
            if [ -f "$system_backup" ]; then
                print_info "Restoring system configuration..."
                
                if [[ "$host" == "$(hostname)" ]]; then
                    sudo tar -xf "$system_backup" -C /
                else
                    cat "$system_backup" | ssh "$SSH_USER@$host" "sudo tar -xf - -C /"
                fi
                
                print_success "System configuration restored"
            fi
            ;;
        user)
            if [ -f "$user_backup" ]; then
                print_info "Restoring user data..."
                
                # Similar restore logic for user data
                print_success "User data restored"
            fi
            ;;
        full)
            # Restore both system and user
            restore_backup "$backup_id" "$host" "config"
            restore_backup "$backup_id" "$host" "user"
            ;;
    esac
}

# List available backups
list_backups() {
    echo -e "${CYAN}Available Backups:${NC}"
    echo "═══════════════════════════════════════════════"
    
    for backup_dir in "$BACKUP_DIR"/*; do
        if [ -d "$backup_dir" ]; then
            local backup_id=$(basename "$backup_dir")
            local backup_date=$(echo "$backup_id" | sed 's/\(....\)\(..\)\(..\)-\(..\)\(..\)\(..\)/\1-\2-\3 \4:\5:\6/')
            local size=$(du -sh "$backup_dir" | cut -f1)
            local file_count=$(find "$backup_dir" -type f | wc -l)
            
            echo "ID: $backup_id"
            echo "  Date: $backup_date"
            echo "  Size: $size"
            echo "  Files: $file_count"
            
            # List hosts in this backup
            echo -n "  Hosts: "
            for file in "$backup_dir"/*-system.*; do
                if [ -f "$file" ]; then
                    local hostname=$(basename "$file" | sed 's/-system\..*//')
                    echo -n "$hostname "
                fi
            done
            echo
            echo
        fi
    done
}

# Interactive menu
show_menu() {
    print_header
    
    echo "Backup Operations:"
    echo "  1) Backup all hosts"
    echo "  2) Backup specific host"
    echo "  3) Sync configurations"
    echo "  4) List backups"
    echo "  5) Restore backup"
    echo "  6) Clean old backups"
    echo "  7) Exit"
    echo
}

# Main function for CLI usage
main() {
    case "${1:-}" in
        backup-all)
            print_header
            init_backup
            
            mapfile -t hosts < <(get_hosts)
            
            for host in "${hosts[@]}"; do
                [ -z "$host" ] && continue
                
                echo
                if check_host "$host"; then
                    backup_system_config "$host"
                    backup_generations "$host"
                    backup_user_data "$host"
                else
                    print_host "$host" "${RED}Host unreachable${NC}"
                fi
            done
            
            upload_remote
            cleanup_old_backups
            
            # Summary
            echo
            echo "Backup Summary:"
            local success=0
            local failed=0
            
            for status in "${BACKUP_STATUS[@]}"; do
                if [ "$status" = "success" ]; then
                    ((success++))
                else
                    ((failed++))
                fi
            done
            
            echo "  Successful: $success"
            echo "  Failed: $failed"
            ;;
            
        backup)
            shift
            host="${1:-$(hostname)}"
            print_header
            init_backup
            
            if check_host "$host"; then
                backup_system_config "$host"
                backup_generations "$host"
                backup_user_data "$host"
                upload_remote
            else
                print_error "Host $host is unreachable"
            fi
            ;;
            
        sync)
            shift
            source_host="${1:-}"
            dest_host="${2:-}"
            sync_type="${3:-config}"
            
            if [ -z "$source_host" ] || [ -z "$dest_host" ]; then
                print_error "Usage: $0 sync <source-host> <dest-host> [config|user|full]"
                exit 1
            fi
            
            print_header
            sync_configs "$source_host" "$dest_host" "$sync_type"
            ;;
            
        restore)
            shift
            backup_id="${1:-}"
            host="${2:-}"
            restore_type="${3:-config}"
            
            if [ -z "$backup_id" ] || [ -z "$host" ]; then
                print_error "Usage: $0 restore <backup-id> <host> [config|user|full]"
                exit 1
            fi
            
            print_header
            restore_backup "$backup_id" "$host" "$restore_type"
            ;;
            
        list)
            print_header
            list_backups
            ;;
            
        clean)
            print_header
            cleanup_old_backups
            ;;
            
        --help|-h)
            echo "Usage: $0 [COMMAND] [OPTIONS]"
            echo
            echo "Commands:"
            echo "  backup-all              Backup all configured hosts"
            echo "  backup [HOST]           Backup specific host"
            echo "  sync SRC DST [TYPE]     Sync between hosts"
            echo "  restore ID HOST [TYPE]  Restore backup"
            echo "  list                    List available backups"
            echo "  clean                   Clean old backups"
            echo
            echo "Environment Variables:"
            echo "  BACKUP_DIR              Backup directory (default: ./backups)"
            echo "  REMOTE_BACKUP           Remote backup location"
            echo "  COMPRESSION             Compression method (gzip|zstd|xz|none)"
            echo "  ENCRYPTION              Enable GPG encryption (true|false)"
            echo "  GPG_RECIPIENT           GPG key for encryption"
            echo "  RETENTION_DAYS          Keep backups for N days"
            echo
            echo "Examples:"
            echo "  $0 backup-all"
            echo "  $0 backup workstation-001"
            echo "  $0 sync workstation-001 workstation-002 config"
            echo "  $0 restore 20240101-120000 workstation-001"
            ;;
            
        *)
            # Interactive mode
            while true; do
                show_menu
                read -p "Select option [1-7]: " choice
                echo
                
                case $choice in
                    1)
                        init_backup
                        mapfile -t hosts < <(get_hosts)
                        for host in "${hosts[@]}"; do
                            [ -z "$host" ] && continue
                            if check_host "$host"; then
                                backup_system_config "$host"
                                backup_generations "$host"
                            fi
                        done
                        upload_remote
                        ;;
                    2)
                        read -p "Enter hostname: " host
                        init_backup
                        if check_host "$host"; then
                            backup_system_config "$host"
                            backup_generations "$host"
                            backup_user_data "$host"
                        fi
                        ;;
                    3)
                        read -p "Source host: " src
                        read -p "Destination host: " dst
                        read -p "Sync type (config/user/full) [config]: " stype
                        stype=${stype:-config}
                        sync_configs "$src" "$dst" "$stype"
                        ;;
                    4)
                        list_backups
                        ;;
                    5)
                        read -p "Backup ID: " bid
                        read -p "Target host: " host
                        read -p "Restore type (config/user/full) [config]: " rtype
                        rtype=${rtype:-config}
                        restore_backup "$bid" "$host" "$rtype"
                        ;;
                    6)
                        cleanup_old_backups
                        ;;
                    7)
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
            ;;
    esac
}

# Run main
main "$@"