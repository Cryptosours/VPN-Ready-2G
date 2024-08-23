#!/bin/bash

# Comprehensive Outline and V2Ray VPN Setup Script with Optimizations
# This script sets up both Outline and V2Ray VPNs on a Linux VPS
# It includes error handling, optimization, and proper package management

set -e

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to handle errors
handle_error() {
    log "Error occurred in line $1"
    exit 1
}

# Set up error handling
trap 'handle_error $LINENO' ERR

# Update system and install dependencies
log "Updating system and installing dependencies..."
apt-get update && apt-get upgrade -y
apt-get install -y curl wget jq ufw net-tools htop tcpdump iftop iotop fail2ban unattended-upgrades

# Create outline user and add to necessary groups
log "Creating outline user..."
useradd -m -s /bin/bash outline
usermod -aG sudo outline
echo "outline ALL=(ALL) NOPASSWD:ALL" | tee -a /etc/sudoers

# Install Docker
log "Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker outline
usermod -aG docker root

# Install Outline
log "Installing Outline..."
bash -c "$(wget -qO- https://raw.githubusercontent.com/Jigsaw-Code/outline-server/master/src/server_manager/install_scripts/install_server.sh)"

# Optimize Outline settings
log "Optimizing Outline settings..."
docker exec outline-shadowbox sed -i 's/"encryptionMethod":"chacha20-ietf-poly1305"/"encryptionMethod":"aes-256-gcm"/g' /opt/outline/persisted-state/shadowbox_config.json

# Install V2Ray
log "Installing V2Ray..."
bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)

# Generate V2Ray config
log "Generating V2Ray config..."
cat > /usr/local/etc/v2ray/config.json <<EOL
{
  "inbounds": [{
    "port": 10086,
    "protocol": "vmess",
    "settings": {
      "clients": [
        {
          "id": "$(uuidgen)",
          "alterId": 0
        }
      ]
    },
    "streamSettings": {
      "network": "ws",
      "wsSettings": {
        "path": "/v2ray"
      }
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  }]
}
EOL

# Configure firewall
log "Configuring firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 10086/tcp
ufw allow 20923/tcp
ufw allow 35026/tcp
ufw allow 35026/udp
ufw --force enable

# Install and configure Nginx as reverse proxy
log "Installing and configuring Nginx..."
apt-get install -y nginx
cat > /etc/nginx/sites-available/v2ray <<EOL
server {
    listen 443 ssl;
    server_name _;

    ssl_certificate /etc/letsencrypt/live/YOUR_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/YOUR_DOMAIN/privkey.pem;

    location /v2ray {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10086;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
    }
}
EOL
ln -s /etc/nginx/sites-available/v2ray /etc/nginx/sites-enabled/
rm /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx

# Optimize system settings
log "Optimizing system settings..."
cat >> /etc/sysctl.conf <<EOL
net.ipv4.tcp_fastopen = 3
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 5000
EOL
sysctl -p

# Increase max open files
log "Increasing max open files..."
echo "* soft nofile 51200" | sudo tee -a /etc/security/limits.conf
echo "* hard nofile 51200" | sudo tee -a /etc/security/limits.conf

# Optimize DNS settings
log "Optimizing DNS settings..."
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf > /dev/null
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf > /dev/null

# Optimize Docker settings
log "Optimizing Docker settings..."
cat << EOF | sudo tee /etc/docker/daemon.json
{
  "mtu": 1500,
  "max-concurrent-downloads": 10,
  "max-concurrent-uploads": 10
}
EOF

# Set up automatic updates
log "Setting up automatic updates..."
echo 'APT::Periodic::Update-Package-Lists "1";' > /etc/apt/apt.conf.d/20auto-upgrades
echo 'APT::Periodic::Unattended-Upgrade "1";' >> /etc/apt/apt.conf.d/20auto-upgrades

# Start services
log "Starting services..."
systemctl start v2ray
systemctl enable v2ray
systemctl restart docker
docker restart outline-shadowbox

# Clean up
log "Cleaning up..."
apt-get autoremove -y
apt-get clean

# Create a script for generating new Outline access keys
log "Creating script for generating new Outline access keys..."
cat > /usr/local/bin/create_outline_key.sh <<EOL
#!/bin/bash
API_URL=\$(sudo docker exec outline-shadowbox cat /opt/outline/access.txt | jq -r '.apiUrl')
NEW_KEY=\$(curl -s -X POST "\${API_URL}/access-keys")
ACCESS_URL=\$(echo \$NEW_KEY | jq -r '.accessUrl')
echo "New access key created successfully."
echo "Access URL: \$ACCESS_URL"
EOL
chmod +x /usr/local/bin/create_outline_key.sh

log "Setup complete. Please note the following:"
log "1. Replace 'YOUR_DOMAIN' in the Nginx configuration with your actual domain."
log "2. Set up SSL certificates using Let's Encrypt or your preferred method."
log "3. Outline access keys can be found in /opt/outline/access_keys.txt"
log "4. To create a new Outline access key, run: sudo /usr/local/bin/create_outline_key.sh"
log "5. V2Ray client config: Server: YOUR_IP, Port: 443, UUID: Check /usr/local/etc/v2ray/config.json, Path: /v2ray"
log "6. Some changes may require a system reboot to take full effect."

log "VPN setup and optimization completed successfully!"