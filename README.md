# Proxmox LXC Installer: LocalAI + Mistral 7B (CPU-only)

This script creates a ready-to-run **unprivileged LXC container** on Proxmox that hosts:

- 🧠 [LocalAI](https://github.com/go-skynet/LocalAI): an OpenAI-compatible local LLM server
- 🔮 [Mistral 7B Instruct](https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF): a compact and powerful language model for summarization, automation, coding help, and smart home narration
- 📦 Systemd-managed, OpenAI-compatible REST API (http://<LXC-IP>:8080)

---

## 🚀 What It Does

- Prompts for LXC config (ID, VLAN, RAM, CPU, etc.)
- Creates a **Debian 12** LXC (unprivileged + nesting)
- Installs LocalAI
- Downloads Mistral 7B Instruct in `gguf` format (Q4_K_M for CPU efficiency)
- Configures systemd service to start LocalAI on boot

---

## 🛠️ How to Run It

### Option 1: Save + Run

```bash
wget https://raw.githubusercontent.com/nickysqueekz/proxmox-scripts/main/create-localai-mistral.sh
chmod +x create-localai-mistral.sh
./create-localai-mistral.sh

### Option 2: Run Direct

bash <(curl -s https://raw.githubusercontent.com/nickysqueekz/proxmox-scripts/main/create-localai-mistral.sh)

