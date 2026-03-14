# Proxmox Oracle AI Database 26ai Helper Scripts

## TL;DR

> **Quick Summary**: Build an open-source, MIT-licensed Proxmox helper script project that deploys Oracle AI Database 26ai Free via Docker inside either LXC containers or KVM VMs, with modular opt-in features (APEX/ORDS, vector search demo, backup/restore, SSL/TLS) and a whiptail-based interactive TUI.
> 
> **Deliverables**:
> - LXC creation script with whiptail TUI (`ct/oracle26ai.sh`)
> - KVM VM creation script with whiptail TUI (`ct/oracle26ai-vm.sh`)
> - Oracle 26ai install script (`install/oracle26ai-install.sh`)
> - Modular feature scripts: APEX/ORDS, vector demo, backup/restore, SSL
> - Shared function library (`misc/build.func`)
> - README, LICENSE (MIT), .env.sample
> 
> **Estimated Effort**: Medium-Large
> **Parallel Execution**: YES — 4 waves + final verification
> **Critical Path**: Task 1 → Task 2 → Task 4/5/6 → Task 7-10 → Task 11 → F1-F4

---

## Context

### Original Request
User wants to create a Proxmox script template for deploying Oracle AI Database 26ai, and share it publicly so others can spin up their own Oracle 26ai in their Proxmox environments.

### Interview Summary
**Key Discussions**:
- **Deployment**: Both LXC (Docker-in-LXC) AND KVM VM (Docker-in-VM). User chooses at runtime.
- **Project format**: Standalone repo, own structure. Can contribute to community-scripts later.
- **Container runtime**: Auto-detect Docker/Podman or prompt user to choose and install.
- **Oracle image**: User picks Full (~10GB, all features) or Lite (~2GB, faster) at install time.
- **Features**: Modular — basic DB first, then opt-in APEX+ORDS, vector search demo, backup/restore, SSL/TLS.
- **UI**: whiptail interactive TUI (professional, guided).
- **Networking**: DHCP default, static IP optional via whiptail prompt.
- **Resources**: Defaults 4 CPU / 8GB RAM / 32GB disk (adjustable via whiptail).
- **License**: MIT.
- **Audience**: Both homelab enthusiasts and developers.

**Research Findings**:
- Oracle AI Database 26ai GA since Jan 27, 2026 (Linux x86-64)
- Container image: `container-registry.oracle.com/database/free:23.26.0.0` (also `:latest`, `:latest-lite`)
- Docker run pattern: `-e ORACLE_PWD=xxx -p 1521:1521 --shm-size=1g`
- Health check: wait for `"DATABASE IS READY TO USE!"` in container logs (3-8 min)
- community-scripts/ProxmoxVE pattern: `ct/`, `install/`, `misc/build.func`, whiptail TUI, `pct create`
- Docker-in-LXC requires: `--features nesting=1,keyctl=1`, privileged mode recommended
- shakiyam/Oracle-AI-Database-26ai-Free-on-Docker (13 stars) — simple Docker wrapper exists
- ggordham/ora-lab — Terraform + Proxmox for Oracle VMs exists

### Metis Review
**Identified Gaps** (addressed):
- **shm-size in Docker-in-LXC**: LXC must explicitly mount adequate shm or use privileged mode. Script must validate shm before Oracle start. → Added to install script requirements.
- **10GB image pull UX**: Separate `docker pull` from `docker run` for progress visibility. Add timing estimate message. → Added to install script.
- **Oracle startup time**: 3-8 min first-run init. Need health check loop with spinner + 600s timeout. → Added to install script.
- **Lite image tag uncertainty**: Must validate tag exists before pull, handle failure gracefully. → Added validation step.
- **APEX/ORDS complexity**: Multi-step process (ORDS download, config, connection pools). Use separate module. → Kept as separate modular script.
- **Vector demo scope**: Defined as SQL-only demo — pre-built SQL file with sample vector data and 3 example queries. No ML model, no external API. → Scoped explicitly.
- **Storage backend detection**: Must handle local, local-lvm, local-zfs, NFS, Ceph. → Follow community-scripts pattern.
- **Oracle registry auth**: Free images may require accepting terms at container-registry.oracle.com. Script must detect auth failure and guide user. → Added to install script.
- **Edge cases**: No internet, full storage, VMID collision, port collision, Docker daemon failure, OOM kill, duplicate runs, whiptail cancel handling. → All incorporated into validation functions and error handling.

---

## Work Objectives

### Core Objective
Create a production-quality, open-source Proxmox helper script project that lets anyone deploy Oracle AI Database 26ai Free on their Proxmox VE server with a single command, choosing between LXC or VM deployment, with modular add-on features.

### Concrete Deliverables
```
proxmox-oracle26ai/
├── ct/
│   ├── oracle26ai.sh              # LXC creation entry point
│   └── oracle26ai-vm.sh           # VM creation entry point
├── install/
│   └── oracle26ai-install.sh      # Oracle DB install inside LXC/VM
├── misc/
│   └── build.func                 # Shared functions library
├── scripts/
│   ├── setup-apex-ords.sh         # APEX + ORDS module
│   ├── setup-vector-demo.sh       # Vector search demo module
│   ├── backup.sh                  # Backup script
│   ├── restore.sh                 # Restore script
│   └── setup-ssl.sh               # SSL/TLS setup
├── sql/
│   └── vector-demo.sql            # Vector search demo SQL data
├── .env.sample                    # Configuration template
├── .gitignore
├── LICENSE                        # MIT
└── README.md                      # Full documentation
```

### Definition of Done
- [ ] `bash <(curl -fsSL https://raw.githubusercontent.com/.../ct/oracle26ai.sh)` creates a working Oracle 26ai LXC on Proxmox
- [ ] `bash <(curl -fsSL https://raw.githubusercontent.com/.../ct/oracle26ai-vm.sh)` creates a working Oracle 26ai VM on Proxmox
- [ ] Oracle DB accessible on port 1521 after deployment
- [ ] All modular scripts (APEX, vector, backup, SSL) run independently without breaking base DB
- [ ] All scripts pass `shellcheck` and `bash -n` syntax check
- [ ] README contains one-liner install, architecture overview, connection guide, and troubleshooting

### Must Have
- Both LXC and VM deployment paths
- whiptail TUI for guided setup
- Docker/Podman auto-detection + install
- Full vs Lite Oracle image choice
- DHCP default networking with static IP option
- Health check loop with progress feedback during Oracle startup
- Separate `docker pull` with progress (not embedded in `docker run`)
- Graceful error handling with clear messages on every failure path
- `set -euo pipefail` in every script
- MIT LICENSE file

### Must NOT Have (Guardrails)
- NO config file parser or feature flag system — modularity = separate script files
- NO ACME / Let's Encrypt integration — SSL = self-signed certificates only
- NO backup scheduler or log rotation — single backup + single restore, that's it
- NO more than 6 whiptail screens in any single TUI flow
- NO Podman support in v1 unless trivially compatible — mark as future enhancement
- NO native Oracle RPM installation — Docker/Podman container images only
- NO inline comments on every line — comments only on non-obvious logic
- NO hardcoded passwords in committed code — always use variables from .env or user input
- NO Terraform, Ansible, or other orchestration tools — pure bash
- NO Oracle paid editions — Free edition only

---

## Verification Strategy

> **ZERO HUMAN INTERVENTION** — ALL verification is agent-executed. No exceptions.

### Test Decision
- **Infrastructure exists**: NO (bash scripts project)
- **Automated tests**: None (bash scripts — no unit test framework)
- **Framework**: shellcheck for static analysis, bash -n for syntax
- **Verification**: Agent-executed QA scenarios per task

### QA Policy
Every task MUST include agent-executed QA scenarios.
Evidence saved to `.sisyphus/evidence/task-{N}-{scenario-slug}.{ext}`.

- **Scripts**: Use Bash — `bash -n script.sh` (syntax), `shellcheck script.sh` (lint)
- **Functional**: Use Bash/tmux — source functions, run validators, check exit codes
- **Documentation**: Use Bash — verify file exists, check section headings, word count

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately — foundation, 3 parallel):
├── Task 1: Repo scaffolding (git init, dirs, LICENSE, .gitignore, .env.sample) [quick]
├── Task 2: Shared functions library (misc/build.func) [unspecified-high]
└── Task 3: Vector demo SQL data (sql/vector-demo.sql) [quick]

Wave 2 (After Wave 1 — core scripts, 3 parallel):
├── Task 4: LXC creation script (ct/oracle26ai.sh) [unspecified-high]
├── Task 5: VM creation script (ct/oracle26ai-vm.sh) [unspecified-high]
└── Task 6: Oracle install script (install/oracle26ai-install.sh) [deep]

