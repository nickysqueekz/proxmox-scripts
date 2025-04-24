#!/usr/bin/env bash
# Author: nickysqueekz
# Repo: https://github.com/nickysqueekz/proxmox-scripts
# Description: Minimal Proxmox LXC installer for LocalAI + Mistral (OpenAI API, CPU-only)
# License: MIT

set -euo pipefail
trap 'echo "❌ Script failed on line $LINENO. Exiting." >&2' ERR

header_info() {
  echo -e "\n🌐 \e[1mLocalAI (Mistral 7B Instruct) LXC Installer v1.7\e[0m"
  echo "Minimal, fail-fast Proxmox script to install LocalAI with Mistral support (CPU-only)."
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
MODEL_URL="https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct.Q4_K_M.gguf"
MODEL_NAME="mistral-7b-instruct.Q4_K_M.gguf"
MODEL_ALIAS="mistral"

# Prompt for values
read -rp "🔢 LXC ID [${DEFAULT_LXC_ID}]: " LXC_ID
LXC_ID=${LXC_ID:-$DEFAULT_LXC_ID}

read -rp "🖥️ Hostname [${DEFAULT_HOSTNAME}]: " HOSTNAME
HOSTNAME=${HOSTNAME:-$DEFAULT_HOSTNAME}

read -rp "💾 Storage Pool [${DEFAULT_STORAGE}]: " STORAGE
STORAGE=${STORAGE:-$DEFAULT_STORAGE}

read -rp "🌐 Bridge [${DEFAULT_BRIDGE}]: " BRIDGE
BRIDGE=${BRIDGE:-$DEFAULT_BRIDGE}

read -rp "🔌 VLAN Tag [${DEFAULT_VLAN}]: " VLAN_TAG
VLAN_TAG=${VLAN_TAG:-$DEFAULT_VLAN}

read -rp "🧠 RAM (MB) [${DEFAULT_RAM}]: " RAM_MB
RAM_MB=${RAM_MB:-$DEFAULT_RAM}

read -rp "📀 Swap (MB) [${DEFAULT_SWAP}]: " SWAP_MB
SWAP_MB=${SWAP_MB:-$DEFAULT_SWAP}

read -rp "⚙️ CPU Cores [${DEFAULT_CORES}]: " CPU_CORES
CPU_CORES=${CPU_CORES:-$DEFAULT_CORES}

# Root password prompt with confirmation
echo
while true; do
  read -rsp "🔐 Enter root password for LXC (input hidden): " ROOT_PASSWORD
  echo
  read -rsp "🔐 Confirm password: " CONFIRM_PASSWORD
  echo
  [ "$ROOT_PASSWORD" = "$CONFIRM_PASSWORD" ] && break
  echo "❌ Passwords do not match. Please try again."
done

# Template selection - strict match to avoid TurnKey
TEMPLATE=$(pveam available | awk '$2 ~ /^debian-12-standard/ { print $2 }' | sort -r | head -n1)
echo "📄 Using template: $TEMPLATE"
[ -z "$TEMPLATE" ] && echo "❌ Could not find a clean Debian 12 standard template. Aborting." && exit 1

# Download template if missing
[ ! -f "/var/lib/vz/template/cache/$TEMPLATE" ] && {
  echo "📦 Downloading template..."
  pveam update
  pveam download local "$TEMPLATE"
}

# Create the container
echo "📦 Creating LXC container..."
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
  --onboot 1

# Set root password securely
echo "🔐 Setting root password..."
pct exec "$LXC_ID" -- bash -c "echo 'root:$ROOT_PASSWORD' | chpasswd"

# Inside container setup
echo "🧠 Installing LocalAI + model..."
pct exec "$LXC_ID" -- bash -c "
  set -e
  export DEBIAN_FRONTEND=noninteractive
  apt update && apt upgrade -y
  apt install -y --no-install-recommends curl wget unzip build-essential libopenblas-dev

  mkdir -p /usr/local/bin
  cd /usr/local/bin
  echo '⬇️ Downloading LocalAI binary...'
  if ! wget -q https://github.com/go-skynet/LocalAI/releases/latest/download/localai-linux-amd64 -O localai; then
    echo '❌ ERROR: Failed to download LocalAI binary.'
    exit 1
  fi
  chmod +x localai

  mkdir -p /models
  cd /models
  echo '📦 Downloading Mistral model...'
  if ! wget -q \"$MODEL_URL\" -O \"$MODEL_NAME\"; then
    echo '❌ ERROR: Failed to download Mistral model from HuggingFace.'
    exit 1
  fi

  echo '🧠 Writing config.yaml...'
  cat <<EOF > /models/config.yaml
- name: $MODEL_ALIAS
  backend: llama-cpp
  model: $MODEL_NAME
  context_size: 4096
  f16: true
EOF

  echo '⚙️ Creating systemd service...'
  cat <<EOF > /etc/systemd/system/localai.service
[Unit]
Description=LocalAI Server
After=network.target

[Service]
ExecStart=/usr/local/bin/localai --models-path /models
Restart=always
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

# Health check
IP_ADDR=$(pct exec "$LXC_ID" -- hostname -I | awk '{print $1}')
echo "📡 Testing LocalAI API..."
if curl -s --fail "http://$IP_ADDR:8080/v1/models" > /dev/null; then
  echo -e "\n✅ LocalAI is ready!"
  echo "🌐 Access it at: http://$IP_ADDR:8080"
else
  echo "❌ ERROR: LocalAI did not respond. Check logs in the LXC."
  exit 1
fi
