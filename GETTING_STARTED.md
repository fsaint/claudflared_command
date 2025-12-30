# Getting Started with Cloudflared Tunnel Manager

This guide walks you through setting up and using the Cloudflared Tunnel Manager to expose your local development services to the internet.

## Prerequisites

- macOS with Homebrew installed
- A Cloudflare account with a domain configured
- Basic terminal knowledge

## Initial Configuration

### Step 1: Install Required Tools

```bash
brew install cloudflared yq
```

- **cloudflared**: Cloudflare's tunnel client
- **yq**: YAML processor used to manage config files

### Step 2: Authenticate with Cloudflare

```bash
cloudflared tunnel login
```

This opens your browser to authenticate. Select the domain you want to use for tunnels.

### Step 3: Create Your Tunnel

```bash
cloudflared tunnel create main-tunnel
```

This outputs a **Tunnel ID** (e.g., `a1b2c3d4-e5f6-7890-abcd-ef1234567890`). Save this ID - you'll need it next.

### Step 4: Set Up DNS Routing

Route a wildcard subdomain through your tunnel:

```bash
cloudflared tunnel route dns main-tunnel "*.yourdomain.com"
```

Replace `yourdomain.com` with your actual domain.

### Step 5: Create the Tunnel Config File

Create `~/.cloudflared/config.yml`:

```yaml
tunnel: YOUR_TUNNEL_ID
credentials-file: /Users/YOUR_USERNAME/.cloudflared/YOUR_TUNNEL_ID.json

ingress:
  - service: http_status:404
```

Replace:
- `YOUR_TUNNEL_ID` with the ID from Step 3
- `YOUR_USERNAME` with your macOS username

### Step 6: Install the Shell Functions

```bash
# Create bin directory if it doesn't exist
mkdir -p ~/bin

# Copy the functions script
cp cf-tunnel-functions.sh ~/bin/

# Add to your shell profile
cat >> ~/.zshrc << 'EOF'

# Cloudflared Tunnel Manager
source ~/bin/cf-tunnel-functions.sh
export CF_BASE_DOMAIN="yourdomain.com"
export CF_TUNNEL_NAME="main-tunnel"
EOF

# Reload your shell
source ~/.zshrc
```

Replace `yourdomain.com` with your actual domain.

## Main Usage

### Register a Service

Expose a local service to the internet:

```bash
cf_register myapp 3000
```

This creates `https://myapp.yourdomain.com` pointing to `http://localhost:3000`.

### List Active Routes

View all registered services:

```bash
cf_list
```

Example output:
```
myapp.yourdomain.com -> http://localhost:3000
api.yourdomain.com -> http://localhost:8080
```

### Check Tunnel Status

```bash
cf_status
```

Shows whether cloudflared is running and lists all routes.

### Remove a Service

Stop exposing a service:

```bash
cf_deregister myapp
```

### Start/Stop the Tunnel

```bash
cf_start    # Start cloudflared daemon
cf_stop     # Stop cloudflared daemon
```

## Quick Reference

| Command | Description | Example |
|---------|-------------|---------|
| `cf_register <name> <port>` | Expose localhost:port as name.domain.com | `cf_register api 8080` |
| `cf_deregister <name>` | Remove a service | `cf_deregister api` |
| `cf_list` | Show all routes | `cf_list` |
| `cf_status` | Check tunnel status | `cf_status` |
| `cf_start` | Start tunnel daemon | `cf_start` |
| `cf_stop` | Stop tunnel daemon | `cf_stop` |

## Integration Examples

### In a Project Start Script

```bash
#!/bin/bash
source ~/bin/cf-tunnel-functions.sh
cf_register myproject 3000
npm start
```

### In package.json

```json
{
  "scripts": {
    "dev": "bash -c 'source ~/bin/cf-tunnel-functions.sh && cf_register myapp 3000' && vite"
  }
}
```

### In a Makefile

```makefile
run:
	@bash -c 'source ~/bin/cf-tunnel-functions.sh && cf_register myapp 8000'
	python manage.py runserver 0.0.0.0:8000
```

## Troubleshooting

### View Logs

```bash
tail -f /tmp/cloudflared.log
```

### Validate Configuration

```bash
cloudflared tunnel ingress validate --config ~/.cloudflared/config.yml
```

### Test a Specific Route

```bash
cloudflared tunnel ingress rule https://myapp.yourdomain.com --config ~/.cloudflared/config.yml
```

### Common Issues

**"Config not found" error**
- Ensure `~/.cloudflared/config.yml` exists
- Check that `CLOUDFLARED_CONFIG` env var points to the correct path

**Service not accessible**
- Verify cloudflared is running: `cf_status`
- Check that your local service is running on the specified port
- Confirm DNS is properly configured in Cloudflare dashboard

**Validation failed**
- Run manual validation to see the error details
- Ensure the config.yml has the catch-all rule (`- service: http_status:404`) as the last entry
