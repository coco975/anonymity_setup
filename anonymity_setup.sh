#!/bin/bash

# Ensure the script runs as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root. Use 'sudo' to execute it."
    exit 1
fi

# Define constants
BACKUP_DIR="/root/anonymity_backup"
TORRC_FILE="/etc/tor/torrc"
RESTORE_SCRIPT="/root/restore_anonymity.sh"
LOG_FILE="/root/anonymity_setup.log"

# Create backup directory and log file
mkdir -p "$BACKUP_DIR"
touch "$LOG_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting anonymity setup" >> "$LOG_FILE"

# Function to log messages
log_message() {
    echo "$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Function to backup current configurations
backup_configs() {
    log_message "Backing up current configurations..."
    if ! iptables-save > "$BACKUP_DIR/iptables.rules"; then
        log_message "Error: Failed to backup iptables rules"
        return 1
    fi
    if [ -f "$TORRC_FILE" ]; then
        if ! cp "$TORRC_FILE" "$BACKUP_DIR/torrc.bak"; then
            log_message "Error: Failed to backup Tor configuration"
            return 1
        fi
    fi
    log_message "Backup completed successfully"
    return 0
}

# Function to install necessary tools
install_tools() {
    log_message "Installing necessary tools (Tor, macchanger)..."
    if ! apt update -y &>> "$LOG_FILE"; then
        log_message "Error: Failed to update package lists"
        return 1
    fi
    for pkg in tor macchanger; do
        if ! dpkg -l | grep -q " $pkg "; then
            if ! apt install -y "$pkg" &>> "$LOG_FILE"; then
                log_message "Error: Failed to install $pkg"
                return 1
            fi
        else
            log_message "$pkg is already installed"
        fi
    done
    log_message "Tool installation completed successfully"
    return 0
}

# Function to spoof MAC address
spoof_mac() {
    log_message "Spoofing MAC address..."
    # Identify active network interface
    INTERFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | grep -E 'eth[0-9]|wlan[0-9]' | head -1)
    if [ -z "$INTERFACE" ]; then
        log_message "Error: No suitable network interface found"
        return 1
    fi
    log_message "Using interface: $INTERFACE"
    
    # Store original MAC for reference
    ORIGINAL_MAC=$(macchanger -s "$INTERFACE" | grep "Current MAC" | awk '{print $3}')
    echo "$ORIGINAL_MAC" > "$BACKUP_DIR/original_mac_$INTERFACE"
    
    # Bring down interface
    if ! ip link set "$INTERFACE" down; then
        log_message "Error: Failed to bring down interface $INTERFACE"
        return 1
    fi
    
    # Spoof MAC address
    if ! macchanger -r "$INTERFACE" &>> "$LOG_FILE"; then
        log_message "Error: Failed to spoof MAC address for $INTERFACE"
        ip link set "$INTERFACE" up
        return 1
    fi
    
    # Bring interface back up
    if ! ip link set "$INTERFACE" up; then
        log_message "Error: Failed to bring up interface $INTERFACE"
        return 1
    fi
    
    # Reconnect if Wi-Fi
    if [[ "$INTERFACE" =~ ^wlan[0-9] ]]; then
        if command -v nmcli >/dev/null 2>&1; then
            if ! nmcli device connect "$INTERFACE" &>> "$LOG_FILE"; then
                log_message "Warning: Failed to reconnect Wi-Fi with nmcli. Please reconnect manually."
            fi
        else
            log_message "Warning: nmcli not found. Please reconnect Wi-Fi manually if needed."
        fi
    fi
    log_message "MAC address spoofed successfully for $INTERFACE"
    return 0
}

# Function to configure Tor for transparent proxy
configure_tor() {
    log_message "Configuring Tor as a transparent proxy..."
    # Define Tor configuration lines
    TOR_CONFIG=(
        "VirtualAddrNetworkIPv4 10.192.0.0/10"
        "AutomapHostsOnResolve 1"
        "TransPort 9040"
        "DNSPort 5353"
    )
    
    # Backup original torrc if not already backed up
    [ ! -f "$BACKUP_DIR/torrc.bak" ] && [ -f "$TORRC_FILE" ] && cp "$TORRC_FILE" "$BACKUP_DIR/torrc.bak"
    
    # Append configurations if not present
    for line in "${TOR_CONFIG[@]}"; do
        if ! grep -Fxq "$line" "$TORRC_FILE" 2>/dev/null; then
            echo "$line" >> "$TORRC_FILE"
        fi
    done
    
    # Restart Tor service
    if ! systemctl restart tor &>> "$LOG_FILE"; then
        log_message "Error: Failed to restart Tor service"
        return 1
    fi
    
    # Wait and verify Tor is running
    sleep 5
    if ! systemctl is-active --quiet tor; then
        log_message "Error: Tor service is not running"
        return 1
    fi
    log_message "Tor configured and running successfully"
    return 0
}

