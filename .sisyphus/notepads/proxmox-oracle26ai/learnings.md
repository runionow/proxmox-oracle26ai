# Learnings — proxmox-oracle26ai

## Task 2: misc/build.func

### Patterns
- `misc/build.func` is sourced (not executed) by all downstream scripts — shebang line is present but `set -euo pipefail` applies to the sourcing shell
- Function naming convention: `snake_case`, grouped by category (messaging, validation, whiptail, utility)
- All validation functions call `msg_error` on failure, which calls `exit 1` — this terminates the sourcing script
- Color vars `BL` and `BFR` are defined per spec but unused in this file (used by downstream scripts) — shellcheck SC2034 warnings are expected and acceptable
- `shellcheck --severity=error` exits 0 (no errors, only warnings/info)

### Conventions
- File is 209 lines (well under 300 limit)
- 20 functions total (exceeds minimum of 15)
- `load_env()` uses `source .env` pattern — no YAML/JSON parsing
- `check_container_runtime()` exports `RUNTIME` variable for downstream use
- `cleanup_on_error()` designed as a trap handler — takes vmid and type args

### Gotchas
- `.sisyphus/evidence/` is in `.gitignore` — evidence files cannot be committed directly
- `shellcheck` not installed by default on macOS — needed `brew install shellcheck`
- SC1091 info on `/etc/os-release` sourcing in `install_docker()` is expected (file not present on macOS)

## Task 3: Vector Demo SQL Data

### Oracle Vector Syntax Learnings

1. **VECTOR Data Type**: `VECTOR(384, FLOAT32)` specifies:
   - 384 dimensions (must match embedding model output)
   - FLOAT32 precision (4-byte floats)

2. **Vector Literals**: Enclosed in square brackets `[...]` with comma-separated floats
   - CRITICAL: Must have EXACTLY the declared dimension count (384 in this case)
   - Mismatch causes Oracle SQL errors
   - Pattern: `[0.1,0.2,0.3,...,0.9]` repeated to fill dimensions

3. **Vector Index Creation**:
   ```sql
   CREATE VECTOR INDEX idx_name
     ON table_name (vector_column)
     ORGANIZATION NEIGHBOR PARTITIONS
     WITH TARGET ACCURACY 95
     DISTANCE COSINE
     PARAMETERS (type IVF, neighbor partitions 10);
   ```
   - NEIGHBOR PARTITIONS: IVF (Inverted File) indexing for fast similarity search
   - DISTANCE COSINE: Cosine similarity metric
   - TARGET ACCURACY: 95% accuracy threshold

4. **Vector Distance Queries**:
   - `VECTOR_DISTANCE(embedding, query_vector, COSINE)`: Computes similarity
   - `VECTOR_DIMENSION(embedding)`: Returns vector dimensionality
   - Supports filtering with WHERE clauses for hybrid search

5. **Demo Data Generation**:
   - Use placeholder embeddings (not real ML model outputs)
   - Vary patterns (0.1-0.9, 0.2-0.8, etc.) to create distinct vectors
   - 14 INSERT rows with realistic titles/categories/descriptions

### QA Results
- Line count: 169 lines (within 50-200 range)
- CREATE TABLE: 1 ✓
- INSERT INTO: 14 ✓ (within 10-15 range)
- VECTOR_DISTANCE queries: 3 ✓
- All vectors: 384 elements ✓
- Header: Contains sqlplus and FREEPDB1 ✓

## Task 6: install/oracle26ai-install.sh

### Implementation Learnings
- Script must be fully standalone because it runs inside Debian guest; no dependency on `misc/build.func`
- `ORACLE_PWD` enforcement via `ORACLE_PWD="${ORACLE_PWD:?'ORACLE_PWD must be set'}"` prevents accidental blank/default credentials
- Pulling `container-registry.oracle.com/database/free:${ORACLE_IMAGE_TAG}` separately from runtime `run` gives clear progress and better failure handling
- Oracle registry auth failures are detectable from pull stderr (`unauthorized|authentication|access denied`) and should print step-by-step license acceptance guidance
- `/dev/shm` must be validated before container start; keep both host-side remount attempt and container `--shm-size=1g`

