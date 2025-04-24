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

# Prompts
read -rp "🔢 Enter LXC ID (e.g. 10065): " LXC_ID
read -rp "🖥️ Enter Hostname (e.g. localai): " HOSTNAME
read -rp "💾 Enter Storage Pool (e.g. local-lvm): " STORAGE
read -rp "🌐 Enter Bridge (e.g. vmbr0): " BRIDGE
read -rp "🔌 Enter VLAN Tag (e.g. 10): " VLAN_TAG
read -rp "🧠 Enter RAM (MB, e.g. 12288): " RAM_MB
read -rp "📀 Enter Swap (MB, e.g. 1024): " SWAP_MB
read -rp "⚙️ Enter CPU Cores (e.g. 4): " CPU_CORES

TEMPLATE="debian-12-standard_20240210_amd64.tar.zst"
MODEL_URL="https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct.Q4_K_M.gguf"
MODEL_NAME="mistral-7b-instruct.Q4_K_M.gguf"
MODEL_ALIAS="mistral"

echo "📦 Creating unprivileged LXC container..."
pveam update
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
echo "📡 You can now call Mistral from Home Assistant using rest_command!"