Wave 3 (After Wave 2 — modular features, 4 parallel):
├── Task 7: APEX + ORDS module (scripts/setup-apex-ords.sh) [unspecified-high]
├── Task 8: Vector search demo runner (scripts/setup-vector-demo.sh) [quick]
├── Task 9: Backup + restore scripts (scripts/backup.sh, restore.sh) [quick]
└── Task 10: SSL/TLS setup (scripts/setup-ssl.sh) [quick]

Wave 4 (After Wave 3 — documentation + cleanup, 2 parallel):
├── Task 11: README.md finalization [writing]
└── Task 12: Uninstall/cleanup script (scripts/uninstall.sh) [quick]

Wave FINAL (After ALL tasks — verification, 4 parallel):
├── Task F1: Plan compliance audit [oracle]
├── Task F2: Code quality review (shellcheck all scripts) [unspecified-high]
├── Task F3: Real manual QA [unspecified-high]
└── Task F4: Scope fidelity check [deep]

Critical Path: Task 1 → Task 2 → Task 4 → Task 6 → Task 7 → Task 11 → F1-F4
Parallel Speedup: ~60% faster than sequential
Max Concurrent: 4 (Waves 2, 3)
```

### Dependency Matrix

| Task | Depends On | Blocks | Wave |
|------|-----------|--------|------|
| 1 | — | 2, 3, 4, 5, 6 | 1 |
| 2 | 1 | 4, 5, 6, 7, 8, 9, 10 | 1 |
| 3 | 1 | 8 | 1 |
| 4 | 1, 2 | 7, 8, 9, 10, 11 | 2 |
| 5 | 1, 2 | 11 | 2 |
| 6 | 1, 2 | 7, 8, 9, 10, 11 | 2 |
| 7 | 4, 6 | 10, 11 | 3 |
| 8 | 3, 4, 6 | 11 | 3 |
| 9 | 4, 6 | 11 | 3 |
| 10 | 4, 6, 7 | 11 | 3 |
| 11 | 4-10 | F1-F4 | 4 |
| 12 | 4, 6 | F1-F4 | 4 |
| F1-F4 | 1-12 | — | FINAL |

### Agent Dispatch Summary

| Wave | Tasks | Categories |
|------|-------|------------|
| 1 | 3 | T1 → `quick`, T2 → `unspecified-high`, T3 → `quick` |
| 2 | 3 | T4 → `unspecified-high`, T5 → `unspecified-high`, T6 → `deep` |
| 3 | 4 | T7 → `unspecified-high`, T8 → `quick`, T9 → `quick`, T10 → `quick` |
| 4 | 2 | T11 → `writing`, T12 → `quick` |
| FINAL | 4 | F1 → `oracle`, F2 → `unspecified-high`, F3 → `unspecified-high`, F4 → `deep` |

---

## TODOs

> Implementation + Verification = ONE Task. Never separate.
> EVERY task MUST have: Recommended Agent Profile + Parallelization info + QA Scenarios.

- [x] 1. Repo Scaffolding — git init, directories, LICENSE, .gitignore, .env.sample

  **What to do**:
  - Run `git init` in the project root
  - Create directory structure: `ct/`, `install/`, `misc/`, `scripts/`, `sql/`, `.sisyphus/evidence/`
  - Create `LICENSE` file with full MIT License text (Copyright 2026 Arun Nekkalapudi)
  - Create `.gitignore` with: `.env`, `*.log`, `.sisyphus/evidence/`, `node_modules/`, `.DS_Store`
  - Create `.env.sample` with ALL configurable variables documented:
    ```
    # Oracle Configuration
    ORACLE_PWD=ChangeMe123!        # Oracle SYS/SYSTEM password
    ORACLE_IMAGE_TAG=23.26.0.0     # Full image tag (use "latest-lite" for Lite image)
    ORACLE_CONTAINER_NAME=oracle-26ai
    ORACLE_LISTENER_PORT=1521
    ORACLE_ORDS_PORT=8080
    ORACLE_ORDS_SSL_PORT=8443
    # Proxmox Configuration
    CT_ID=auto                     # Container/VM ID (auto = next available)
    CT_HOSTNAME=oracle26ai
    CT_CORES=4
    CT_MEMORY=8192                 # MB
    CT_DISK_SIZE=32                # GB
    CT_STORAGE=local-lvm           # Proxmox storage pool
    CT_NETWORK=dhcp                # "dhcp" or static IP like "192.168.1.100/24"
    CT_GATEWAY=                    # Required if static IP
    CT_DNS=                        # DNS server (default: gateway)
    CT_BRIDGE=vmbr0                # Proxmox network bridge
    # Container Runtime
    CONTAINER_RUNTIME=auto         # "auto", "docker", or "podman"
    ```
  - Create skeleton `README.md` with project title, one-line description, and "Coming soon" placeholder sections

  **Must NOT do**:
  - Don't write any bash logic yet — this is pure scaffolding
  - Don't add excessive comments to .env.sample — one comment per variable max
  - Don't create README content beyond skeleton (Task 11 does full README)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Simple file creation, no logic, just boilerplate
  - **Skills**: []
    - No specialized skills needed
  - **Skills Evaluated but Omitted**:
    - `git-master`: Not needed — simple git init, no complex git operations

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 2, 3)
  - **Blocks**: Tasks 2, 3, 4, 5, 6
  - **Blocked By**: None (can start immediately)

  **References**:

  **Pattern References**:
  - community-scripts/ProxmoxVE repo (https://github.com/community-scripts/ProxmoxVE) — directory structure: `ct/`, `install/`, `misc/` convention
  - shakiyam/Oracle-AI-Database-26ai-Free-on-Docker `dotenv.sample` — Oracle env var naming conventions

  **External References**:
  - Oracle container registry: `container-registry.oracle.com/database/free` — tag `23.26.0.0` for GA, `latest-lite` for lite
  - MIT License text: https://opensource.org/licenses/MIT

  **WHY Each Reference Matters**:
  - community-scripts pattern ensures familiarity for Proxmox users who know the ecosystem
  - shakiyam's .env shows the standard Oracle container env vars that users expect

  **Acceptance Criteria**:

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Directory structure matches specification
    Tool: Bash
    Preconditions: Project root exists
    Steps:
      1. Run: find . -type d -not -path '*/.git/*' -not -path '*/.sisyphus/*' | sort
      2. Assert output contains: ./ct, ./install, ./misc, ./scripts, ./sql
    Expected Result: All 5 directories exist
    Failure Indicators: Any directory missing from output
    Evidence: .sisyphus/evidence/task-1-dir-structure.txt

  Scenario: LICENSE file is valid MIT
    Tool: Bash
    Preconditions: LICENSE file exists
    Steps:
      1. Run: head -1 LICENSE
      2. Assert: output contains "MIT License"
      3. Run: grep -c "Copyright" LICENSE
      4. Assert: count >= 1
    Expected Result: MIT License with copyright notice
    Failure Indicators: Missing file or wrong license text
    Evidence: .sisyphus/evidence/task-1-license.txt

  Scenario: .env.sample contains all required variables
    Tool: Bash
    Preconditions: .env.sample file exists
    Steps:
      1. Run: grep -c "^[A-Z_]*=" .env.sample
      2. Assert: count >= 14 (all variables listed above)
      3. Run: grep "ORACLE_PWD" .env.sample
      4. Assert: line exists and does NOT contain a real password
    Expected Result: All config variables present with safe defaults
    Failure Indicators: Missing variables or hardcoded real passwords
    Evidence: .sisyphus/evidence/task-1-env-sample.txt

  Scenario: .gitignore excludes sensitive files
    Tool: Bash
    Preconditions: .gitignore file exists
    Steps:
      1. Run: grep ".env" .gitignore
      2. Assert: .env is listed (not .env.sample)
    Expected Result: .env excluded, .env.sample not excluded
    Failure Indicators: .env missing from .gitignore
    Evidence: .sisyphus/evidence/task-1-gitignore.txt
  ```

  **Commit**: YES
  - Message: `feat: init repo with README skeleton, LICENSE, directory structure`
  - Files: `README.md, LICENSE, .gitignore, .env.sample, ct/, install/, misc/, scripts/, sql/`
  - Pre-commit: `test -f LICENSE && test -f .env.sample && test -d ct && test -d install`