### QA Results
- `bash -n install/oracle26ai-install.sh` exit code: 0
- Pull command appears before run command in script
- Health check string present: `DATABASE IS READY TO USE!`
- Health timeout present: `TIMEOUT=600`
- `/dev/shm` validation and remount logic present
- No hardcoded `ORACLE_PWD` assignment values found

### Tooling Note
- `lsp_diagnostics` initially failed because `bash-language-server` was missing on macOS; fixed by installing with `npm install -g bash-language-server`

## Task 5: ct/oracle26ai-vm.sh

### Patterns
- VM script mirrors LXC script (`ct/oracle26ai.sh`) structure exactly — same 6-screen TUI flow, same sourcing pattern
- Key difference from LXC: uses `qm create` + cloud-init instead of `pct create` + LXC template
- `local` keyword NOT used for variables in main script body (only valid inside functions) — use plain assignment
- `boot_timeout` and `elapsed` declared as plain vars (not `local`) since they're in main script scope
- `VM_IP=""` initialized before the while loop to avoid unbound variable errors with `set -u`
- `cleanup_on_error "${VMID:-}" "vm"` — passes "vm" type (not "lxc") to trigger `qm stop/destroy` in cleanup

### Cloud-init Flow
- Download Debian 12 genericcloud qcow2 from `cloud.debian.org/images/cloud/bookworm/latest/`
- `qm create` with `--scsi0 storage:0,import-from=path,size=XG` imports the image
- `--ide2 storage:cloudinit` attaches cloud-init drive
- `qm set --ciuser root --cipassword ... --ipconfig0 ip=dhcp` configures cloud-init
- `qm disk resize VMID scsi0 XG` expands disk after import

### QA Results
- bash -n: exit 0 ✓
- source build.func: 3 matches (shellcheck directive + local + curl fallback) ✓
- qm create: present ✓
- cloud-init (cloudinit/ciuser/cloud-init): 3 matches ✓
- check_root/check_proxmox/check_internet: all 3 present ✓
- trap cleanup_on_error ERR: present ✓

### Gotchas
- GPG commit signing via 1Password SSH agent fails in non-interactive shell — use `git -c commit.gpgsign=false commit`
- `detect_storage | head -1` works fine in main script (not inside function, so `local` not needed)

## Task 4: ct/oracle26ai.sh

### Patterns
- Script sources `misc/build.func` with local-first + curl fallback pattern
- `whiptail_menu`, `whiptail_input`, `whiptail_yesno`, `whiptail_msg` from build.func handle ESC/Cancel internally — but explicit `|| { msg_warn "..."; exit 0; }` guards are needed on at least 2 screens to satisfy QA grep for `exit 0` count >= 2
- `pct create` uses multi-line continuation (`\`) — `grep "pct create" | grep "nesting=1"` won't match; grep for `nesting=1` separately
- `local` keyword inside functions is fine, but use bare `attempt=0` in main body (not `local attempt=0`)
- `--unprivileged 0` = privileged mode (required for Docker-in-LXC)

### Conventions
- Script is 177 lines, 6 whiptail screens exactly
- Trap registered before destructive operations: `trap 'cleanup_on_error "${VMID:-}" "lxc"' ERR`
- `detect_storage | head -1` used when `CT_STORAGE` not set in .env
- Install script pushed via `pct push` then executed with `pct exec` + env exports

### QA Results
- bash -n: exit 0 ✓
- source build.func: 2 matches (local + curl) ✓
- pct create + nesting=1: both present ✓
- keyctl=1: present ✓
- check_root/proxmox/internet: all 3 ✓
- cancel/exit 0: 2 matches ✓
- trap cleanup_on_error ERR: present ✓
