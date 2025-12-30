#!/bin/bash
#
# Cloudflared Tunnel Manager - Interactive Setup Script
#
# This script guides you through setting up the cloudflared tunnel manager
# by checking prerequisites and walking you through each configuration step.
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#######################################
# Utility Functions
#######################################

print_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_step() {
    echo -e "${YELLOW}▶${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

prompt_continue() {
    echo ""
    read -p "Press Enter to continue (or Ctrl+C to exit)... "
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-y}"
    local yn

    if [[ "$default" == "y" ]]; then
        read -p "$prompt [Y/n]: " yn
        yn="${yn:-y}"
    else
        read -p "$prompt [y/N]: " yn
        yn="${yn:-n}"
    fi

    [[ "$yn" =~ ^[Yy] ]]
}

command_exists() {
    command -v "$1" &> /dev/null
}

#######################################
# Check Functions
#######################################

check_homebrew() {
    print_step "Checking for Homebrew..."

    if command_exists brew; then
        print_success "Homebrew is installed"
        return 0
    else
        print_error "Homebrew is not installed"
        echo ""
        print_info "Homebrew is required to install dependencies."
        echo "    Install it by running:"
        echo ""
        echo -e "    ${CYAN}/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"${NC}"
        echo ""
        return 1
    fi
}

check_cloudflared() {
    print_step "Checking for cloudflared..."

    if command_exists cloudflared; then
        local version
        version=$(cloudflared --version 2>/dev/null | head -1)
        print_success "cloudflared is installed ($version)"
        return 0
    else
        print_error "cloudflared is not installed"
        return 1
    fi
}

check_yq() {
    print_step "Checking for yq..."

    if command_exists yq; then
        local version
        version=$(yq --version 2>/dev/null | head -1)
        print_success "yq is installed ($version)"
        return 0
    else
        print_error "yq is not installed"
        return 1
    fi
}

check_cloudflared_auth() {
    print_step "Checking Cloudflare authentication..."

    if [[ -f "$HOME/.cloudflared/cert.pem" ]]; then
        print_success "Cloudflare authentication found"
        return 0
    else
        print_warning "Not authenticated with Cloudflare"
        return 1
    fi
}

check_existing_tunnels() {
    print_step "Checking for existing tunnels..."

    local tunnels
    tunnels=$(cloudflared tunnel list 2>/dev/null | grep -v "^ID" | grep -v "^$" || true)

    if [[ -n "$tunnels" ]]; then
        print_success "Found existing tunnels:"
        echo "$tunnels" | while read -r line; do
            echo "    $line"
        done
        return 0
    else
        print_info "No existing tunnels found"
        return 1
    fi
}

check_config_file() {
    local config_path="${CLOUDFLARED_CONFIG:-$HOME/.cloudflared/config.yml}"

    print_step "Checking for config file..."

    if [[ -f "$config_path" ]]; then
        print_success "Config file exists: $config_path"
        return 0
    else
        print_info "Config file not found: $config_path"
        return 1
    fi
}

#######################################
# Installation Functions
#######################################

install_cloudflared() {
    print_step "Installing cloudflared..."

    if brew install cloudflared; then
        print_success "cloudflared installed successfully"
        return 0
    else
        print_error "Failed to install cloudflared"
        return 1
    fi
}

install_yq() {
    print_step "Installing yq..."

    if brew install yq; then
        print_success "yq installed successfully"
        return 0
    else
        print_error "Failed to install yq"
        return 1
    fi
}

authenticate_cloudflare() {
    print_header "Cloudflare Authentication"

    print_info "This will open your browser to authenticate with Cloudflare."
    print_info "Select the domain you want to use for tunnels."
    echo ""

    if prompt_yes_no "Ready to authenticate?"; then
        echo ""
        print_step "Opening browser for authentication..."
        cloudflared tunnel login

        if [[ -f "$HOME/.cloudflared/cert.pem" ]]; then
            print_success "Authentication successful!"
            return 0
        else
            print_error "Authentication may have failed. cert.pem not found."
            return 1
        fi
    else
        print_warning "Skipping authentication"
        return 1
    fi
}