- [x] 2. Shared Functions Library — misc/build.func

  **What to do**:
  - Create `misc/build.func` containing ALL shared bash functions used across every script
  - **Color variables**: `YW` (yellow), `GN` (green), `RD` (red), `BL` (blue), `CL` (clear/reset), `BFR` (buffer clear), `CM` (checkmark ✓), `CROSS` (✗), `HOLD` (spinner)
  - **Messaging functions** (match community-scripts pattern exactly):
    - `msg_info()` — yellow spinner + message (for in-progress operations)
    - `msg_ok()` — green checkmark + message (for success)
    - `msg_error()` — red cross + message (for errors), then `exit 1`
    - `msg_warn()` — yellow warning message (non-fatal)
  - **Validation functions** (each returns 0 on pass, exits with msg_error on fail):
    - `check_root()` — verify running as root (`[[ $EUID -eq 0 ]]`)
    - `check_proxmox()` — verify running on Proxmox host (`command -v pveversion`)
    - `check_internet()` — verify internet connectivity (`ping -c1 -W3 8.8.8.8`)
    - `check_storage_space()` — verify sufficient disk space on target storage pool (param: required_gb)
    - `check_port_available()` — verify port is not in use (param: port number)
    - `check_vmid_available()` — verify VMID is not taken (param: vmid)
    - `check_container_runtime()` — detect Docker/Podman or prompt to install
  - **Whiptail helper functions**:
    - `whiptail_menu()` — generic radiolist wrapper with cancel handling
    - `whiptail_input()` — generic inputbox wrapper with cancel handling and default value
    - `whiptail_yesno()` — generic yes/no dialog wrapper
    - `whiptail_msg()` — generic message box wrapper
    - All whiptail functions must handle ESC/Cancel (exit code 1 or 255) by calling `msg_warn "Operation cancelled by user."` and `exit 0`
  - **Utility functions**:
    - `next_vmid()` — find next available VMID (`pvesh get /cluster/resources --type vm --output-format json | jq ...` or fallback to `pvesh get /cluster/nextid`)
    - `detect_storage()` — list available Proxmox storage pools for whiptail selection
    - `load_env()` — source .env file if it exists, apply defaults for missing vars
    - `cleanup_on_error()` — trap handler to clean up partial LXC/VM on script failure
  - Start the file with `#!/usr/bin/env bash` and a header comment block (project name, purpose, 3 lines max)
  - `set -euo pipefail` at the top (after shebang)

  **Must NOT do**:
  - Don't create functions "for later" that aren't called by any task's scripts
  - Don't add more than 3 lines of header comments
  - Don't build a config file parser — `load_env()` just `source .env` and sets defaults with `${VAR:-default}`
  - Don't implement Podman-specific logic beyond detection — Docker path first

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Core infrastructure file, many functions, needs careful bash scripting and consistent patterns
  - **Skills**: []
    - No specialized skills needed — pure bash
  - **Skills Evaluated but Omitted**:
    - `playwright`: No browser interaction needed
    - `git-master`: No git operations in this task

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 3)
  - **Blocks**: Tasks 4, 5, 6, 7, 8, 9, 10
  - **Blocked By**: Task 1 (needs directory structure)

  **References**:

  **Pattern References**:
  - community-scripts/ProxmoxVE `misc/build.func` (https://github.com/community-scripts/ProxmoxVE/blob/main/misc/build.func) — `build_container()` function, msg_info/msg_ok/msg_error exact pattern, color codes, whiptail usage. This file is 5000+ lines — only replicate the PATTERNS, not the entire file.
  - community-scripts/ProxmoxVE `ct/` scripts — how they `source <(curl -fsSL .../misc/build.func)` to load shared functions

  **External References**:
  - Proxmox API: `pvesh get /cluster/nextid` — getting next available VMID
  - Proxmox API: `pvesh get /cluster/resources --type vm` — listing existing VMs/CTs
  - whiptail man page — `--radiolist`, `--inputbox`, `--yesno`, `--msgbox` usage

  **WHY Each Reference Matters**:
  - community-scripts `build.func` is the gold standard for Proxmox helper function libraries — following its patterns ensures consistency with what Proxmox users expect
  - pvesh API is the correct Proxmox-native way to query resources (not parsing config files)

  **Acceptance Criteria**:

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: File passes syntax and shellcheck
    Tool: Bash
    Preconditions: misc/build.func exists
    Steps:
      1. Run: bash -n misc/build.func
      2. Assert: exit code 0
      3. Run: shellcheck misc/build.func || true
      4. Assert: no errors (warnings acceptable)
    Expected Result: Clean syntax, no shellcheck errors
    Failure Indicators: Non-zero exit code from bash -n
    Evidence: .sisyphus/evidence/task-2-shellcheck.txt

  Scenario: All required functions are defined
    Tool: Bash
    Preconditions: misc/build.func exists
    Steps:
      1. Run: grep -c "^[a-z_]*() {" misc/build.func
      2. Assert: count >= 15 (all functions listed above)
      3. Run: grep "msg_info\|msg_ok\|msg_error\|check_root\|check_proxmox\|check_internet\|next_vmid\|detect_storage\|load_env\|cleanup_on_error\|whiptail_menu\|whiptail_input\|whiptail_yesno" misc/build.func
      4. Assert: all 13+ function names appear
    Expected Result: All required functions present
    Failure Indicators: Any function missing
    Evidence: .sisyphus/evidence/task-2-functions.txt

  Scenario: Color codes are defined
    Tool: Bash
    Preconditions: misc/build.func exists
    Steps:
      1. Run: grep "YW=\|GN=\|RD=\|BL=\|CL=\|CM=\|CROSS=" misc/build.func
      2. Assert: all 7 color variables defined
    Expected Result: All color codes present
    Failure Indicators: Missing color definitions
    Evidence: .sisyphus/evidence/task-2-colors.txt

  Scenario: set -euo pipefail is present
    Tool: Bash
    Preconditions: misc/build.func exists
    Steps:
      1. Run: head -5 misc/build.func
      2. Assert: contains "set -euo pipefail" within first 5 lines
    Expected Result: Fail-fast behavior enabled
    Failure Indicators: Missing set -euo pipefail
    Evidence: .sisyphus/evidence/task-2-pipefail.txt

  Scenario: Functions handle errors — msg_error exits
    Tool: Bash
    Preconditions: misc/build.func exists
    Steps:
      1. Run: grep -A2 "msg_error()" misc/build.func
      2. Assert: function body contains "exit" (1 or non-zero)
    Expected Result: msg_error causes script exit
    Failure Indicators: msg_error does not exit
    Evidence: .sisyphus/evidence/task-2-error-exit.txt
  ```

  **Commit**: YES
  - Message: `feat: add shared utility functions library`
  - Files: `misc/build.func`
  - Pre-commit: `bash -n misc/build.func`

- [x] 3. Vector Demo SQL Data — sql/vector-demo.sql

  **What to do**:
  - Create `sql/vector-demo.sql` — a self-contained SQL script that demonstrates Oracle 26ai vector search
  - **Scope**: SQL-only. No ML model. No external API. Just SQL-level vector operations.
  - Script structure:
    1. Create a demo table: `CREATE TABLE vector_demo (id NUMBER, title VARCHAR2(200), description VARCHAR2(4000), embedding VECTOR(384, FLOAT32))`
    2. Insert 10-15 sample rows with realistic titles/descriptions (e.g., tech articles, product descriptions) and pre-computed 384-dimensional embedding vectors (use placeholder float arrays that are syntactically valid)
    3. Create a vector index: `CREATE VECTOR INDEX idx_vector_demo ON vector_demo(embedding) ...`
    4. Include 3 example queries:
       - Query 1: Nearest neighbor search — `SELECT ... ORDER BY VECTOR_DISTANCE(embedding, :query_vector, COSINE) FETCH FIRST 5 ROWS ONLY`
       - Query 2: Filtered vector search — combine WHERE clause with vector distance
       - Query 3: Vector distance calculation — show similarity scores
    5. Each query should have a comment explaining what it does
  - Use `FREEPDB1` as the target PDB (Oracle Free container default)
  - Add a header comment: "Oracle 26ai Vector Search Demo — run with: sqlplus sys/password@localhost:1521/FREEPDB1 as sysdba @vector-demo.sql"

  **Must NOT do**:
  - Don't use real ML model embeddings — use syntactically valid placeholder vectors
  - Don't create more than 1 table
  - Don't include DROP TABLE (let the setup script handle cleanup)
  - Don't use PL/SQL procedures — keep it pure SQL for simplicity

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single SQL file with static data, no complex logic
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - None relevant for SQL file creation

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 2)
  - **Blocks**: Task 8
  - **Blocked By**: Task 1 (needs sql/ directory)

  **References**:

  **External References**:
  - Oracle 26ai Vector Search docs: https://docs.oracle.com/en/database/oracle/oracle-database/23/vecse/ — VECTOR data type, VECTOR_DISTANCE function, CREATE VECTOR INDEX syntax
  - Oracle AI Vector Search examples from GitHub — search `VECTOR_DISTANCE` + `COSINE` for real query patterns

  **WHY Each Reference Matters**:
  - Oracle 26ai vector syntax is new and specific — VECTOR(dimensions, type) and VECTOR_DISTANCE are Oracle-specific functions that must use exact syntax

  **Acceptance Criteria**:

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: SQL file is syntactically structured
    Tool: Bash
    Preconditions: sql/vector-demo.sql exists
    Steps:
      1. Run: wc -l sql/vector-demo.sql
      2. Assert: line count between 50-200 (reasonable size)
      3. Run: grep -c "CREATE TABLE" sql/vector-demo.sql
      4. Assert: exactly 1
      5. Run: grep -c "INSERT INTO" sql/vector-demo.sql
      6. Assert: between 10-15
      7. Run: grep -c "VECTOR_DISTANCE" sql/vector-demo.sql
      8. Assert: >= 3 (3 demo queries)
    Expected Result: Well-structured SQL with table, data, and queries
    Failure Indicators: Missing CREATE TABLE, too few inserts, missing queries
    Evidence: .sisyphus/evidence/task-3-sql-structure.txt

  Scenario: SQL has header comment with usage instructions
    Tool: Bash
    Preconditions: sql/vector-demo.sql exists
    Steps:
      1. Run: head -5 sql/vector-demo.sql
      2. Assert: contains "sqlplus" and "FREEPDB1" in comment
    Expected Result: Clear usage instructions in header
    Failure Indicators: Missing header or wrong PDB name
    Evidence: .sisyphus/evidence/task-3-sql-header.txt
  ```

  **Commit**: YES (groups with Task 8)
  - Message: `feat: add vector search demo with sample SQL`
  - Files: `sql/vector-demo.sql`
  - Pre-commit: `test -f sql/vector-demo.sql`

- [x] 4. LXC Creation Script — ct/oracle26ai.sh

  **What to do**:
  - Create `ct/oracle26ai.sh` — the main entry point for LXC-based Oracle 26ai deployment
  - Script flow (max 6 whiptail screens):
    1. Source `misc/build.func` (via curl from raw GitHub URL, with local fallback)
    2. Run validation: `check_root`, `check_proxmox`, `check_internet`
    3. **Screen 1**: Welcome message (whiptail_msg) — "Oracle AI Database 26ai - LXC Deployment"
    4. **Screen 2**: Oracle image selection (whiptail_menu) — Full vs Lite
    5. **Screen 3**: Resource configuration (whiptail_input x3) — CPU cores (default 4), RAM MB (default 8192), Disk GB (default 32)
    6. **Screen 4**: Network configuration (whiptail_menu) — DHCP or Static IP. If static: additional input for IP/CIDR, gateway, DNS
    7. **Screen 5**: Password input (whiptail_input) — Oracle SYS password (with default from .env)
    8. **Screen 6**: Confirmation summary (whiptail_yesno) — show all settings, confirm to proceed
    9. Load .env overrides if file exists (skip whiptail for pre-configured values)
    10. Auto-detect or create VMID via `next_vmid()`
    11. Download Debian 12 LXC template if not cached: `pveam download local debian-12-standard_12.7-1_amd64.tar.zst`
    12. Create LXC container: `pct create $VMID local:vztmpl/debian-12-standard... --hostname $HOSTNAME --cores $CORES --memory $MEMORY --rootfs $STORAGE:$DISK --features nesting=1,keyctl=1 --unprivileged 0 --net0 name=eth0,bridge=$BRIDGE,ip=$NETWORK --onboot 1`
    13. Configure LXC for Docker: add `lxc.mount.entry: tmpfs dev/shm tmpfs defaults,size=2g 0 0` to container config if not privileged
    14. Start container: `pct start $VMID`
    15. Wait for container network connectivity
    16. Execute install script inside container: `pct exec $VMID -- bash -c "$(cat install/oracle26ai-install.sh)"` OR push and execute
    17. Display completion summary: IP address, port 1521, connection string, next steps (module scripts)
    18. Register cleanup trap: if script fails mid-way, remove the partial container

  **Must NOT do**:
  - Don't exceed 6 whiptail screens (combine where possible)
  - Don't hardcode storage to "local-lvm" — use `detect_storage()` if .env doesn't specify
  - Don't skip the confirmation screen — user must see all settings before creation
  - Don't use unprivileged mode by default — privileged (`--unprivileged 0`) is more reliable for Docker-in-LXC

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Complex bash script with whiptail TUI, Proxmox API calls, LXC creation, error handling
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - `playwright`: No browser interaction

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 5, 6)
  - **Blocks**: Tasks 7, 8, 9, 10, 11
  - **Blocked By**: Tasks 1, 2 (needs directory + shared functions)

  **References**:

  **Pattern References**:
  - community-scripts/ProxmoxVE `ct/` scripts — how creation scripts structure their flow: source build.func, validate, prompt, create, install
  - community-scripts/ProxmoxVE `misc/build.func:build_container()` (line ~3466) — the canonical `pct create` command with all options
  - community-scripts/ProxmoxVE `.github/workflows/scripts/app-test/pr-create-lxc.sh` (line ~145) — `pct create` with template download and retry logic

  **External References**:
  - Proxmox `pct create` man page — all available options for LXC creation
  - Proxmox `pveam` — template download commands

  **WHY Each Reference Matters**:
  - `build_container()` from community-scripts shows the exact `pct create` flags needed, including nesting, keyctl, network string format
  - The CI test script shows template download + retry pattern which handles edge cases

  **Acceptance Criteria**:

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Script passes syntax and shellcheck
    Tool: Bash
    Preconditions: ct/oracle26ai.sh exists
    Steps:
      1. Run: bash -n ct/oracle26ai.sh
      2. Assert: exit code 0
      3. Run: shellcheck ct/oracle26ai.sh || true
      4. Assert: no errors (warnings acceptable)
    Expected Result: Clean syntax
    Failure Indicators: Syntax errors
    Evidence: .sisyphus/evidence/task-4-shellcheck.txt

  Scenario: Script sources build.func
    Tool: Bash
    Preconditions: ct/oracle26ai.sh exists
    Steps:
      1. Run: grep "source\|\\." ct/oracle26ai.sh | grep "build.func"
      2. Assert: at least one line sources misc/build.func
    Expected Result: Shared functions are loaded
    Failure Indicators: No source of build.func found
    Evidence: .sisyphus/evidence/task-4-source.txt

  Scenario: Script uses pct create with required flags
    Tool: Bash
    Preconditions: ct/oracle26ai.sh exists
    Steps:
      1. Run: grep "pct create" ct/oracle26ai.sh
      2. Assert: line contains "--features" and "nesting=1"
      3. Run: grep "nesting=1" ct/oracle26ai.sh
      4. Assert: present
      5. Run: grep "keyctl=1" ct/oracle26ai.sh
      6. Assert: present
    Expected Result: LXC created with Docker-compatible features
    Failure Indicators: Missing nesting or keyctl flags
    Evidence: .sisyphus/evidence/task-4-pct-flags.txt

  Scenario: Script has validation calls
    Tool: Bash
    Preconditions: ct/oracle26ai.sh exists
    Steps:
      1. Run: grep "check_root\|check_proxmox\|check_internet" ct/oracle26ai.sh
      2. Assert: all 3 validation functions called
    Expected Result: Pre-flight checks before creation
    Failure Indicators: Missing validation calls
    Evidence: .sisyphus/evidence/task-4-validation.txt

  Scenario: Whiptail cancel is handled — no partial state
    Tool: Bash
    Preconditions: ct/oracle26ai.sh exists
    Steps:
      1. Run: grep -c "Cancel\|cancel\|255\|exit 0" ct/oracle26ai.sh
      2. Assert: count >= 3 (each whiptail call handles cancel)
    Expected Result: Graceful exit on user cancel
    Failure Indicators: Unhandled whiptail exit codes
    Evidence: .sisyphus/evidence/task-4-cancel.txt
  ```

  **Commit**: YES
  - Message: `feat: add LXC creation script with whiptail TUI`
  - Files: `ct/oracle26ai.sh`
  - Pre-commit: `shellcheck ct/oracle26ai.sh`

- [x] 5. VM Creation Script — ct/oracle26ai-vm.sh

  **What to do**:
  - Create `ct/oracle26ai-vm.sh` — entry point for KVM VM-based Oracle 26ai deployment
  - Script flow (mirrors LXC script structure, same whiptail screens):
    1. Source `misc/build.func`
    2. Run validation: `check_root`, `check_proxmox`, `check_internet`
    3. Same 6 whiptail screens as Task 4 (image, resources, network, password, confirm)
    4. Resource defaults slightly higher for VM overhead: 4 CPU, 8192 MB RAM, 40GB disk
    5. Download cloud-init image: Debian 12 cloud image (`debian-12-genericcloud-amd64.qcow2`) — download if not cached
    6. Create VM: `qm create $VMID --name $HOSTNAME --cores $CORES --memory $MEMORY --scsihw virtio-scsi-pci --scsi0 $STORAGE:0,import-from=/path/to/image,size=${DISK}G --ide2 $STORAGE:cloudinit --boot order=scsi0 --serial0 socket --vga serial0 --net0 virtio,bridge=$BRIDGE`
    7. Configure cloud-init: `qm set $VMID --ciuser root --cipassword $ROOT_PASSWORD --ipconfig0 ip=$NETWORK,gw=$GATEWAY --nameserver $DNS`
    8. Resize disk: `qm disk resize $VMID scsi0 ${DISK}G`
    9. Start VM: `qm start $VMID`
    10. Wait for VM boot + cloud-init completion (check via `qm guest exec` or SSH)
    11. Copy and execute install script inside VM via `qm guest exec` or SSH
    12. Display completion summary with connection details

  **Must NOT do**:
  - Don't create a separate VM template — use cloud-init directly
  - Don't require manual ISO upload — download cloud image automatically
  - Don't exceed 6 whiptail screens

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Complex bash script with qm commands, cloud-init, VM creation
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - `playwright`: No browser interaction

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 4, 6)
  - **Blocks**: Task 11
  - **Blocked By**: Tasks 1, 2

  **References**:

  **Pattern References**:
  - community-scripts/ProxmoxVE `vm/` scripts — VM creation pattern using `qm create`
  - Task 4 (ct/oracle26ai.sh) — whiptail flow to mirror for consistency

  **External References**:
  - Proxmox `qm create` man page — VM creation options
  - Debian cloud images: https://cloud.debian.org/images/cloud/ — download URL for cloud-init images
  - Proxmox cloud-init docs — `qm set --ciuser`, `--ipconfig0` syntax

  **WHY Each Reference Matters**:
  - VM creation via `qm create` has different flag syntax than `pct create` — must use correct options
  - Cloud-init is the standard for automated VM provisioning without manual ISO interaction

  **Acceptance Criteria**:

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Script passes syntax and shellcheck
    Tool: Bash
    Preconditions: ct/oracle26ai-vm.sh exists
    Steps:
      1. Run: bash -n ct/oracle26ai-vm.sh
      2. Assert: exit code 0
      3. Run: shellcheck ct/oracle26ai-vm.sh || true
      4. Assert: no errors
    Expected Result: Clean syntax
    Failure Indicators: Syntax errors
    Evidence: .sisyphus/evidence/task-5-shellcheck.txt

  Scenario: Script uses qm create with required options
    Tool: Bash
    Preconditions: ct/oracle26ai-vm.sh exists
    Steps:
      1. Run: grep "qm create" ct/oracle26ai-vm.sh
      2. Assert: line exists
      3. Run: grep "cloudinit" ct/oracle26ai-vm.sh
      4. Assert: cloud-init configuration present
    Expected Result: VM created with cloud-init support
    Failure Indicators: Missing qm create or cloudinit
    Evidence: .sisyphus/evidence/task-5-qm-flags.txt

  Scenario: Script mirrors LXC script structure
    Tool: Bash
    Preconditions: ct/oracle26ai-vm.sh and ct/oracle26ai.sh exist
    Steps:
      1. Run: grep "source.*build.func" ct/oracle26ai-vm.sh
      2. Assert: sources same build.func
      3. Run: grep "check_root\|check_proxmox\|check_internet" ct/oracle26ai-vm.sh
      4. Assert: same validations as LXC script
    Expected Result: Consistent structure between LXC and VM scripts
    Failure Indicators: Different validation approach
    Evidence: .sisyphus/evidence/task-5-consistency.txt
  ```

  **Commit**: YES
  - Message: `feat: add VM creation script with whiptail TUI`
  - Files: `ct/oracle26ai-vm.sh`
  - Pre-commit: `shellcheck ct/oracle26ai-vm.sh`

