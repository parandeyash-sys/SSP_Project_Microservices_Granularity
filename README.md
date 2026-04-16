# Microservice Granularity Study — Online Boutique + Service Weaver

> Replication of *"Performance Impact of Microservice Granularity Decisions: An Empirical Evaluation Using the Service Weaver Framework"*

## Prerequisites

- **OS**: Ubuntu 22.04+ (or compatible Linux)
- **RAM**: ≥ 8 GB (16 GB recommended for distributed configs)
- **CPU**: ≥ 4 cores
- **Disk**: ≥ 5 GB free
- **Network**: VM1 must reach VM2 via SSH (for 2-VM experiments)

---

## Directory Structure

```
SSP_Online/
├── 00_install_deps.sh         # Install Go, weaver, Locust
├── 01_clone_build.sh          # Clone & build Online Boutique
├── 02_run_1vm_experiments.sh  # Run 4 × 1-VM configs
├── 02_run_2vm_experiments.sh  # Run 4 × 2-VM configs (SSH)
├── 03_collect_results.sh      # Parse CSVs → results/summary.csv
├── 04_plot_results.py         # Generate bar charts
├── locustfile.py              # Locust load test user flows
├── ssh_locations_2vm.txt      # VM IPs for SSH deployer
├── experiment.log             # Append-only run log
├── configs/
│   ├── 1vm_monolith.toml
│   ├── 1vm_frontend_colocated.toml
│   ├── 1vm_two_colocated.toml
│   ├── 1vm_distributed.toml
│   ├── 2vm_frontend_colocated.toml
│   ├── 2vm_frontend_distributed.toml
│   ├── 2vm_colocated_colocated.toml
│   └── 2vm_distributed_distributed.toml
├── results/
│   ├── 1vm/<config>/<vus>/locust_stats.csv
│   ├── 2vm/<config>/<vus>/locust_stats.csv
│   └── summary.csv
└── plots/
    ├── 1vm/  (avg_ms.png, p95_ms.png, p99_ms.png, max_ms.png, rps.png, overview.png)
    └── 2vm/  (same)
```

---

## Deployment Configurations

### 1-VM Configurations

| ID | Name | Description |
|---|---|---|
| `1vm_monolith` | **Monolith** | All 11 components in one OS process |
| `1vm_frontend_colocated` | **Frontend + Backend Groups** | Frontend & light services group + heavy backend group |
| `1vm_two_colocated` | **Three Groups** | Frontend alone + catalog group + checkout group |
| `1vm_distributed` | **Distributed** | Each component its own process |

### 2-VM Configurations

| ID | Name | VM1 | VM2 |
|---|---|---|---|
| `2vm_frontend_colocated` | **Frontend \| Colocated Backend** | frontend | all backend co-located |
| `2vm_frontend_distributed` | **Frontend \| Distributed Backend** | frontend | each backend separate |
| `2vm_colocated_colocated` | **Colocated \| Colocated** | frontend + catalog/browsing | cart/checkout/payment |
| `2vm_distributed_distributed` | **Distributed \| Distributed** | half components | other half |

---

## Step-by-Step: Phase 1 — 1-VM Experiments

### Step 1 — Install Dependencies

```bash
cd /home/yash/ssp/SSP_Online
chmod +x *.sh
./00_install_deps.sh
source ~/.bashrc          # ← IMPORTANT: reload PATH
```

Installs: **Go 1.22**, **Service Weaver CLI**, **Locust**, **matplotlib**, **pandas**, **seaborn**.

---

### Step 2 — Clone & Build Online Boutique

```bash
./01_clone_build.sh
```

This will:
1. Clone `https://github.com/ServiceWeaver/onlineboutique` → `./onlineboutique/`
2. Run `weaver generate ./...`
3. Build binary: `./onlineboutique/boutique`

Verify:
```bash
ls -lh onlineboutique/boutique
# Expected: -rwxr-xr-x  ... boutique
```

---

### Step 3 — (Optional) Smoke Test

```bash
# Terminal 1: start the monolith
weaver multi deploy configs/1vm_monolith.toml

# Terminal 2: verify app is up
curl http://localhost:8080/
# You should see HTML of the Online Boutique homepage

# Terminal 3: quick Locust smoke test (10 users, 30s)
source ~/ssp_venv/bin/activate
locust -f locustfile.py --headless -u 10 -r 2 \
  --host http://localhost:8080 --run-time 30s
```

---

### Step 4 — Run 1-VM Experiments

```bash
source ~/ssp_venv/bin/activate
./02_run_1vm_experiments.sh
```

