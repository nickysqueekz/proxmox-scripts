#!/usr/bin/env bash
# Author: nickysqueekz
# Repo: https://github.com/nickysqueekz/proxmox-scripts
# Description: Creates an LXC container for LocalAI with Mistral 7B Instruct (CPU-only)
# License: MIT

set -e

header_info() {
  echo -e "🌐 \e[1mLocalAI (Mistral 7B Instruct) LXC Installer\e[0m"
  echo "This script creates a Proxmox LXC with LocalAI and Mistral for OpenAI-style use."
  echo "CPU-only, optimized for chat-based summarization and camera scene description."
  echo ""
}

header_info

# Defaults
DEFAULT_LXC_ID=10065
DEFAULT_HOSTNAME="localai-mistral"
DEFAULT_STORAGE="local-lvm"
DEFAULT_BRIDGE="vmbr0"
DEFAULT_VLAN=10
DEFAULT_RAM=12288
DEFAULT_SWAP=1024
DEFAULT_CORES=4
TEMPLATE=$(pveam available | grep debian-12 | sort -r | head -n1 | awk '{print $2}')
MODEL_URL="https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct.Q4_K_M.gguf"
MODEL_NAME="mistral-7b-instruct.Q4_K_M.gguf"
MODEL_ALIAS="mistral"

# Prompt with defaults
read -rp "🔢 Enter LXC ID [${DEFAULT_LXC_ID}]: " LXC_ID
LXC_ID=${LXC_ID:-$DEFAULT_LXC_ID}

read -rp "🖥️ Enter Hostname [${DEFAULT_HOSTNAME}]: " HOSTNAME
HOSTNAME=${HOSTNAME:-$DEFAULT_HOSTNAME}

read -rp "💾 Enter Storage Pool [${DEFAULT_STORAGE}]: " STORAGE
STORAGE=${STORAGE:-$DEFAULT_STORAGE}

read -rp "🌐 Enter Bridge [${DEFAULT_BRIDGE}]: " BRIDGE
BRIDGE=${BRIDGE:-$DEFAULT_BRIDGE}

read -rp "🔌 Enter VLAN Tag [${DEFAULT_VLAN}]: " VLAN_TAG
VLAN_TAG=${VLAN_TAG:-$DEFAULT_VLAN}

read -rp "🧠 Enter RAM (MB) [${DEFAULT_RAM}]: " RAM_MB
RAM_MB=${RAM_MB:-$DEFAULT_RAM}

read -rp "📀 Enter Swap (MB) [${DEFAULT_SWAP}]: " SWAP_MB
SWAP_MB=${SWAP_MB:-$DEFAULT_SWAP}

read -rp "⚙️ Enter CPU Cores [${DEFAULT_CORES}]: " CPU_CORES
CPU_CORES=${CPU_CORES:-$DEFAULT_CORES}

# Template check
echo "📄 Using template: $TEMPLATE"
echo "🔍 Checking if template $TEMPLATE exists in local storage..."

if [ ! -f "/var/lib/vz/template/cache/$TEMPLATE" ]; then
  echo "📦 Template not found locally. Downloading..."
  pveam update
  pveam download local "$TEMPLATE"
else
  echo "✅ Template found in cache."
fi

echo "📦 Creating unprivileged LXC container..."
pct create "$LXC_ID" local:vztmpl/$TEMPLATE \
  --hostname "$HOSTNAME" \
  --cores "$CPU_CORES" \
  --memory "$RAM_MB" \
  --swap "$SWAP_MB" \
  --net0 name=eth0,bridge="$BRIDGE",tag="$VLAN_TAG",ip=dhcp \
  --ostype debian \
  --rootfs "$STORAGE":10 \
  --unprivileged 1 \
  --features nesting=1 \
  --start 1 \
  --onboot 1 \
  --description "LocalAI + Mistral 7B Instruct container"

echo "🛠️ Configuring LocalAI inside container $LXC_ID..."
pct exec "$LXC_ID" -- bash -c "
  set -e
  apt update && apt upgrade -y
  apt install -y curl wget unzip build-essential libopenblas-dev

  echo '⬇️ Installing LocalAI...'
  curl -s https://raw.githubusercontent.com/go-skynet/LocalAI/main/install.sh | bash

  mkdir -p /models
  cd /models
  echo '⬇️ Downloading Mistral model...'
  wget -q --show-progress \"$MODEL_URL\" -O \"$MODEL_NAME\"

  echo '🧠 Writing config.yaml...'
  cat <<EOF > /models/config.yaml
- name: $MODEL_ALIAS
  backend: llama-cpp
  model: $MODEL_NAME
  context_size: 4096
  f16: true
EOF

  echo '⚙️ Setting up systemd service...'
  cat <<EOF > /etc/systemd/system/localai.service
[Unit]
Description=LocalAI (OpenAI-compatible local LLM server)
After=network.target

[Service]
ExecStart=/localai --models-path /models
Restart=always
RestartSec=5
WorkingDirectory=/models
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl enable localai
  systemctl start localai
"

echo ""
echo "✅ LocalAI setup complete!"
IP_ADDR=$(pct exec "$LXC_ID" -- hostname -I | awk '{print $1}')
echo "🌐 Access the API at: http://$IP_ADDR:8080/v1/models"