- [x] 6. Oracle Install Script — install/oracle26ai-install.sh

  **What to do**:
  - Create `install/oracle26ai-install.sh` — runs INSIDE the LXC container or VM to install Docker and Oracle 26ai
  - This is the core script that both LXC and VM creation scripts call after container/VM creation
  - Script flow:
    1. Update package repos: `apt-get update`
    2. Install prerequisites: `apt-get install -y curl ca-certificates gnupg lsb-release`
    3. **Container runtime detection/install**:
       - Check if Docker is installed (`command -v docker`)
       - Check if Podman is installed (`command -v podman`)
       - If neither: install Docker CE (official Docker repo for Debian 12)
       - If both: use Docker (preferred)
       - Set `RUNTIME` variable to `docker` or `podman`
    4. **Oracle image pull** (SEPARATE from run — critical for UX):
       - `msg_info "Pulling Oracle 26ai image (~10GB for Full, ~2GB for Lite). This may take 10-30 minutes..."`
       - `$RUNTIME pull container-registry.oracle.com/database/free:${ORACLE_IMAGE_TAG}`
       - If pull fails with auth error: display message guiding user to accept terms at container-registry.oracle.com
       - If pull fails with other error: `msg_error` with clear diagnostics
    5. **Validate shm availability** (critical for Docker-in-LXC):
       - Check `/dev/shm` size: `df -h /dev/shm | awk 'NR==2{print $2}'`
       - If < 1GB: warn user, attempt to remount `mount -o remount,size=2g /dev/shm`
    6. **Start Oracle container**:
       ```
       $RUNTIME run -d \
         --name ${ORACLE_CONTAINER_NAME:-oracle-26ai} \
         -p ${ORACLE_LISTENER_PORT:-1521}:1521 \
         -e ORACLE_PWD=${ORACLE_PWD} \
         --shm-size=1g \
         -v oracle_data:/opt/oracle/oradata \
         --restart unless-stopped \
         container-registry.oracle.com/database/free:${ORACLE_IMAGE_TAG}
       ```
    7. **Health check loop** (critical — Oracle takes 3-8 min to init):
       - `msg_info "Waiting for Oracle Database to initialize (this takes 3-8 minutes)..."`
       - Loop: check `$RUNTIME logs $CONTAINER_NAME 2>&1 | grep -q "DATABASE IS READY TO USE!"`
       - Timeout: 600 seconds (10 min)
       - Show elapsed time every 30 seconds: `msg_info "Still initializing... (${elapsed}s elapsed)"`
       - On timeout: `msg_error "Oracle failed to start within 600s. Check logs: $RUNTIME logs $CONTAINER_NAME"`
    8. **Verify connectivity**:
       - Install sqlplus or use docker exec: `$RUNTIME exec $CONTAINER_NAME bash -c "echo 'SELECT 1 FROM dual;' | sqlplus -S sys/${ORACLE_PWD}@localhost:1521/FREEPDB1 as sysdba"`
       - Assert output contains `1`
    9. **Display connection info**:
       ```
       msg_ok "Oracle AI Database 26ai is ready!"
       echo "  Connection string: localhost:1521/FREEPDB1"
       echo "  SYS password: (as configured)"
       echo "  Container name: $CONTAINER_NAME"
       echo "  Logs: $RUNTIME logs $CONTAINER_NAME"
       ```

  **Must NOT do**:
  - Don't embed `docker pull` inside `docker run` — pull separately for progress feedback
  - Don't skip the health check — Oracle WILL fail if accessed before ready
  - Don't hardcode image tag — use variable from .env or parameter
  - Don't implement Podman-specific workarounds beyond basic compatibility — flag issues and document

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Most complex script — Docker install, image pull with error handling, Oracle health check loop, shm validation, connectivity verification. Critical path component.
  - **Skills**: []
  - **Skills Evaluated but Omitted**:
    - `playwright`: No browser interaction

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 4, 5)
  - **Blocks**: Tasks 7, 8, 9, 10, 11
  - **Blocked By**: Tasks 1, 2

  **References**:

  **Pattern References**:
  - shakiyam/Oracle-AI-Database-26ai-Free-on-Docker `run.sh` — Oracle container run command with health check loop pattern
  - community-scripts/ProxmoxVE `install/*.sh` — install script conventions (apt-get patterns, msg_info/ok usage)
  - GitHub code search results: `container-registry.oracle.com/database/free` — 10+ repos showing Docker run patterns, all use `-e ORACLE_PWD`, `--shm-size=1g`
  - racket/db `docker-util.sh` — `start_oracle()` function with `--shm-size=1g` and health check

  **External References**:
  - Docker CE install for Debian: https://docs.docker.com/engine/install/debian/
  - Oracle Container Registry: container-registry.oracle.com — free image acceptance terms
  - Oracle Free container docs: startup behavior, env vars, PDB names

  **WHY Each Reference Matters**:
  - shakiyam's health check pattern (`until logs | grep "DATABASE IS READY"`) is the proven Oracle startup detection method
  - Docker install for Debian has specific repo setup steps that must be followed exactly
  - The `--shm-size=1g` flag is REQUIRED — without it Oracle crashes silently

  **Acceptance Criteria**:

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Script passes syntax and shellcheck
    Tool: Bash
    Preconditions: install/oracle26ai-install.sh exists
    Steps:
      1. Run: bash -n install/oracle26ai-install.sh
      2. Assert: exit code 0
      3. Run: shellcheck install/oracle26ai-install.sh || true
      4. Assert: no errors
    Expected Result: Clean syntax
    Failure Indicators: Syntax errors
    Evidence: .sisyphus/evidence/task-6-shellcheck.txt

  Scenario: Script separates docker pull from docker run
    Tool: Bash
    Preconditions: install/oracle26ai-install.sh exists
    Steps:
      1. Run: grep -n "pull\|run" install/oracle26ai-install.sh | grep -i "container-registry\|RUNTIME\|docker\|podman"
      2. Assert: "pull" command appears BEFORE "run" command (by line number)
    Expected Result: Image pulled separately for progress visibility
    Failure Indicators: No separate pull command, or pull after run
    Evidence: .sisyphus/evidence/task-6-pull-order.txt

  Scenario: Health check loop exists with timeout
    Tool: Bash
    Preconditions: install/oracle26ai-install.sh exists
    Steps:
      1. Run: grep "DATABASE IS READY TO USE" install/oracle26ai-install.sh
      2. Assert: health check string present
      3. Run: grep "600\|timeout\|TIMEOUT" install/oracle26ai-install.sh
      4. Assert: timeout value present
    Expected Result: Health check with 600s timeout
    Failure Indicators: Missing health check or timeout
    Evidence: .sisyphus/evidence/task-6-healthcheck.txt

  Scenario: shm validation present
    Tool: Bash
    Preconditions: install/oracle26ai-install.sh exists
    Steps:
      1. Run: grep "shm\|/dev/shm" install/oracle26ai-install.sh
      2. Assert: shm check/mount logic present
    Expected Result: Shared memory validated before Oracle start
    Failure Indicators: No shm handling
    Evidence: .sisyphus/evidence/task-6-shm.txt

  Scenario: No hardcoded passwords
    Tool: Bash
    Preconditions: install/oracle26ai-install.sh exists
    Steps:
      1. Run: grep "ORACLE_PWD=" install/oracle26ai-install.sh | grep -v '${' | grep -v 'ORACLE_PWD=$' | grep -v '#'
      2. Assert: no matches (all password refs use variables)
    Expected Result: Passwords always from variables
    Failure Indicators: Hardcoded password found
    Evidence: .sisyphus/evidence/task-6-no-hardcoded-pw.txt
  ```

  **Commit**: YES
  - Message: `feat: add Oracle 26ai install script with health checks`
  - Files: `install/oracle26ai-install.sh`
  - Pre-commit: `shellcheck install/oracle26ai-install.sh`

- [x] 7. APEX + ORDS Module — scripts/setup-apex-ords.sh

  **What to do**:
  - Create `scripts/setup-apex-ords.sh` — optional module to install Oracle APEX and ORDS on an existing Oracle 26ai container
  - Runs on the Proxmox host, executes commands inside the LXC/VM
  - Script flow:
    1. Source `misc/build.func`
    2. Detect running Oracle container: `$RUNTIME ps --filter name=oracle-26ai --format '{{.Names}}'`
    3. Verify Oracle DB is healthy (check for `"DATABASE IS READY TO USE!"` in logs)
    4. **Install ORDS inside the container**:
       - Download ORDS: `$RUNTIME exec $CONTAINER bash -c "curl -fsSL https://download.oracle.com/otn_software/java/ords/ords-latest.zip -o /tmp/ords.zip"`
       - Or use the Oracle Free container's built-in ORDS if available (check `$RUNTIME exec $CONTAINER ls /opt/oracle/ords/`)
       - Install Java (OpenJDK 17): `$RUNTIME exec $CONTAINER bash -c "apt-get install -y openjdk-17-jre-headless"` or use Oracle's bundled JDK
       - Unzip and configure ORDS
       - Configure ORDS connection to FREEPDB1
       - Start ORDS: `$RUNTIME exec -d $CONTAINER /opt/oracle/ords/bin/ords serve --port 8080`
    5. **Enable APEX** (bundled with Oracle Free):
       - Run APEX installation SQL if not already installed
       - Configure APEX workspace and admin account
    6. Wait for ORDS to start (health check on port 8080)
    7. Display access info: `http://<CONTAINER_IP>:8080/ords/`
    8. Forward port if needed: `$RUNTIME port` or inform user about port mapping

  **Must NOT do**:
  - Don't build a full ORDS standalone deployment — keep it simple inside the existing Oracle container
  - Don't create an ORDS Docker sidecar — too complex for v1
  - Don't auto-start ORDS on container restart (document manual restart in README instead)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Multi-step install process with Oracle-specific configuration, ORDS setup
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 8, 9, 10)
  - **Blocks**: Task 10, 11
  - **Blocked By**: Tasks 4, 6

  **References**:

  **Pattern References**:
  - jk-kashe/gcp-database-demos `startup.sh.tpl` — ORDS install inside Oracle Free container: download, unzip, configure, start
  - shakiyam/Oracle-AI-Database-26ai-Free-on-Docker — container management patterns

  **External References**:
  - Oracle ORDS docs: https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/
  - Oracle APEX installation guide for Oracle Free
  - ORDS download: https://www.oracle.com/database/technologies/appdev/rest.html

  **WHY Each Reference Matters**:
  - jk-kashe's startup script shows a proven ORDS installation sequence inside an Oracle Free container — copy this exact pattern
  - ORDS + APEX inside Oracle Free requires specific SQL grants and configuration that differ from enterprise installs

  **Acceptance Criteria**:

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Script passes syntax and shellcheck
    Tool: Bash
    Preconditions: scripts/setup-apex-ords.sh exists
    Steps:
      1. Run: bash -n scripts/setup-apex-ords.sh
      2. Assert: exit code 0
      3. Run: shellcheck scripts/setup-apex-ords.sh || true
      4. Assert: no errors
    Expected Result: Clean syntax
    Evidence: .sisyphus/evidence/task-7-shellcheck.txt

  Scenario: Script checks for running Oracle container first
    Tool: Bash
    Preconditions: scripts/setup-apex-ords.sh exists
    Steps:
      1. Run: grep "ps\|inspect\|CONTAINER" scripts/setup-apex-ords.sh | head -5
      2. Assert: container detection logic present
    Expected Result: Validates Oracle is running before ORDS install
    Failure Indicators: No container detection
    Evidence: .sisyphus/evidence/task-7-container-check.txt

  Scenario: Script configures ORDS on port 8080
    Tool: Bash
    Preconditions: scripts/setup-apex-ords.sh exists
    Steps:
      1. Run: grep "8080" scripts/setup-apex-ords.sh
      2. Assert: port 8080 referenced
    Expected Result: ORDS configured on expected port
    Evidence: .sisyphus/evidence/task-7-ords-port.txt
  ```

  **Commit**: YES
  - Message: `feat: add APEX/ORDS setup module`
  - Files: `scripts/setup-apex-ords.sh`
  - Pre-commit: `shellcheck scripts/setup-apex-ords.sh`

- [x] 8. Vector Search Demo Runner — scripts/setup-vector-demo.sh

  **What to do**:
  - Create `scripts/setup-vector-demo.sh` — loads and runs the vector search demo from `sql/vector-demo.sql`
  - Script flow:
    1. Source `misc/build.func`
    2. Detect running Oracle container
    3. Copy `sql/vector-demo.sql` into the container: `$RUNTIME cp sql/vector-demo.sql $CONTAINER:/tmp/`
    4. Execute SQL: `$RUNTIME exec $CONTAINER bash -c "echo '@/tmp/vector-demo.sql' | sqlplus -S sys/${ORACLE_PWD}@localhost:1521/FREEPDB1 as sysdba"`
    5. Verify: query `SELECT COUNT(*) FROM vector_demo` returns > 0
    6. Display results of 3 demo queries with formatted output
    7. `msg_ok "Vector search demo loaded! Connect to FREEPDB1 and explore the vector_demo table."`

  **Must NOT do**:
  - Don't install ML models or call external APIs
  - Don't create additional tables beyond vector_demo

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Simple wrapper script — copy SQL file into container, execute, verify
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 7, 9, 10)
  - **Blocks**: Task 11
  - **Blocked By**: Tasks 3, 4, 6

  **References**:

  **Pattern References**:
  - Task 3 (sql/vector-demo.sql) — the SQL file this script executes
  - Task 6 (install/oracle26ai-install.sh) — sqlplus exec pattern via docker exec

  **Acceptance Criteria**:

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Script passes syntax and shellcheck
    Tool: Bash
    Preconditions: scripts/setup-vector-demo.sh exists
    Steps:
      1. Run: bash -n scripts/setup-vector-demo.sh && shellcheck scripts/setup-vector-demo.sh || true
      2. Assert: no errors
    Expected Result: Clean syntax
    Evidence: .sisyphus/evidence/task-8-shellcheck.txt

  Scenario: Script references vector-demo.sql
    Tool: Bash
    Preconditions: scripts/setup-vector-demo.sh exists
    Steps:
      1. Run: grep "vector-demo.sql" scripts/setup-vector-demo.sh
      2. Assert: SQL file referenced
    Expected Result: Script uses the demo SQL file
    Evidence: .sisyphus/evidence/task-8-sql-ref.txt
  ```

  **Commit**: YES (groups with Task 3)
  - Message: `feat: add vector search demo with sample SQL`
  - Files: `scripts/setup-vector-demo.sh, sql/vector-demo.sql`
  - Pre-commit: `shellcheck scripts/setup-vector-demo.sh`