**What it does:**
- Loops through 4 configurations × 7 workload levels (500, 750, 1000, 1250, 1500, 1750, 2000 VUs)
- Each level: **5 minutes** of load
- Saves Locust CSVs to `results/1vm/<config>/<vus>/`
- Appends progress to `experiment.log`

**Estimated time:** ~4 configs × 7 levels × 5 min = **~2.3 hours** (+ startup overhead)

**Monitor progress:**
```bash
# Follow log in another terminal
tail -f experiment.log
```

---

## Step-by-Step: Phase 2 — 2-VM Experiments

### Prerequisites

1. **Second VM available** with Linux + internet access.
2. **Passwordless SSH** from VM1 → VM2:

```bash
# On VM1 (this machine):
ssh-keygen -t ed25519 -f ~/.ssh/id_ssp -N ""
ssh-copy-id -i ~/.ssh/id_ssp.pub user@<VM2_IP>
ssh <VM2_IP> "echo SSH OK"   # should print: SSH OK
```

3. **Install Go & weaver on VM2:**
```bash
ssh user@<VM2_IP>
# On VM2: copy and run 00_install_deps.sh
```

4. **Copy the binary to VM2:**
```bash
# On VM1:
ssh user@<VM2_IP> "mkdir -p ~/ssp/SSP_Online/onlineboutique"
scp onlineboutique/boutique user@<VM2_IP>:~/ssp/SSP_Online/onlineboutique/boutique
```

5. **Update SSH locations file:**
```bash
# Edit: ssh_locations_2vm.txt
# Replace <VM2_IP_ADDRESS> with actual IP
VM1_IP=$(hostname -I | awk '{print $1}')
echo "$VM1_IP" > ssh_locations_2vm.txt
echo "192.168.x.x"  >> ssh_locations_2vm.txt   # ← your actual VM2 IP
```

---

### Step 5 — Run 2-VM Experiments

```bash
source ~/ssp_venv/bin/activate
export VM2_HOST="192.168.x.x"   # ← set your actual VM2 IP
./02_run_2vm_experiments.sh
```

**Estimated time:** ~4 configs × 7 levels × 5 min = **~2.3 hours** (+ SSH/startup overhead)

---

## Step-by-Step: Phase 3 — Collect & Plot Results

### Step 6 — Parse Locust CSVs

```bash
./03_collect_results.sh
# Output: results/summary.csv
head -5 results/summary.csv
```

### Step 7 — Generate Bar Charts

```bash
source ~/ssp_venv/bin/activate
python3 04_plot_results.py
```

**Output:**
```
plots/1vm/avg_ms.png       — Average response time
plots/1vm/p95_ms.png       — P95 response time
plots/1vm/p99_ms.png       — P99 response time
plots/1vm/max_ms.png       — Max response time
plots/1vm/rps.png          — Requests/s
plots/1vm/overview.png     — All metrics in one figure
plots/2vm/...              — Same for 2-VM configs
```

---

## Workload Parameters (from the paper)

| Parameter | Value |
|---|---|
| Virtual Users (VUs) | 500, 750, 1000, 1250, 1500, 1750, 2000 |
| Spawn Rate | VUs ÷ 30 per second |
| Duration per level | 5 minutes (300s) |
| Think Time | 1–5 seconds (random) |
| Target | `http://localhost:8080` |
| Metrics | P95, P99, Avg, Max response time (ms) + RPS |

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `weaver: command not found` | `source ~/.bashrc` or `export PATH=$HOME/go/bin:$PATH` |
| `locust: command not found` | `source ~/ssp_venv/bin/activate` |
| App not ready within 60s | Check `results/1vm/<config>/<vus>/app.log` for errors |
| 2-VM SSH fails | Verify `ssh -o BatchMode=yes <VM2_HOST> echo ok` works |
| `weaver generate` fails | Ensure Go 1.21+ and run inside the `onlineboutique/` dir |
| Port 8080 already in use | `fuser -k 8080/tcp` then retry |
| Locust shows high failure% | App may be overloaded — check `app.log`, reduce max VUs |

---

## Results CSV Format

`results/summary.csv`:
```
vm_count,config,vus,avg_ms,p50_ms,p95_ms,p99_ms,max_ms,rps,failure_pct
1,1vm_monolith,500,45.2,38,120,210,1540,312.4,0.00
...
```

---

## Citation

> *"Performance Impact of Microservice Granularity Decisions: An Empirical Evaluation Using the Service Weaver Framework"*
> Service Weaver Online Boutique: https://github.com/ServiceWeaver/onlineboutique
> Service Weaver: https://serviceweaver.dev