create_tunnel() {
    print_header "Create Tunnel"

    local tunnel_name

    echo "Enter a name for your tunnel (e.g., 'main-tunnel', 'dev-tunnel'):"
    read -p "> " tunnel_name

    if [[ -z "$tunnel_name" ]]; then
        tunnel_name="main-tunnel"
        print_info "Using default name: $tunnel_name"
    fi

    echo ""
    print_step "Creating tunnel: $tunnel_name"

    if cloudflared tunnel create "$tunnel_name"; then
        print_success "Tunnel created successfully!"

        # Get the tunnel ID
        local tunnel_id
        tunnel_id=$(cloudflared tunnel list | grep "$tunnel_name" | awk '{print $1}')

        echo ""
        print_info "Tunnel ID: $tunnel_id"
        print_info "Credentials file: $HOME/.cloudflared/$tunnel_id.json"

        # Store for later use
        CREATED_TUNNEL_NAME="$tunnel_name"
        CREATED_TUNNEL_ID="$tunnel_id"

        return 0
    else
        print_error "Failed to create tunnel"
        return 1
    fi
}

select_existing_tunnel() {
    print_header "Select Tunnel"

    echo "Available tunnels:"
    echo ""

    local tunnels
    tunnels=$(cloudflared tunnel list 2>/dev/null | grep -v "^ID" | grep -v "^$" || true)

    local i=1
    local tunnel_ids=()
    local tunnel_names=()

    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local id name
            id=$(echo "$line" | awk '{print $1}')
            name=$(echo "$line" | awk '{print $2}')
            tunnel_ids+=("$id")
            tunnel_names+=("$name")
            echo "  $i) $name ($id)"
            ((i++))
        fi
    done <<< "$tunnels"

    echo ""
    read -p "Select tunnel number (or press Enter for #1): " selection

    selection="${selection:-1}"

    if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#tunnel_names[@]} )); then
        CREATED_TUNNEL_NAME="${tunnel_names[$((selection-1))]}"
        CREATED_TUNNEL_ID="${tunnel_ids[$((selection-1))]}"
        print_success "Selected: $CREATED_TUNNEL_NAME ($CREATED_TUNNEL_ID)"
        return 0
    else
        print_error "Invalid selection"
        return 1
    fi
}

setup_dns_route() {
    print_header "DNS Routing Setup"

    local domain

    echo "Enter your domain (e.g., 'example.com'):"
    read -p "> " domain

    if [[ -z "$domain" ]]; then
        print_error "Domain cannot be empty"
        return 1
    fi

    # Store for later
    CONFIGURED_DOMAIN="$domain"

    echo ""
    print_info "This will route *.${domain} through your tunnel."
    print_warning "Make sure you've added this domain to your Cloudflare account!"
    echo ""

    if prompt_yes_no "Create wildcard DNS route?"; then
        print_step "Creating DNS route..."

        if cloudflared tunnel route dns "$CREATED_TUNNEL_NAME" "*.${domain}"; then
            print_success "DNS route created: *.${domain} -> $CREATED_TUNNEL_NAME"
            return 0
        else
            print_warning "DNS route creation returned an error."
            print_info "This might be okay if the route already exists."
            print_info "You can also set this up manually in the Cloudflare dashboard."
            return 0
        fi
    else
        print_info "Skipping DNS route setup"
        print_info "You'll need to set up DNS routing manually in Cloudflare dashboard:"
        echo "    1. Go to your domain's DNS settings"
        echo "    2. Add a CNAME record:"
        echo "       - Name: *"
        echo "       - Target: ${CREATED_TUNNEL_ID}.cfargotunnel.com"
        return 0
    fi
}

