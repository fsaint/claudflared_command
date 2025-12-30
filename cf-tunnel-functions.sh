# cf-tunnel-functions.sh
#
# Source this in your .zshrc or .bashrc:
#   source ~/bin/cf-tunnel-functions.sh
#
# Then use in any project:
#   cf_register myapp 3000
#   cf_deregister myapp
#   cf_list

export CF_BASE_DOMAIN="${CF_BASE_DOMAIN:-btv.pw}"
export CF_TUNNEL_NAME="${CF_TUNNEL_NAME:-main-tunnel}"
export CLOUDFLARED_CONFIG="${CLOUDFLARED_CONFIG:-$HOME/.cloudflared/config.yml}"

# Register a service with the tunnel
cf_register() {
    local subdomain="$1"
    local port="$2"
    local hostname="${subdomain}.${CF_BASE_DOMAIN}"
    local service="http://localhost:${port}"
    
    if [[ -z "$subdomain" || -z "$port" ]]; then
        echo "Usage: cf_register <subdomain> <port>"
        echo "Example: cf_register myapp 3000"
        return 1
    fi
    
    echo "📡 Registering: $hostname -> $service"
    
    # Ensure config exists with basic structure
    if [[ ! -f "$CLOUDFLARED_CONFIG" ]]; then
        echo "❌ Config not found: $CLOUDFLARED_CONFIG"
        echo "Run 'cloudflared tunnel create $CF_TUNNEL_NAME' first"
        return 1
    fi
    
    # Check if rule already exists with same service
    local existing
    existing=$(yq ".ingress[] | select(.hostname == \"$hostname\") | .service" "$CLOUDFLARED_CONFIG" 2>/dev/null)
    
    if [[ "$existing" == "$service" ]]; then
        echo "✓ Already registered: $hostname -> $service"
        return 0
    fi
    
    # Remove existing rule if any
    yq -i "del(.ingress[] | select(.hostname == \"$hostname\"))" "$CLOUDFLARED_CONFIG" 2>/dev/null
    
    # Add new rule before catch-all
    yq -i ".ingress = [.ingress[0:-1][], {\"hostname\": \"$hostname\", \"service\": \"$service\"}, .ingress[-1]]" "$CLOUDFLARED_CONFIG"
    
    # Validate
    if ! cloudflared tunnel ingress validate --config "$CLOUDFLARED_CONFIG" &>/dev/null; then
        echo "❌ Validation failed!"
        return 1
    fi
    
    # Restart cloudflared
    _cf_restart
    
    echo "✓ Registered: https://$hostname"
}

# Remove a service from the tunnel
cf_deregister() {
    local subdomain="$1"
    local hostname="${subdomain}.${CF_BASE_DOMAIN}"
    
    if [[ -z "$subdomain" ]]; then
        echo "Usage: cf_deregister <subdomain>"
        return 1
    fi
    
    echo "🗑️  Removing: $hostname"
    
    yq -i "del(.ingress[] | select(.hostname == \"$hostname\"))" "$CLOUDFLARED_CONFIG"
    
    _cf_restart
    
    echo "✓ Removed: $hostname"
}

# List current tunnel routes
cf_list() {
    echo "📋 Current tunnel routes:"
    echo ""
    yq '.ingress[] | select(.hostname != null) | .hostname + " -> " + .service' "$CLOUDFLARED_CONFIG" 2>/dev/null
    echo ""
    echo "Catch-all: $(yq '.ingress[-1].service' "$CLOUDFLARED_CONFIG")"
}

# Show tunnel status
cf_status() {
    echo "🔍 Cloudflared Status:"
    echo ""
    
    if pgrep -f "cloudflared tunnel" > /dev/null; then
        echo "Status: Running ✓"
        echo "PID: $(pgrep -f 'cloudflared tunnel')"
    elif launchctl list 2>/dev/null | grep -q cloudflared; then
        echo "Status: Running as service ✓"
    else
        echo "Status: Not running ❌"
    fi
    
    echo ""
    cf_list
}

# Internal: restart cloudflared
_cf_restart() {
    if launchctl list 2>/dev/null | grep -q "com.cloudflare.cloudflared"; then
        launchctl stop com.cloudflare.cloudflared 2>/dev/null || true
        sleep 1
        launchctl start com.cloudflare.cloudflared
    else
        pkill -f "cloudflared tunnel run" 2>/dev/null || true
        sleep 1
        nohup cloudflared tunnel --config "$CLOUDFLARED_CONFIG" run > /tmp/cloudflared.log 2>&1 &
        disown
    fi
}

# Start cloudflared if not running
cf_start() {
    if pgrep -f "cloudflared tunnel" > /dev/null; then
        echo "cloudflared already running"
        return 0
    fi
    
    echo "Starting cloudflared..."
    nohup cloudflared tunnel --config "$CLOUDFLARED_CONFIG" run > /tmp/cloudflared.log 2>&1 &
    disown
    echo "✓ Started with PID $!"
}

# Stop cloudflared
cf_stop() {
    echo "Stopping cloudflared..."
    pkill -f "cloudflared tunnel run" 2>/dev/null || true
    echo "✓ Stopped"
}