- [x] 9. Backup and Restore Scripts — scripts/backup.sh, scripts/restore.sh

  **What to do**:
  - Create `scripts/backup.sh` — backs up Oracle data from the container
  - Create `scripts/restore.sh` — restores Oracle data from a backup file
  - **backup.sh** flow:
    1. Source `misc/build.func`
    2. Detect running Oracle container
    3. Create backup directory: `/var/backups/oracle-26ai/` (or configurable via .env)
    4. Generate timestamped backup filename: `oracle26ai_$(date +%Y%m%d_%H%M%S).dmp`
    5. Run Data Pump export inside container: `$RUNTIME exec $CONTAINER bash -c "expdp sys/${ORACLE_PWD}@localhost:1521/FREEPDB1 as sysdba directory=DATA_PUMP_DIR dumpfile=backup.dmp logfile=backup.log full=y"`
    6. Copy dump file out of container: `$RUNTIME cp $CONTAINER:/opt/oracle/admin/FREE/dpdump/backup.dmp /var/backups/oracle-26ai/$BACKUP_FILE`
    7. `msg_ok "Backup saved to /var/backups/oracle-26ai/$BACKUP_FILE"`
  - **restore.sh** flow:
    1. Accept backup file path as argument: `$1`
    2. Validate file exists
    3. Copy into container
    4. Run Data Pump import: `impdp sys/${ORACLE_PWD}@... directory=DATA_PUMP_DIR dumpfile=backup.dmp logfile=restore.log full=y`
    5. Verify: run a basic query to confirm data is present

  **Must NOT do**:
  - Don't implement backup scheduling or cron jobs
  - Don't implement backup rotation or cleanup of old backups
  - Don't implement incremental backups — full dump only

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Straightforward expdp/impdp wrapper scripts
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 7, 8, 10)
  - **Blocks**: Task 11
  - **Blocked By**: Tasks 4, 6

  **References**:

  **External References**:
  - Oracle Data Pump (expdp/impdp) documentation for Oracle Free
  - Oracle Free container data directory: `/opt/oracle/admin/FREE/dpdump/`

  **Acceptance Criteria**:

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Both scripts pass syntax and shellcheck
    Tool: Bash
    Steps:
      1. Run: bash -n scripts/backup.sh && bash -n scripts/restore.sh
      2. Run: shellcheck scripts/backup.sh scripts/restore.sh || true
      3. Assert: no errors
    Expected Result: Both scripts clean
    Evidence: .sisyphus/evidence/task-9-shellcheck.txt

  Scenario: backup.sh creates timestamped file
    Tool: Bash
    Steps:
      1. Run: grep "date\|timestamp\|%Y%m%d" scripts/backup.sh
      2. Assert: timestamped filename pattern present
    Expected Result: Backups are timestamped
    Evidence: .sisyphus/evidence/task-9-timestamp.txt

  Scenario: restore.sh accepts file argument
    Tool: Bash
    Steps:
      1. Run: grep '$1\|"$1"\|${1}' scripts/restore.sh
      2. Assert: first argument used as backup file path
    Expected Result: Restore takes backup file as input
    Evidence: .sisyphus/evidence/task-9-restore-arg.txt

  Scenario: No backup scheduler or rotation
    Tool: Bash
    Steps:
      1. Run: grep -i "cron\|schedule\|rotate\|retention" scripts/backup.sh scripts/restore.sh
      2. Assert: no matches
    Expected Result: Simple single-use scripts, no scheduling
    Evidence: .sisyphus/evidence/task-9-no-scheduler.txt
  ```

  **Commit**: YES
  - Message: `feat: add backup and restore scripts`
  - Files: `scripts/backup.sh, scripts/restore.sh`
  - Pre-commit: `shellcheck scripts/backup.sh scripts/restore.sh`

- [x] 10. SSL/TLS Setup — scripts/setup-ssl.sh

  **What to do**:
  - Create `scripts/setup-ssl.sh` — generates self-signed certificates and configures ORDS for HTTPS
  - Script flow:
    1. Source `misc/build.func`
    2. Detect running Oracle container and verify ORDS is running (depends on Task 7)
    3. Generate self-signed certificate:
       ```
       openssl req -x509 -nodes -days 365 \
         -newkey rsa:2048 \
         -keyout /tmp/oracle-ssl.key \
         -out /tmp/oracle-ssl.crt \
         -subj "/CN=${CT_HOSTNAME}/O=Oracle26ai/C=US"
       ```
    4. Copy certs into container
    5. Configure ORDS standalone to use HTTPS on port 8443:
       - Update ORDS standalone config for SSL
       - Restart ORDS with `--secure` flag
    6. Verify: `curl -sk https://localhost:8443/ords/` returns 200
    7. `msg_ok "SSL/TLS configured! Access ORDS at https://<IP>:8443/ords/"`

  **Must NOT do**:
  - NO Let's Encrypt / ACME integration
  - NO cert-manager or auto-renewal
  - NO mutual TLS or client certificates
  - Self-signed only — document this limitation in output

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Standard openssl + ORDS config, well-documented patterns
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 7, 8, 9)
  - **Blocks**: Task 11
  - **Blocked By**: Tasks 4, 6, 7 (needs ORDS running)

  **References**:

  **External References**:
  - Oracle ORDS standalone HTTPS configuration docs
  - openssl self-signed cert generation — standard pattern

  **Acceptance Criteria**:

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Script passes syntax and shellcheck
    Tool: Bash
    Steps:
      1. Run: bash -n scripts/setup-ssl.sh && shellcheck scripts/setup-ssl.sh || true
      2. Assert: no errors
    Expected Result: Clean syntax
    Evidence: .sisyphus/evidence/task-10-shellcheck.txt

  Scenario: Uses self-signed certs only
    Tool: Bash
    Steps:
      1. Run: grep "openssl req.*-x509" scripts/setup-ssl.sh
      2. Assert: self-signed cert generation present
      3. Run: grep -i "letsencrypt\|certbot\|acme" scripts/setup-ssl.sh
      4. Assert: no matches (no ACME)
    Expected Result: Self-signed only, no Let's Encrypt
    Evidence: .sisyphus/evidence/task-10-self-signed.txt

  Scenario: Configures port 8443
    Tool: Bash
    Steps:
      1. Run: grep "8443" scripts/setup-ssl.sh
      2. Assert: HTTPS port referenced
    Expected Result: SSL on port 8443
    Evidence: .sisyphus/evidence/task-10-port.txt
  ```

  **Commit**: YES
  - Message: `feat: add SSL/TLS self-signed cert setup`
  - Files: `scripts/setup-ssl.sh`
  - Pre-commit: `shellcheck scripts/setup-ssl.sh`

- [ ] 11. README Finalization — README.md

  **What to do**:
  - Replace the skeleton README from Task 1 with complete documentation
  - **Sections** (exactly these, in this order):
    1. **Header**: Project name, one-line description, badges (MIT license, Oracle 26ai, Proxmox)
    2. **Quick Start**: One-liner install commands for both LXC and VM paths
    3. **Features**: Bullet list of what's included (basic DB, APEX, vector demo, backup, SSL)
    4. **Prerequisites**: Proxmox VE 8.x+, internet connection, 4+ CPU / 8+ GB RAM / 32+ GB disk
    5. **Architecture**: ASCII diagram showing Proxmox Host → LXC/VM → Docker → Oracle 26ai container
    6. **Configuration**: .env.sample variable reference table
    7. **Module Scripts**: How to run each optional module (APEX, vector demo, backup, SSL)
    8. **Connection Guide**: How to connect from SQL Developer, sqlplus, JDBC, Python cx_Oracle
    9. **Troubleshooting**: Top 5 issues (Docker won't start in LXC, Oracle init timeout, shm too small, port conflict, image pull auth)
    10. **Contributing**: How to contribute, code style (shellcheck, set -euo pipefail)
    11. **License**: MIT
  - Keep it concise — max 300 lines total
  - Include the one-liner install prominently at the top

  **Must NOT do**:
  - Don't exceed 300 lines — concise over comprehensive
  - Don't include screenshots (ASCII diagrams instead)
  - Don't repeat content from .env.sample — reference it

  **Recommended Agent Profile**:
  - **Category**: `writing`
    - Reason: Documentation writing — needs clear, organized prose
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with Task 12)
  - **Blocks**: F1-F4
  - **Blocked By**: Tasks 4-10 (needs all scripts done to reference them accurately)

  **References**:

  **Pattern References**:
  - All scripts from Tasks 1-10 — accurate file names, paths, and commands
  - .env.sample from Task 1 — variable reference

  **External References**:
  - community-scripts/ProxmoxVE README — how popular Proxmox projects structure their docs
  - shakiyam/Oracle-AI-Database-26ai-Free-on-Docker README — Oracle-specific usage docs

  **Acceptance Criteria**:

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: README has all required sections
    Tool: Bash
    Steps:
      1. Run: grep -c "^##" README.md
      2. Assert: count >= 10
      3. Run: grep "Quick Start\|Prerequisites\|Architecture\|Configuration\|Troubleshooting\|Contributing\|License" README.md
      4. Assert: all section headers present
    Expected Result: All 11 sections present
    Evidence: .sisyphus/evidence/task-11-sections.txt

  Scenario: One-liner install command is present
    Tool: Bash
    Steps:
      1. Run: grep "bash.*curl.*oracle26ai" README.md
      2. Assert: one-liner install command present for at least LXC path
    Expected Result: Quick install command in README
    Evidence: .sisyphus/evidence/task-11-oneliner.txt

  Scenario: README is under 300 lines
    Tool: Bash
    Steps:
      1. Run: wc -l README.md | awk '{print $1}'
      2. Assert: line count <= 300
    Expected Result: Concise documentation
    Evidence: .sisyphus/evidence/task-11-length.txt
  ```

  **Commit**: YES
  - Message: `docs: finalize README with install guide and troubleshooting`
  - Files: `README.md`
  - Pre-commit: `test -f README.md`

