#!/usr/bin/env bash
# Automated Multi-Host Deployment Script
# Deploy NixOS configurations to multiple hosts with advanced orchestration

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
LOG_DIR="${LOG_DIR:-./logs}"
MAX_PARALLEL="${MAX_PARALLEL:-5}"
DEPLOYMENT_MODE="${DEPLOYMENT_MODE:-sequential}"  # sequential, parallel, rolling
SSH_USER="${SSH_USER:-root}"
BUILD_HOST="${BUILD_HOST:-localhost}"

# Deployment tracking
declare -A DEPLOYMENT_STATUS
declare -A DEPLOYMENT_LOGS
DEPLOYMENT_ID="$(date +%Y%m%d-%H%M%S)"

# Helper functions
print_header() {
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   Automated Multi-Host Deployment      ║${NC}"
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

# Create log directory
init_logs() {
    mkdir -p "$LOG_DIR/$DEPLOYMENT_ID"
    print_info "Deployment ID: $DEPLOYMENT_ID"
    print_info "Logs: $LOG_DIR/$DEPLOYMENT_ID/"
}

# Get all configured hosts from flake
get_all_hosts() {
    nix flake show "$FLAKE_PATH" --json 2>/dev/null | \
        jq -r '.nixosConfigurations | keys[]' 2>/dev/null || echo ""
}

# Check if host is reachable
check_host_health() {
    local host="$1"
    
    # Try SSH connection
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

# Pre-deployment checks
pre_deployment_checks() {
    local hosts=("$@")
    local failed_checks=()
    
    print_info "Running pre-deployment checks..."
    echo
    
    # Check flake
    if ! nix flake check "$FLAKE_PATH" &>/dev/null; then
        print_warning "Flake check reported issues"
    fi
    
    # Check hosts
    for host in "${hosts[@]}"; do
        echo -n "  Checking $host... "
        if check_host_health "$host"; then
            echo -e "${GREEN}OK${NC}"
            
            # Check disk space on target
            local disk_usage=$(ssh -o ConnectTimeout=2 "$SSH_USER@$host" \
                "df / | tail -1 | awk '{print \$5}' | sed 's/%//'" 2>/dev/null || echo "0")
            
            if [ "$disk_usage" -gt 90 ]; then
                print_warning "    Low disk space on $host ($disk_usage% used)"
            fi
        else
            echo -e "${RED}UNREACHABLE${NC}"
            failed_checks+=("$host")
        fi
    done
    
    echo
    
    if [ ${#failed_checks[@]} -gt 0 ]; then
        print_warning "Unreachable hosts: ${failed_checks[*]}"
        read -p "Continue without these hosts? [y/N]: " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
        
        # Remove unreachable hosts
        for failed in "${failed_checks[@]}"; do
            hosts=("${hosts[@]/$failed}")
        done
    fi
    
    echo "${hosts[@]}"
}

# Build configuration
build_configuration() {
    local host="$1"
    local log_file="$LOG_DIR/$DEPLOYMENT_ID/build-$host.log"
    
    print_host "$host" "Building configuration..."
    
    if nix build --no-link \
         "${FLAKE_PATH}#nixosConfigurations.${host}.config.system.build.toplevel" \
         &> "$log_file"; then
        print_host "$host" "${GREEN}Build successful${NC}"
        return 0
    else
        print_host "$host" "${RED}Build failed${NC} (see $log_file)"
        return 1
    fi
}

# Deploy to single host
deploy_to_host() {
    local host="$1"
    local action="${2:-switch}"
    local log_file="$LOG_DIR/$DEPLOYMENT_ID/deploy-$host.log"
    
    DEPLOYMENT_STATUS[$host]="deploying"
    print_host "$host" "Deploying with action: $action..."
    
    # Determine target address
    local target="$host"
    if ! ssh -o ConnectTimeout=1 "$SSH_USER@$host" "true" &>/dev/null; then
        target="$host.local"
    fi
    
    # Build and deploy
    local cmd="nixos-rebuild $action \
        --flake ${FLAKE_PATH}#${host} \
        --target-host $SSH_USER@$target"
    
    if [ "$BUILD_HOST" != "localhost" ]; then
        cmd="$cmd --build-host $BUILD_HOST"
    fi
    
    if $cmd &> "$log_file"; then
        DEPLOYMENT_STATUS[$host]="success"
        print_host "$host" "${GREEN}Deployed successfully${NC}"
        
        # Verify deployment
        verify_deployment "$host"
        return 0
    else
        DEPLOYMENT_STATUS[$host]="failed"
        print_host "$host" "${RED}Deployment failed${NC} (see $log_file)"
        return 1
    fi
}

# Verify deployment
verify_deployment() {
    local host="$1"
    
    # Get new system version
    local new_version=$(ssh -o ConnectTimeout=2 "$SSH_USER@$host" \
        "nixos-version" 2>/dev/null || echo "Unknown")
    
    print_host "$host" "Running version: $new_version"
    
    # Optional: Run health checks
    if [ -n "$HEALTH_CHECK_SCRIPT" ]; then
        if ssh "$SSH_USER@$host" "bash -s" < "$HEALTH_CHECK_SCRIPT" &>/dev/null; then
            print_host "$host" "${GREEN}Health check passed${NC}"
        else
            print_host "$host" "${YELLOW}Health check failed${NC}"
        fi
    fi
}

# Sequential deployment
deploy_sequential() {
    local hosts=("$@")
    
    for host in "${hosts[@]}"; do
        [ -z "$host" ] && continue
        
        if ! deploy_to_host "$host" "switch"; then
            print_error "Deployment to $host failed"
            
            read -p "Continue with remaining hosts? [y/N]: " -n 1 -r
            echo
            [[ ! $REPLY =~ ^[Yy]$ ]] && return 1
        fi
        echo
    done
}

# Parallel deployment
deploy_parallel() {
    local hosts=("$@")
    local pids=()
    
    print_info "Deploying to ${#hosts[@]} hosts in parallel (max $MAX_PARALLEL)..."
    echo
    
    local count=0
    for host in "${hosts[@]}"; do
        [ -z "$host" ] && continue
        
        # Wait if we've reached max parallel
        while [ $(jobs -r | wc -l) -ge "$MAX_PARALLEL" ]; do
            sleep 1
        done
        
        deploy_to_host "$host" "switch" &
        pids+=($!)
        ((count++))
    done
    
    # Wait for all deployments
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
}

# Rolling deployment (with canary)
deploy_rolling() {
    local hosts=("$@")
    local batch_size="${BATCH_SIZE:-2}"
    local canary_host="${hosts[0]}"
    
    # Deploy to canary first
    print_info "Deploying to canary host: $canary_host"
    if ! deploy_to_host "$canary_host" "switch"; then
        print_error "Canary deployment failed, aborting"
        return 1
    fi
    
    echo
    print_success "Canary deployment successful"
    read -p "Continue with rolling deployment? [y/N]: " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && return 0
    
    # Remove canary from list
    hosts=("${hosts[@]:1}")
    
    # Deploy in batches
    local batch_num=1
    while [ ${#hosts[@]} -gt 0 ]; do
        echo
        print_info "Deploying batch $batch_num (${#hosts[@]} hosts remaining)..."
        
        # Get batch
        local batch=("${hosts[@]:0:$batch_size}")
        hosts=("${hosts[@]:$batch_size}")
        
        # Deploy batch in parallel
        local pids=()
        for host in "${batch[@]}"; do
            deploy_to_host "$host" "switch" &
            pids+=($!)
        done
        
        # Wait for batch
        for pid in "${pids[@]}"; do
            wait "$pid"
        done
        
        # Check batch results
        local failed=0
        for host in "${batch[@]}"; do
            if [ "${DEPLOYMENT_STATUS[$host]}" = "failed" ]; then
                ((failed++))
            fi
        done
        
        if [ $failed -gt 0 ]; then
            print_warning "Batch $batch_num had $failed failures"
            read -p "Continue deployment? [y/N]: " -n 1 -r
            echo
            [[ ! $REPLY =~ ^[Yy]$ ]] && return 1
        fi
        
        ((batch_num++))
        
        # Wait between batches
        if [ ${#hosts[@]} -gt 0 ] && [ -n "$BATCH_DELAY" ]; then
            print_info "Waiting $BATCH_DELAY seconds before next batch..."
            sleep "$BATCH_DELAY"
        fi
    done
}

# Generate deployment report
generate_report() {
    local report_file="$LOG_DIR/$DEPLOYMENT_ID/deployment-report.md"
    
    print_info "Generating deployment report..."
    
    {
        echo "# Deployment Report"
        echo "**ID:** $DEPLOYMENT_ID"
        echo "**Date:** $(date)"
        echo "**Mode:** $DEPLOYMENT_MODE"
        echo
        
        echo "## Summary"
        local total=0
        local success=0
        local failed=0
        
        for host in "${!DEPLOYMENT_STATUS[@]}"; do
            ((total++))
            case "${DEPLOYMENT_STATUS[$host]}" in
                success) ((success++)) ;;
                failed) ((failed++)) ;;
            esac
        done
        
        echo "- Total Hosts: $total"
        echo "- Successful: $success"
        echo "- Failed: $failed"
        echo
        
        echo "## Host Details"
        echo
        echo "| Host | Status | Log File |"
        echo "|------|--------|----------|"
        
        for host in "${!DEPLOYMENT_STATUS[@]}"; do
            local status="${DEPLOYMENT_STATUS[$host]}"
            local status_display="$status"
            
            case "$status" in
                success) status_display="✅ Success" ;;
                failed) status_display="❌ Failed" ;;
                deploying) status_display="🔄 In Progress" ;;
            esac
            
            echo "| $host | $status_display | deploy-$host.log |"
        done
        
        echo
        echo "## Logs"
        echo "All logs available in: \`$LOG_DIR/$DEPLOYMENT_ID/\`"
        
    } > "$report_file"
    
    print_success "Report saved to $report_file"
}

# Rollback deployment
rollback_hosts() {
    local hosts=("$@")
    
    print_warning "Rolling back deployment on failed hosts..."
    
    for host in "${hosts[@]}"; do
        if [ "${DEPLOYMENT_STATUS[$host]}" = "failed" ]; then
            print_host "$host" "Rolling back..."
            
            if ssh "$SSH_USER@$host" "nixos-rebuild --rollback switch" &>/dev/null; then
                print_host "$host" "${GREEN}Rolled back${NC}"
            else
                print_host "$host" "${RED}Rollback failed${NC}"
            fi
        fi
    done
}

# Main deployment orchestration
main() {
    print_header
    init_logs
    
    # Parse arguments
    local action="switch"
    local host_filter=""
    local hosts_to_deploy=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mode)
                DEPLOYMENT_MODE="$2"
                shift 2
                ;;
            --action)
                action="$2"
                shift 2
                ;;
            --filter)
                host_filter="$2"
                shift 2
                ;;
            --batch-size)
                BATCH_SIZE="$2"
                shift 2
                ;;
            --batch-delay)
                BATCH_DELAY="$2"
                shift 2
                ;;
            --max-parallel)
                MAX_PARALLEL="$2"
                shift 2
                ;;
            --rollback-on-failure)
                ROLLBACK_ON_FAILURE="true"
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS] [HOSTS...]"
                echo
                echo "Options:"
                echo "  --mode MODE           Deployment mode (sequential, parallel, rolling)"
                echo "  --action ACTION       NixOS rebuild action (switch, test, boot)"
                echo "  --filter PATTERN      Filter hosts by pattern"
                echo "  --batch-size N        Batch size for rolling deployment"
                echo "  --batch-delay N       Delay between batches (seconds)"
                echo "  --max-parallel N      Max parallel deployments"
                echo "  --rollback-on-failure Auto-rollback failed hosts"
                echo
                echo "Examples:"
                echo "  $0                    Deploy to all hosts"
                echo "  $0 host1 host2        Deploy to specific hosts"
                echo "  $0 --mode parallel    Parallel deployment"
                echo "  $0 --mode rolling --batch-size 3"
                echo "  $0 --filter 'workstation-*'"
                exit 0
                ;;
            *)
                hosts_to_deploy+=("$1")
                shift
                ;;
        esac
    done
    
    # Get hosts to deploy
    if [ ${#hosts_to_deploy[@]} -eq 0 ]; then
        # Get all hosts
        mapfile -t hosts_to_deploy < <(get_all_hosts)
        
        # Apply filter if specified
        if [ -n "$host_filter" ]; then
            local filtered=()
            for host in "${hosts_to_deploy[@]}"; do
                if [[ "$host" == $host_filter ]]; then
                    filtered+=("$host")
                fi
            done
            hosts_to_deploy=("${filtered[@]}")
        fi
    fi
    
    if [ ${#hosts_to_deploy[@]} -eq 0 ]; then
        print_error "No hosts to deploy"
        exit 1
    fi
    
    # Show deployment plan
    echo -e "${CYAN}Deployment Plan:${NC}"
    echo "  Mode: $DEPLOYMENT_MODE"
    echo "  Action: $action"
    echo "  Hosts: ${#hosts_to_deploy[@]}"
    echo
    echo "Hosts to deploy:"
    for host in "${hosts_to_deploy[@]}"; do
        echo "  • $host"
    done
    echo
    
    read -p "Proceed with deployment? [y/N]: " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
    echo
    
    # Run pre-deployment checks
    mapfile -t hosts_to_deploy < <(pre_deployment_checks "${hosts_to_deploy[@]}")
    
    # Start deployment
    print_info "Starting deployment..."
    echo
    
    case "$DEPLOYMENT_MODE" in
        parallel)
            deploy_parallel "${hosts_to_deploy[@]}"
            ;;
        rolling)
            deploy_rolling "${hosts_to_deploy[@]}"
            ;;
        *)
            deploy_sequential "${hosts_to_deploy[@]}"
            ;;
    esac
    
    echo
    
    # Check for failures
    local has_failures=false
    for host in "${!DEPLOYMENT_STATUS[@]}"; do
        if [ "${DEPLOYMENT_STATUS[$host]}" = "failed" ]; then
            has_failures=true
            break
        fi
    done
    
    # Rollback if requested
    if [ "$has_failures" = true ] && [ "$ROLLBACK_ON_FAILURE" = "true" ]; then
        echo
        rollback_hosts "${hosts_to_deploy[@]}"
    fi
    
    # Generate report
    echo
    generate_report
    
    # Final summary
    echo
    echo "═══════════════════════════════════════════════"
    echo "Deployment Complete"
    echo "═══════════════════════════════════════════════"
    
    local success_count=0
    local failed_count=0
    
    for host in "${!DEPLOYMENT_STATUS[@]}"; do
        case "${DEPLOYMENT_STATUS[$host]}" in
            success) ((success_count++)) ;;
            failed) ((failed_count++)) ;;
        esac
    done
    
    if [ $success_count -gt 0 ]; then
        echo -e "${GREEN}Successful: $success_count${NC}"
    fi
    
    if [ $failed_count -gt 0 ]; then
        echo -e "${RED}Failed: $failed_count${NC}"
        exit 1
    fi
    
    print_success "All deployments completed successfully!"
}

# Run main function
main "$@"