create_config_file() {
    print_header "Config File Setup"

    local config_path="$HOME/.cloudflared/config.yml"
    local credentials_file="$HOME/.cloudflared/${CREATED_TUNNEL_ID}.json"

    if [[ -f "$config_path" ]]; then
        print_warning "Config file already exists: $config_path"

        if prompt_yes_no "Overwrite existing config?" "n"; then
            print_step "Backing up existing config..."
            cp "$config_path" "${config_path}.backup.$(date +%Y%m%d_%H%M%S)"
            print_success "Backup created"
        else
            print_info "Keeping existing config"
            return 0
        fi
    fi

    print_step "Creating config file: $config_path"

    cat > "$config_path" << EOF
tunnel: ${CREATED_TUNNEL_ID}
credentials-file: ${credentials_file}

ingress:
  # Add your routes above this catch-all rule
  - service: http_status:404
EOF

    print_success "Config file created!"
    echo ""
    echo "Contents:"
    echo -e "${CYAN}"
    cat "$config_path"
    echo -e "${NC}"

    return 0
}

install_shell_functions() {
    print_header "Shell Functions Installation"

    local bin_dir="$HOME/bin"
    local functions_source="$SCRIPT_DIR/cf-tunnel-functions.sh"
    local functions_dest="$bin_dir/cf-tunnel-functions.sh"

    # Check if source exists
    if [[ ! -f "$functions_source" ]]; then
        print_error "Cannot find cf-tunnel-functions.sh in $SCRIPT_DIR"
        return 1
    fi

    # Create bin directory
    if [[ ! -d "$bin_dir" ]]; then
        print_step "Creating ~/bin directory..."
        mkdir -p "$bin_dir"
        print_success "Created $bin_dir"
    fi

    # Copy functions
    print_step "Copying shell functions..."
    cp "$functions_source" "$functions_dest"
    chmod +x "$functions_dest"
    print_success "Copied to $functions_dest"

    # Detect shell
    local shell_rc
    if [[ "$SHELL" == *"zsh"* ]]; then
        shell_rc="$HOME/.zshrc"
    else
        shell_rc="$HOME/.bashrc"
    fi

    print_step "Configuring shell profile: $shell_rc"

    # Check if already configured
    if grep -q "cf-tunnel-functions.sh" "$shell_rc" 2>/dev/null; then
        print_info "Shell functions already sourced in $shell_rc"
    else
        echo "" >> "$shell_rc"
        echo "# Cloudflared Tunnel Manager" >> "$shell_rc"
        echo "source ~/bin/cf-tunnel-functions.sh" >> "$shell_rc"
        print_success "Added source command to $shell_rc"
    fi

    # Configure environment variables
    if grep -q "CF_BASE_DOMAIN=" "$shell_rc" 2>/dev/null; then
        print_info "CF_BASE_DOMAIN already set in $shell_rc"
    else
        echo "export CF_BASE_DOMAIN=\"${CONFIGURED_DOMAIN:-yourdomain.com}\"" >> "$shell_rc"
        print_success "Added CF_BASE_DOMAIN to $shell_rc"
    fi

    if grep -q "CF_TUNNEL_NAME=" "$shell_rc" 2>/dev/null; then
        print_info "CF_TUNNEL_NAME already set in $shell_rc"
    else
        echo "export CF_TUNNEL_NAME=\"${CREATED_TUNNEL_NAME:-main-tunnel}\"" >> "$shell_rc"
        print_success "Added CF_TUNNEL_NAME to $shell_rc"
    fi

    return 0
}

#######################################
# Main Setup Flow
#######################################

