# Cloudflared Tunnel Manager

Decentralized management for cloudflared tunnels. Each project can register itself on launch without you having to manually update the cloudflared config.

> **New to this project?** See the [Getting Started Guide](GETTING_STARTED.md) for step-by-step setup instructions.

## Quick Setup

### 1. Prerequisites

```bash
# Install cloudflared and yq
brew install cloudflared yq

# Authenticate with Cloudflare
cloudflared tunnel login

# Create a tunnel (one-time)
cloudflared tunnel create main-tunnel

# Note the tunnel ID and create DNS routes in Cloudflare dashboard
# Or use: cloudflared tunnel route dns main-tunnel "*.yourdomain.com"
```

### 2. Install the Functions

```bash
# Copy to your bin directory
cp cf-tunnel-functions.sh ~/bin/

# Add to your shell profile (~/.zshrc or ~/.bashrc)
echo 'source ~/bin/cf-tunnel-functions.sh' >> ~/.zshrc
echo 'export CF_BASE_DOMAIN="yourdomain.com"' >> ~/.zshrc
echo 'export CF_TUNNEL_NAME="main-tunnel"' >> ~/.zshrc

# Reload
source ~/.zshrc
```

### 3. Create Initial Config

Create `~/.cloudflared/config.yml`:

```yaml
tunnel: YOUR_TUNNEL_ID
credentials-file: /Users/YOU/.cloudflared/YOUR_TUNNEL_ID.json

ingress:
  # Catch-all rule (required, must be last)
  - service: http_status:404
```

## Usage

### Shell Functions (Recommended)

```bash
# Register a service
cf_register myapp 3000
# -> Creates: myapp.yourdomain.com -> http://localhost:3000

# List all routes
cf_list

# Check status
cf_status

# Remove a service
cf_deregister myapp

# Start/stop cloudflared
cf_start
cf_stop
```

### In Project Scripts

Add to your project's start script:

```bash
#!/bin/bash
# start.sh

# Register with tunnel
source ~/bin/cf-tunnel-functions.sh
cf_register myproject 8080

# Start your app
npm start
```

### With npm scripts

```json
{
  "scripts": {
    "pretunnel": "source ~/bin/cf-tunnel-functions.sh && cf_register myapp 3000",
    "start": "npm run pretunnel && node server.js"
  }
}
```

### With Make

```makefile
.PHONY: run
run:
	@bash -c 'source ~/bin/cf-tunnel-functions.sh && cf_register myapp 3000'
	python manage.py runserver 0.0.0.0:3000
```

## How It Works

1. **Config Management**: The script modifies `~/.cloudflared/config.yml`, adding/updating ingress rules
2. **Idempotent**: Running `cf_register` multiple times with the same args is safe
3. **Validation**: Config is validated before restarting cloudflared
4. **Restart**: cloudflared is restarted only when config actually changes

## Example Config After Multiple Registrations

```yaml
tunnel: abc123-def456-...
credentials-file: /Users/felipe/.cloudflared/abc123-def456-....json

ingress:
  - hostname: mcp.btv.pw
    service: http://localhost:8888
  - hostname: api.btv.pw
    service: http://localhost:3000
  - hostname: app.btv.pw
    service: http://localhost:5173
  - service: http_status:404
```

## Tips

### Run cloudflared as a Service

```bash
# Install as launchd service
sudo cloudflared service install

# Or create your own plist for user-level service
# See: ~/Library/LaunchAgents/com.cloudflare.cloudflared.plist
```

### Wildcard DNS

Set up a wildcard DNS record in Cloudflare:
- Type: CNAME
- Name: `*`
- Target: `YOUR_TUNNEL_ID.cfargotunnel.com`

This way any subdomain will route through your tunnel.

### Multiple Tunnels

You can have different tunnels for different purposes:

```bash
export CF_TUNNEL_NAME="dev-tunnel"
cf_register devapp 3000

export CF_TUNNEL_NAME="prod-tunnel"  
cf_register prodapp 8080
```

## Troubleshooting

### Check cloudflared logs
```bash
tail -f /tmp/cloudflared.log
```

### Validate config manually
```bash
cloudflared tunnel ingress validate --config ~/.cloudflared/config.yml
```

### Test a route
```bash
cloudflared tunnel ingress rule https://myapp.yourdomain.com --config ~/.cloudflared/config.yml
```
