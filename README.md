# Proxmox Oracle AI Database 26ai

> **Deploy Oracle AI Database 26ai Free on your Proxmox VE homelab in minutes.**  
> Open-source installer with whiptail TUI, LXC and VM support, and modular add-ons.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Oracle 26ai](https://img.shields.io/badge/Oracle-26ai_Free-red.svg)](https://container-registry.oracle.com/database/free)
[![Proxmox VE](https://img.shields.io/badge/Proxmox-VE_8%2B-blue.svg)](https://www.proxmox.com)

---

## Quick Start

**Deploy via LXC container (recommended):**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/runionow/proxmox-oracle26ai/main/ct/oracle26ai.sh)
```

**Deploy via KVM virtual machine:**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/runionow/proxmox-oracle26ai/main/ct/oracle26ai-vm.sh)
```

> ⚠️ Run on your **Proxmox VE host** as root. Always review scripts before piping to bash.

---

## Features

| Feature | Description |
|---------|-------------|
| 🐳 **Docker-based** | Uses Oracle's official container image — no native install needed |
| 🖥️ **Dual deployment** | Choose LXC (lightweight) or KVM VM (full isolation) |
| 🎨 **whiptail TUI** | Guided interactive installer — no config files required |
| 🔢 **Image choice** | Full (~10GB) or Lite (~2GB) Oracle 26ai Free image |
| 🤖 **AI-ready** | Vector search, embeddings, AI-powered SQL features |
| 🧩 **Modular add-ons** | APEX+ORDS, vector demo, backup/restore, SSL/TLS |
| 🔄 **Smart defaults** | 4 CPU / 8GB RAM / 32GB disk — all adjustable |

---

## Prerequisites

- **Proxmox VE 8.x+** running on bare metal
- **Internet connection** (to pull Oracle container image)
- **Resources**: 4+ CPU cores, 8+ GB RAM, 32+ GB disk free
- **Run as root** on the Proxmox host

---

## Architecture

```
Proxmox VE Host
├── ct/oracle26ai.sh       ─── Creates LXC Container
│   └── LXC (Debian 12, privileged)
│       └── Docker CE
│           └── oracle-26ai  (container-registry.oracle.com/database/free)
│               ├── Port 1521 — Oracle Listener (SQL*Net)
│               ├── Port 8080 — ORDS / APEX  (optional)
│               └── Port 8443 — HTTPS ORDS   (optional)
│
└── ct/oracle26ai-vm.sh    ─── Creates KVM VM
    └── KVM VM (Debian 12 cloud-init)
        └── Docker CE
            └── oracle-26ai  (same image)
```

---

## Configuration

Copy `.env.sample` to `.env` to pre-configure the installer (skips whiptail prompts):

```bash
cp .env.sample .env
# Edit .env with your settings
```

Key variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `ORACLE_PWD` | `ChangeMe123!` | Oracle SYS/SYSTEM password |
| `ORACLE_IMAGE_TAG` | `23.26.0.0` | Full image tag (`latest-lite` for Lite) |
| `CT_CORES` | `4` | CPU cores |
| `CT_MEMORY` | `8192` | RAM in MB |
| `CT_DISK_SIZE` | `32` | Disk in GB |
| `CT_STORAGE` | `local-lvm` | Proxmox storage pool |
| `CT_NETWORK` | `dhcp` | `dhcp` or `192.168.1.100/24` |
| `CONTAINER_RUNTIME` | `auto` | `auto`, `docker`, or `podman` |

---

## Module Scripts

Run these **after** the base Oracle deployment completes:

```bash
# APEX + ORDS web interface (port 8080)
bash scripts/setup-apex-ords.sh

# Vector search demo data
bash scripts/setup-vector-demo.sh

# SSL/TLS for ORDS (self-signed, port 8443)
bash scripts/setup-ssl.sh

# Backup Oracle database
bash scripts/backup.sh

# Restore from backup
bash scripts/restore.sh /var/backups/oracle-26ai/oracle26ai_20260314_120000.dmp

# Remove deployment
bash scripts/uninstall.sh
```

---

## Connection Guide

**SQL*Plus (inside container):**
```bash
docker exec -it oracle-26ai sqlplus sys/YourPassword@localhost:1521/FREEPDB1 as sysdba
```

**JDBC connection string:**
```
jdbc:oracle:thin:@//<CONTAINER-IP>:1521/FREEPDB1
```

**Python (cx_Oracle / oracledb):**
```python
import oracledb
conn = oracledb.connect(user="sys", password="YourPassword",
                        dsn="<CONTAINER-IP>:1521/FREEPDB1", mode=oracledb.AUTH_MODE_SYSDBA)
```

**Oracle SQL Developer:**
- Host: `<CONTAINER-IP>`
- Port: `1521`
- Service Name: `FREEPDB1`
- User: `sys` / Role: `SYSDBA`

---

## Troubleshooting

**Docker won't start in LXC:**
```bash
# Check LXC features — must have nesting=1,keyctl=1
pct config <VMID> | grep features
# Fix: pct set <VMID> --features nesting=1,keyctl=1
```

**Oracle container not starting (`DATABASE IS READY TO USE!` never appears):**
```bash
docker logs oracle-26ai
# Common cause: insufficient /dev/shm
mount -o remount,size=2g /dev/shm
docker restart oracle-26ai
```

**Oracle image pull fails with "unauthorized":**
1. Visit https://container-registry.oracle.com
2. Sign in → Database → Free → Accept license
3. `docker login container-registry.oracle.com`
4. Re-run the installer

**Port 1521 already in use:**
```bash
# Set different port in .env:
ORACLE_LISTENER_PORT=11521
```

**Out of disk space:**
```bash
pvesm status  # check storage usage
# Full Oracle image needs ~15GB + data volume
```

---

## Contributing

1. Fork this repository
2. Create a feature branch: `git checkout -b feat/my-feature`
3. Follow conventions:
   - `set -euo pipefail` in every script
   - Use `msg_info/msg_ok/msg_error` from `misc/build.func`
   - Run `bash -n <script>` before committing
4. Open a pull request

---

## License

MIT License — Copyright 2026 Arun Nekkalapudi

See [LICENSE](LICENSE) for full text.

---

*Powered by [Oracle AI Database 26ai Free](https://container-registry.oracle.com/database/free) · Built for [Proxmox VE](https://www.proxmox.com)*