main() {
    clear

    echo -e "${BOLD}${CYAN}"
    echo "   _____ _                 _  __ _                    _ "
    echo "  / ____| |               | |/ _| |                  | |"
    echo " | |    | | ___  _   _  __| | |_| | __ _ _ __ ___  __| |"
    echo " | |    | |/ _ \\| | | |/ _\` |  _| |/ _\` | '__/ _ \\/ _\` |"
    echo " | |____| | (_) | |_| | (_| | | | | (_| | | |  __/ (_| |"
    echo "  \\_____|_|\\___/ \\__,_|\\__,_|_| |_|\\__,_|_|  \\___|\\__,_|"
    echo ""
    echo "           Tunnel Manager - Interactive Setup"
    echo -e "${NC}"
    echo ""

    print_info "This script will guide you through setting up the Cloudflared Tunnel Manager."
    print_info "It will check for prerequisites and help you configure everything step by step."

    prompt_continue

    #######################################
    # Step 1: Check Prerequisites
    #######################################

    print_header "Step 1: Checking Prerequisites"

    local missing_deps=()

    if ! check_homebrew; then
        print_error "Please install Homebrew first, then run this script again."
        exit 1
    fi

    if ! check_cloudflared; then
        missing_deps+=("cloudflared")
    fi

    if ! check_yq; then
        missing_deps+=("yq")
    fi

    # Install missing dependencies
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo ""
        print_warning "Missing dependencies: ${missing_deps[*]}"

        if prompt_yes_no "Install missing dependencies with Homebrew?"; then
            for dep in "${missing_deps[@]}"; do
                case "$dep" in
                    cloudflared) install_cloudflared ;;
                    yq) install_yq ;;
                esac
            done
        else
            print_error "Cannot continue without required dependencies."
            exit 1
        fi
    fi

    prompt_continue

    #######################################
    # Step 2: Cloudflare Authentication
    #######################################

    print_header "Step 2: Cloudflare Authentication"

    if ! check_cloudflared_auth; then
        authenticate_cloudflare || {
            print_error "Authentication is required to continue."
            exit 1
        }
    fi

    prompt_continue

    #######################################
    # Step 3: Tunnel Setup
    #######################################

    print_header "Step 3: Tunnel Setup"

    if check_existing_tunnels; then
        echo ""
        if prompt_yes_no "Use an existing tunnel?"; then
            select_existing_tunnel || exit 1
        else
            create_tunnel || exit 1
        fi
    else
        create_tunnel || exit 1
    fi

    prompt_continue

    #######################################
    # Step 4: DNS Routing
    #######################################

    setup_dns_route

    prompt_continue

    #######################################
    # Step 5: Config File
    #######################################

    create_config_file

    prompt_continue

    #######################################
    # Step 6: Install Shell Functions
    #######################################

    install_shell_functions

    prompt_continue

    #######################################
    # Complete!
    #######################################

    print_header "Setup Complete!"

    echo -e "${GREEN}${BOLD}Congratulations! Setup is complete.${NC}"
    echo ""
    echo "To start using the tunnel manager:"
    echo ""
    echo -e "  ${CYAN}1. Reload your shell:${NC}"
    echo "     source ~/.zshrc  # or ~/.bashrc"
    echo ""
    echo -e "  ${CYAN}2. Start the tunnel:${NC}"
    echo "     cf_start"
    echo ""
    echo -e "  ${CYAN}3. Register a service:${NC}"
    echo "     cf_register myapp 3000"
    echo ""
    echo -e "  ${CYAN}4. Access your service at:${NC}"
    echo "     https://myapp.${CONFIGURED_DOMAIN:-yourdomain.com}"
    echo ""
    echo "Available commands:"
    echo "  cf_register <name> <port>  - Expose a local service"
    echo "  cf_deregister <name>       - Remove a service"
    echo "  cf_list                    - Show all routes"
    echo "  cf_status                  - Check tunnel status"
    echo "  cf_start                   - Start tunnel"
    echo "  cf_stop                    - Stop tunnel"
    echo ""
    print_info "See GETTING_STARTED.md for more detailed usage instructions."
    echo ""
}

# Run main
main "$@"
