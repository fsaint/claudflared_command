#!/bin/bash
#
# Example: Project launch script with automatic tunnel registration
#
# This shows how to integrate cf-tunnel-register into your project's
# startup script.

set -euo pipefail

# Project configuration
PROJECT_NAME="myapp"
LOCAL_PORT=3000

# Cloudflare configuration (set these in your shell profile or .env)
export CF_BASE_DOMAIN="${CF_BASE_DOMAIN:-btv.pw}"  # Your domain
export CF_TUNNEL_NAME="${CF_TUNNEL_NAME:-main-tunnel}"

# Path to the registration script
CF_REGISTER="${CF_REGISTER:-$HOME/bin/cf-tunnel-register.sh}"

# Register with cloudflared on startup
register_tunnel() {
    if [[ -x "$CF_REGISTER" ]]; then
        echo "Registering $PROJECT_NAME with cloudflared..."
        "$CF_REGISTER" "$PROJECT_NAME" "$LOCAL_PORT"
    else
        echo "Warning: cf-tunnel-register.sh not found at $CF_REGISTER"
        echo "Tunnel registration skipped"
    fi
}

# Deregister on shutdown (optional - you might want to keep routes active)
cleanup() {
    echo "Shutting down $PROJECT_NAME..."
    # Uncomment to remove tunnel route on shutdown:
    # "$HOME/bin/cf-tunnel-deregister.sh" "$PROJECT_NAME"
}

trap cleanup EXIT

# Register tunnel
register_tunnel

# Start your actual application
echo "Starting $PROJECT_NAME on port $LOCAL_PORT..."
echo "Available at: https://${PROJECT_NAME}.${CF_BASE_DOMAIN}"

# Example: Start a node app
# npm start

# Example: Start a Python app
# python manage.py runserver 0.0.0.0:$LOCAL_PORT

# Example: Just keep running for demo
echo "Press Ctrl+C to stop"
while true; do sleep 1; done
