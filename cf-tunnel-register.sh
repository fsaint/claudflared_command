#!/bin/bash
#
# cf-tunnel-register.sh - Register a service with cloudflared tunnel
#
# Usage: cf-tunnel-register.sh <subdomain> <local_port> [tunnel_name]
#
# Example: cf-tunnel-register.sh myapp 3000 my-tunnel
#
# This script:
#   1. Adds/updates an ingress rule in cloudflared config
#   2. Restarts cloudflared if config changed
#
# Prerequisites:
#   - cloudflared installed and authenticated
#   - A tunnel already created (cloudflared tunnel create <name>)
#   - yq installed (brew install yq)

set -euo pipefail

# Configuration - customize these
CLOUDFLARED_CONFIG="${CLOUDFLARED_CONFIG:-$HOME/.cloudflared/config.yml}"
BASE_DOMAIN="${CF_BASE_DOMAIN:-your-domain.com}"  # Set this env var
DEFAULT_TUNNEL="${CF_TUNNEL_NAME:-main-tunnel}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check dependencies
check_deps() {
    if ! command -v yq &> /dev/null; then
        log_error "yq is required but not installed. Run: brew install yq"
        exit 1
    fi
    if ! command -v cloudflared &> /dev/null; then
        log_error "cloudflared is required but not installed. Run: brew install cloudflared"
        exit 1
    fi
}

# Initialize config if it doesn't exist
init_config() {
    local tunnel_name="$1"
    
    if [[ ! -f "$CLOUDFLARED_CONFIG" ]]; then
        log_info "Creating initial cloudflared config at $CLOUDFLARED_CONFIG"
        mkdir -p "$(dirname "$CLOUDFLARED_CONFIG")"
        
        # Get tunnel UUID
        local tunnel_id
        tunnel_id=$(cloudflared tunnel list | grep "$tunnel_name" | awk '{print $1}')
        
        if [[ -z "$tunnel_id" ]]; then
            log_error "Tunnel '$tunnel_name' not found. Create it with: cloudflared tunnel create $tunnel_name"
            exit 1
        fi
        
        cat > "$CLOUDFLARED_CONFIG" << EOF
tunnel: $tunnel_id
credentials-file: $HOME/.cloudflared/$tunnel_id.json

ingress:
  # Catch-all rule (required, must be last)
  - service: http_status:404
EOF
        log_info "Created initial config with tunnel ID: $tunnel_id"
    fi
}

# Add or update an ingress rule
update_ingress() {
    local hostname="$1"
    local service="$2"
    local config_file="$3"
    
    # Create backup
    cp "$config_file" "${config_file}.bak"
    
    # Check if hostname already exists
    local existing_service
    existing_service=$(yq ".ingress[] | select(.hostname == \"$hostname\") | .service" "$config_file" 2>/dev/null || echo "")
    
    if [[ -n "$existing_service" && "$existing_service" != "null" ]]; then
        if [[ "$existing_service" == "$service" ]]; then
            log_info "Rule for $hostname already exists with correct service"
            rm "${config_file}.bak"
            return 1  # No change needed
        else
            log_info "Updating existing rule for $hostname: $existing_service -> $service"
            # Update existing entry
            yq -i "(.ingress[] | select(.hostname == \"$hostname\")).service = \"$service\"" "$config_file"
        fi
    else
        log_info "Adding new rule: $hostname -> $service"
        # Insert before the catch-all rule (which must be last)
        # yq magic: insert at second-to-last position
        yq -i ".ingress = [.ingress[0:-1][], {\"hostname\": \"$hostname\", \"service\": \"$service\"}, .ingress[-1]]" "$config_file"
    fi
    
    rm "${config_file}.bak"
    return 0  # Config changed
}

# Validate the config
validate_config() {
    local config_file="$1"
    
    if ! cloudflared tunnel ingress validate --config "$config_file" 2>/dev/null; then
        log_error "Config validation failed!"
        return 1
    fi
    log_info "Config validation passed"
    return 0
}

# Restart cloudflared
restart_cloudflared() {
    log_info "Restarting cloudflared..."
    
    # Check if running as a service
    if launchctl list | grep -q "com.cloudflare.cloudflared"; then
        log_info "Restarting via launchctl..."
        launchctl stop com.cloudflare.cloudflared 2>/dev/null || true
        sleep 1
        launchctl start com.cloudflare.cloudflared
    else
        # Kill existing process and restart
        pkill -f "cloudflared tunnel" 2>/dev/null || true
        sleep 1
        
        # Start in background
        log_info "Starting cloudflared tunnel in background..."
        nohup cloudflared tunnel --config "$CLOUDFLARED_CONFIG" run > /tmp/cloudflared.log 2>&1 &
        log_info "cloudflared started with PID $!"
    fi
}

# Main function
main() {
    if [[ $# -lt 2 ]]; then
        echo "Usage: $0 <subdomain> <local_port> [tunnel_name]"
        echo ""
        echo "Environment variables:"
        echo "  CF_BASE_DOMAIN   - Your base domain (default: your-domain.com)"
        echo "  CF_TUNNEL_NAME   - Tunnel name (default: main-tunnel)"
        echo "  CLOUDFLARED_CONFIG - Config path (default: ~/.cloudflared/config.yml)"
        echo ""
        echo "Example:"
        echo "  CF_BASE_DOMAIN=example.com $0 myapp 3000"
        echo "  -> Creates rule: myapp.example.com -> http://localhost:3000"
        exit 1
    fi
    
    local subdomain="$1"
    local port="$2"
    local tunnel_name="${3:-$DEFAULT_TUNNEL}"
    
    local hostname="${subdomain}.${BASE_DOMAIN}"
    local service="http://localhost:${port}"
    
    log_info "Registering: $hostname -> $service"
    
    check_deps
    init_config "$tunnel_name"
    
    if update_ingress "$hostname" "$service" "$CLOUDFLARED_CONFIG"; then
        if validate_config "$CLOUDFLARED_CONFIG"; then
            restart_cloudflared
            log_info "✓ Successfully registered $hostname -> $service"
        else
            log_error "Config validation failed, reverting..."
            # Could restore from backup here
            exit 1
        fi
    else
        log_info "✓ No changes needed for $hostname"
    fi
}

main "$@"
