#!/bin/bash
# Setup script for Podman and Portainer BE on Ubuntu 24.04 LTS
# Author: Sam King (spoon.rip)

set -e

# Update system and install dependencies
echo "Updating system packages..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl apt-transport-https ca-certificates gnupg lsb-release

# Install Podman and CNI plugins
echo "Installing Podman and CNI plugins..."
sudo apt install -y podman containernetworking-plugins

# Verify Podman installation
PODMAN_VERSION=$(podman --version)
echo "Podman installed: $PODMAN_VERSION"

# Enable and start Podman socket
echo "Enabling Podman socket..."
sudo systemctl enable --now podman.socket
sudo systemctl status podman.socket --no-pager

# Clean up any existing Portainer containers and volumes
echo "Cleaning up any existing Portainer containers and volumes..."
sudo podman rm -f portainer 2>/dev/null || true
sudo podman volume rm portainer_data 2>/dev/null || true

# Create volume for Portainer data
echo "Creating Portainer data volume..."
sudo podman volume create portainer_data

# Install Portainer Business Edition
echo "Installing Portainer Business Edition..."
sudo podman run -d \
  -p 8000:8000 \
  -p 9443:9443 \
  -p 9000:9000 \
  --name portainer \
  --restart=always \
  --privileged \
  -v /run/podman/podman.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  docker.io/portainer/portainer-ee:lts

# Check if Portainer container is running
echo "Verifying Portainer container status..."
sudo podman ps | grep portainer

# Get the VM's public IP address
PUBLIC_IP=$(curl -s http://ifconfig.me)

# Output access information
echo ""
echo "======================================================"
echo "Podman and Portainer BE setup completed successfully!"
echo "======================================================"
echo ""
echo "You can access Portainer using the following URL:"
echo "https://${PUBLIC_IP}:9443"
echo ""
echo "Notes:"
echo "1. You will need a Portainer Business Edition license key to complete setup"
echo "2. HTTP port 9000 is also exposed for legacy access if needed"
echo "3. TCP tunnel server is exposed on port 8000 for Edge compute features"
echo ""
echo "Don't forget to configure appropriate Network Security Group rules"
echo "in Azure to allow traffic on ports 9443, 9000, and 8000."
