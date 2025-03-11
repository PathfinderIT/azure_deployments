#!/bin/bash
# Setup script for Portainer Agent on Ubuntu 24.04 LTS
# Author: Sam King (spoon.rip)

set -e

# Update system and install dependencies if needed
echo "Checking for dependencies..."
if ! command -v podman &> /dev/null; then
    echo "Podman not found, installing dependencies..."
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y curl apt-transport-https ca-certificates gnupg lsb-release
    sudo apt install -y podman containernetworking-plugins
    
    # Enable and start Podman socket
    echo "Enabling Podman socket..."
    sudo systemctl enable --now podman.socket
else
    echo "Podman already installed, continuing with agent setup..."
fi

# Clean up any existing Portainer Agent containers
echo "Cleaning up any existing Portainer Agent containers..."
sudo podman rm -f portainer_agent 2>/dev/null || true

# Install Portainer Agent
echo "Installing Portainer Agent..."
sudo podman run -d \
  -p 9001:9001 \
  --name portainer_agent \
  --restart=always \
  --privileged \
  -v /run/podman/podman.sock:/var/run/docker.sock \
  -v /var/run:/var/run \
  -v /var/lib/podman:/var/lib/docker \
  docker.io/portainer/agent:latest

# Check if Portainer Agent container is running
echo "Verifying Portainer Agent container status..."
sudo podman ps | grep portainer_agent

# Get the VM's public IP address
PUBLIC_IP=$(curl -s http://ifconfig.me)

# Output access information
echo ""
echo "======================================================"
echo "Portainer Agent setup completed successfully!"
echo "======================================================"
echo ""
echo "Your Portainer Agent is now running."
echo ""
echo "To add this environment to your Portainer instance:"
echo "1. Navigate to your Portainer Server interface"
echo "2. Go to Environments > Add environment"
echo "3. Select 'Agent' as the environment type"
echo "4. Use the following URL for the Agent URL field:"
echo "   ${PUBLIC_IP}:9001"
echo ""
echo "Don't forget to configure appropriate Network Security Group rules"
echo "in Azure to allow traffic on port 9001."