- [ ] 12. Uninstall/Cleanup Script — scripts/uninstall.sh

  **What to do**:
  - Create `scripts/uninstall.sh` — removes Oracle 26ai deployment from Proxmox
  - Script flow:
    1. Source `misc/build.func`
    2. `check_root`, `check_proxmox`
    3. Prompt user: "This will destroy the Oracle 26ai container/VM and all data. Continue?" (whiptail_yesno)
    4. Detect deployment type: check if VMID is LXC (`pct status`) or VM (`qm status`)
    5. Stop Oracle container inside: `pct exec $VMID -- $RUNTIME stop $CONTAINER_NAME` or `qm guest exec`
    6. Remove Docker volumes: `pct exec $VMID -- $RUNTIME volume rm oracle_data`
    7. Stop and destroy LXC/VM: `pct stop $VMID && pct destroy $VMID` or `qm stop $VMID && qm destroy $VMID`
    8. Clean up backup files if present (prompt first)
    9. `msg_ok "Oracle 26ai deployment removed."`

  **Must NOT do**:
  - Don't delete without confirmation — ALWAYS prompt
  - Don't remove files outside the Oracle deployment (no system-wide Docker uninstall)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Simple teardown script with confirmation prompt
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with Task 11)
  - **Blocks**: F1-F4
  - **Blocked By**: Tasks 4, 6

  **References**:

  **Pattern References**:
  - Task 4 (ct/oracle26ai.sh) — VMID and container name conventions to match
  - community-scripts/ProxmoxVE — how uninstall/removal is typically handled

  **Acceptance Criteria**:

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Script passes syntax and shellcheck
    Tool: Bash
    Steps:
      1. Run: bash -n scripts/uninstall.sh && shellcheck scripts/uninstall.sh || true
      2. Assert: no errors
    Expected Result: Clean syntax
    Evidence: .sisyphus/evidence/task-12-shellcheck.txt

  Scenario: Script requires confirmation before destruction
    Tool: Bash
    Steps:
      1. Run: grep -i "confirm\|yesno\|destroy\|warning" scripts/uninstall.sh
      2. Assert: confirmation prompt exists before destructive operations
    Expected Result: No silent destruction
    Evidence: .sisyphus/evidence/task-12-confirm.txt
  ```

  **Commit**: YES
  - Message: `feat: add uninstall/cleanup script`
  - Files: `scripts/uninstall.sh`
  - Pre-commit: `shellcheck scripts/uninstall.sh`

---

## Final Verification Wave (MANDATORY — after ALL implementation tasks)

> 4 review agents run in PARALLEL. ALL must APPROVE. Rejection → fix → re-run.

- [ ] F1. **Plan Compliance Audit** — `oracle`
  Read the plan end-to-end. For each "Must Have": verify implementation exists (read file, grep for pattern). For each "Must NOT Have": search codebase for forbidden patterns — reject with file:line if found. Check evidence files exist in .sisyphus/evidence/. Compare deliverables against plan.
  Output: `Must Have [N/N] | Must NOT Have [N/N] | Tasks [N/N] | VERDICT: APPROVE/REJECT`

- [ ] F2. **Code Quality Review** — `unspecified-high`
  Run `shellcheck` on ALL .sh scripts. Run `bash -n` on ALL .sh scripts. Review all scripts for: hardcoded passwords, missing error handling, inconsistent function usage (msg_info/msg_ok/msg_error), missing `set -euo pipefail`, unused variables, unquoted variables. Check for AI slop: excessive comments, over-abstraction, generic variable names.
  Output: `ShellCheck [PASS/FAIL per script] | Syntax [PASS/FAIL] | Quality [N clean/N issues] | VERDICT`

- [ ] F3. **Real Manual QA** — `unspecified-high`
  Execute EVERY QA scenario from EVERY task — follow exact steps, capture evidence. Test cross-script integration (does install script work after LXC creation? do modules work after base install?). Test edge cases: whiptail cancel, invalid input, missing dependencies. Save to `.sisyphus/evidence/final-qa/`.
  Output: `Scenarios [N/N pass] | Integration [N/N] | Edge Cases [N tested] | VERDICT`

- [ ] F4. **Scope Fidelity Check** — `deep`
  For each task: read "What to do", read actual file. Verify 1:1 — everything in spec was built (no missing), nothing beyond spec was built (no creep). Check "Must NOT Have" compliance. Detect unaccounted files. Flag any config parser, ACME integration, backup scheduler, or excessive whiptail screens.
  Output: `Tasks [N/N compliant] | Unaccounted [CLEAN/N files] | Guardrails [N/N respected] | VERDICT`

---

## Commit Strategy

| Order | Message | Files | Pre-commit |
|-------|---------|-------|------------|
| 1 | `feat: init repo with README skeleton, LICENSE, directory structure` | README.md, LICENSE, .gitignore, .env.sample, directory structure | — |
| 2 | `feat: add shared utility functions library` | misc/build.func | `bash -n misc/build.func` |
| 3 | `feat: add LXC creation script with whiptail TUI` | ct/oracle26ai.sh | `shellcheck ct/oracle26ai.sh` |
| 4 | `feat: add VM creation script with whiptail TUI` | ct/oracle26ai-vm.sh | `shellcheck ct/oracle26ai-vm.sh` |
| 5 | `feat: add Oracle 26ai install script with health checks` | install/oracle26ai-install.sh | `shellcheck install/oracle26ai-install.sh` |
| 6 | `feat: add APEX/ORDS setup module` | scripts/setup-apex-ords.sh | `shellcheck scripts/setup-apex-ords.sh` |
| 7 | `feat: add vector search demo with sample SQL` | scripts/setup-vector-demo.sh, sql/vector-demo.sql | `shellcheck scripts/setup-vector-demo.sh` |
| 8 | `feat: add backup and restore scripts` | scripts/backup.sh, scripts/restore.sh | `shellcheck scripts/backup.sh scripts/restore.sh` |
| 9 | `feat: add SSL/TLS self-signed cert setup` | scripts/setup-ssl.sh | `shellcheck scripts/setup-ssl.sh` |
| 10 | `feat: add uninstall/cleanup script` | scripts/uninstall.sh | `shellcheck scripts/uninstall.sh` |
| 11 | `docs: finalize README with install guide and troubleshooting` | README.md | — |

---

## Success Criteria

### Verification Commands
```bash
# All scripts pass syntax check
for f in ct/*.sh install/*.sh scripts/*.sh misc/build.func; do bash -n "$f"; done
# Expected: no output (all pass)

# All scripts pass shellcheck
shellcheck ct/*.sh install/*.sh scripts/*.sh
# Expected: no errors

# File structure matches spec
find . -type f -not -path '*/.git/*' -not -path '*/.sisyphus/*' | sort
# Expected: matches deliverables list above

# README has required sections
grep -c "^##" README.md
# Expected: >= 5 sections

# No hardcoded passwords
grep -rn "ORACLE_PWD=.*[^$]" ct/ install/ scripts/ misc/ | grep -v '.env.sample' | grep -v 'example\|demo\|sample\|placeholder'
# Expected: no matches

# LICENSE is MIT
head -1 LICENSE
# Expected: "MIT License"
```

### Final Checklist
- [ ] All "Must Have" items present and verified
- [ ] All "Must NOT Have" items confirmed absent
- [ ] All 12 scripts pass shellcheck + bash -n
- [ ] README contains: one-liner install, architecture, connection guide, troubleshooting, contributing
- [ ] MIT LICENSE present
- [ ] .env.sample documents all configurable variables
- [ ] Every whiptail call handles cancel/ESC gracefully
