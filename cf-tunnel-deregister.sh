#!/bin/bash
#
# cf-tunnel-deregister.sh - Remove a service from cloudflared tunnel
#
# Usage: cf-tunnel-deregister.sh <subdomain>
#
# Example: cf-tunnel-deregister.sh myapp

set -euo pipefail

CLOUDFLARED_CONFIG="${CLOUDFLARED_CONFIG:-$HOME/.cloudflared/config.yml}"
BASE_DOMAIN="${CF_BASE_DOMAIN:-your-domain.com}"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

main() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <subdomain>"
        exit 1
    fi
    
    local subdomain="$1"
    local hostname="${subdomain}.${BASE_DOMAIN}"
    
    if [[ ! -f "$CLOUDFLARED_CONFIG" ]]; then
        log_error "Config file not found: $CLOUDFLARED_CONFIG"
        exit 1
    fi
    
    # Check if rule exists
    local existing
    existing=$(yq ".ingress[] | select(.hostname == \"$hostname\")" "$CLOUDFLARED_CONFIG" 2>/dev/null || echo "")
    
    if [[ -z "$existing" ]]; then
        log_info "No rule found for $hostname"
        exit 0
    fi
    
    log_info "Removing rule for $hostname"
    
    # Remove the rule
    yq -i "del(.ingress[] | select(.hostname == \"$hostname\"))" "$CLOUDFLARED_CONFIG"
    
    # Restart cloudflared
    if launchctl list | grep -q "com.cloudflare.cloudflared"; then
        launchctl stop com.cloudflare.cloudflared 2>/dev/null || true
        sleep 1
        launchctl start com.cloudflare.cloudflared
    else
        pkill -f "cloudflared tunnel run" 2>/dev/null || true
        sleep 1
        nohup cloudflared tunnel --config "$CLOUDFLARED_CONFIG" run > /tmp/cloudflared.log 2>&1 &
    fi
    
    log_info "✓ Removed $hostname from tunnel"
}

main "$@"