# Function to set up iptables rules
setup_iptables() {
    log_message "Setting up iptables rules for traffic redirection..."
    # Flush existing nat table rules
    if ! iptables -t nat -F; then
        log_message "Error: Failed to flush iptables nat table"
        return 1
    fi
    
    # Allow loopback traffic
    iptables -t nat -A OUTPUT -o lo -j RETURN
    
    # Allow Tor user traffic
    TOR_UID=$(id -u debian-tor 2>/dev/null || echo "debian-tor")
    if [ "$TOR_UID" != "debian-tor" ]; then
        iptables -t nat -A OUTPUT -m owner --uid-owner "$TOR_UID" -j RETURN
    else
        log_message "Warning: Could not determine Tor user UID. Skipping Tor traffic exemption."
    fi
    
    # Exclude local network traffic
    for net in "192.168.0.0/16" "10.0.0.0/8" "172.16.0.0/12"; do
        iptables -t nat -A OUTPUT -d "$net" -j RETURN
    done
    
    # Redirect TCP traffic to Tor TransPort
    if ! iptables -t nat -A OUTPUT -p tcp --syn -j REDIRECT --to-ports 9040; then
        log_message "Error: Failed to set TCP redirection rule"
        return 1
    fi
    
    # Redirect DNS traffic (UDP) to Tor DNSPort
    if ! iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports 5353; then
        log_message "Error: Failed to set UDP DNS redirection rule"
        return 1
    fi
    
    # Optionally redirect TCP DNS (less common, but for completeness)
    if ! iptables -t nat -A OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports 9040; then
        log_message "Error: Failed to set TCP DNS redirection rule"
        return 1
    fi
    log_message "iptables rules set up successfully"
    return 0
}

# Function to verify the setup
verify_setup() {
    log_message "Verifying anonymity setup..."
    if ! systemctl is-active --quiet tor; then
        log_message "Error: Tor is not running"
        return 1
    fi
    if ! iptables -t nat -n -L OUTPUT | grep -q "REDIRECT.*tcp.*9040"; then
        log_message "Error: TCP redirection rule not found in iptables"
        return 1
    fi
    if ! iptables -t nat -n -L OUTPUT | grep -q "REDIRECT.*udp.*5353"; then
        log_message "Error: DNS redirection rule not found in iptables"
        return 1
    fi
    
    # Test Tor connectivity (optional, may take time to establish)
    if command -v curl >/dev/null 2>&1; then
        if curl -s https://check.torproject.org | grep -q "Congratulations"; then
            log_message "Success: Tor is routing traffic (confirmed via check.torproject.org)"
        else
            log_message "Warning: Could not confirm Tor routing. It may take a few minutes to establish. Check manually at https://check.torproject.org"
        fi
    else
        log_message "Warning: curl not installed. Skipping Tor connectivity test."
    fi
    log_message "Setup verification passed basic checks"
    return 0
}

# Function to restore original configurations
restore_configs() {
    log_message "Restoring original configurations..."
    if [ -f "$BACKUP_DIR/iptables.rules" ]; then
        if ! iptables-restore < "$BACKUP_DIR/iptables.rules" &>> "$LOG_FILE"; then
            log_message "Error: Failed to restore iptables rules"
        fi
    fi
    if [ -f "$BACKUP_DIR/torrc.bak" ]; then
        if ! cp "$BACKUP_DIR/torrc.bak" "$TORRC_FILE" || ! systemctl restart tor &>> "$LOG_FILE"; then
            log_message "Error: Failed to restore Tor configuration or restart service"
        fi
    fi
    # Restore MAC address
    INTERFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | grep -E 'eth[0-9]|wlan[0-9]' | head -1)
    if [ -n "$INTERFACE" ]; then
        ip link set "$INTERFACE" down
        if ! macchanger -p "$INTERFACE" &>> "$LOG_FILE"; then
            log_message "Error: Failed to restore original MAC address for $INTERFACE"
        fi
        ip link set "$INTERFACE" up
    fi
    log_message "Restoration completed. Check system status."
}

# Trap errors and interruptions to restore configurations
trap 'log_message "Script interrupted or errored. Restoring configurations..."; restore_configs; exit 1' INT TERM ERR

# Main execution flow
log_message "Starting anonymity setup process..."

# Execute steps with error handling
backup_configs || { log_message "Backup failed. Aborting."; exit 1; }
install_tools || { log_message "Tool installation failed."; restore_configs; exit 1; }
spoof_mac || { log_message "MAC spoofing failed."; restore_configs; exit 1; }
configure_tor || { log_message "Tor configuration failed."; restore_configs; exit 1; }
setup_iptables || { log_message "iptables setup failed."; restore_configs; exit 1; }
verify_setup || { log_message "Verification failed."; restore_configs; exit 1; }

# Create restore script for manual use
log_message "Generating restore script at $RESTORE_SCRIPT..."
cat << EOF > "$RESTORE_SCRIPT"
#!/bin/bash
# Restore original configurations
$(declare -f restore_configs)
if [ "\$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root. Use 'sudo' to execute it."
    exit 1
fi
restore_configs
echo "Original configurations restored. Check $LOG_FILE for details."
EOF
chmod +x "$RESTORE_SCRIPT"

# Final message
log_message "Anonymity setup completed successfully!"
echo "---------------------------------------------------------------------------"
echo "Your Kali Linux system is now configured for maximum anonymity:"
echo " - IP Address: Hidden via Tor network"
echo " - DNS Queries: Routed through Tor (encrypted and anonymized)"
echo " - MAC Address: Spoofed to prevent local tracking"
echo " - Network Traffic: Encrypted through Tor (use HTTPS for end-to-end encryption)"
echo "---------------------------------------------------------------------------"
echo "Important Notes:"
echo " - To restore original configurations, run: sudo $RESTORE_SCRIPT"
echo " - Logs are available at: $LOG_FILE"
echo " - For total encryption, ensure all communications use HTTPS or other encrypted protocols."
echo " - Verify your anonymity manually at https://check.torproject.org after a few minutes."
echo "---------------------------------------------------------------------------"
