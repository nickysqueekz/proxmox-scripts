#!/usr/bin/env bash
set -euo pipefail
trap 'echo "❌ Script failed on line $LINENO. Exiting." >&2' ERR

echo -e "\n🌐 \e[1mLocalAI LXC Installer v1.9.2 (Without Model Auto-Download)\e[0m"

# Set defaults
LXC_ID=10065
HOSTNAME="localai-mistral"
STORAGE="local-lvm"
BRIDGE="vmbr0"
VLAN_TAG=10
RAM_MB=12288
SWAP_MB=1024
CPU_CORES=4

# Prompt for root password
while true; do
  read -rsp "🔐 Enter root password for LXC (input hidden): " ROOT_PASSWORD
  echo
  read -rsp "🔐 Confirm password: " CONFIRM_PASSWORD
  echo
  [ "$ROOT_PASSWORD" = "$CONFIRM_PASSWORD" ] && break
  echo "❌ Passwords do not match. Try again."
done

# Template
TEMPLATE=$(pveam available | awk '$2 ~ /^debian-12-standard/ { print $2 }' | sort -r | head -n1)
[ -z "$TEMPLATE" ] && echo "❌ Could not find a Debian 12 template" && exit 1
[ ! -f "/var/lib/vz/template/cache/$TEMPLATE" ] && pveam download local "$TEMPLATE"

# Create LXC
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

# Set password
pct exec "$LXC_ID" -- bash -c "echo 'root:$ROOT_PASSWORD' | chpasswd"

# Install dependencies and LocalAI only (no Python/pip/model logic)
pct exec "$LXC_ID" -- bash -c "
  set -e
  apt update && apt install -y curl wget file build-essential libopenblas-dev ca-certificates

  mkdir -p /usr/local/bin /models
  cd /usr/local/bin

  echo '📦 Fetching latest LocalAI version...'
  VERSION=\$(curl -s https://api.github.com/repos/go-skynet/LocalAI/releases/latest | grep '"tag_name":' | sed -E 's/.*\"([^\"]+)\".*/\1/')
  BINARY_URL="https://github.com/go-skynet/LocalAI/releases/download/\${VERSION}/localai-linux-amd64"
  echo "📥 Downloading from: \$BINARY_URL"

  wget -q "\$BINARY_URL" -O localai
  file localai | grep -q 'ELF 64-bit' || { echo '❌ Invalid binary'; exit 1; }
  chmod +x localai
  ./localai --version || echo '⚠️ Could not determine version'

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

IP_ADDR=$(pct exec "$LXC_ID" -- hostname -I | awk '{print $1}')
echo -e "\n🌐 LocalAI is expected at: http://$IP_ADDR:8080"
echo -e "\n🔹 Model not installed automatically in this version."
echo "To manually install the Mistral model, run the following on your PVE host:"
echo
cat <<'EOF'
pip install huggingface_hub[cli] --break-system-packages
huggingface-cli login  # if needed
huggingface-cli download TheBloke/Mistral-7B-Instruct-v0.1-GGUF mistral-7b-instruct-v0.1.Q4_K_M.gguf \
  --local-dir /var/lib/lxc-models \
  --local-dir-use-symlinks False
mkdir -p /var/lib/lxc/10065/rootfs/models
cp /var/lib/lxc-models/mistral-7b-instruct-v0.1.Q4_K_M.gguf /var/lib/lxc/10065/rootfs/models/
EOF

echo -e "\n✅ LocalAI container is built. Model installation is deferred for manual control."
