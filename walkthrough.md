# Walkthrough — Microservice Granularity Study Setup

## What Was Built

A complete study replication kit for the paper *"Performance Impact of Microservice Granularity Decisions: An Empirical Evaluation Using the Service Weaver Framework"*, using Google's Online Boutique app (Service Weaver port).

---

## Files Created in `/home/yash/ssp/SSP_Online/`

### Shell Scripts (all executable)

| File | Purpose |
|---|---|
| [00_install_deps.sh](file:///home/yash/ssp/SSP_Online/00_install_deps.sh) | Installs Go 1.22, weaver CLI, Locust, matplotlib, pandas |
| [01_clone_build.sh](file:///home/yash/ssp/SSP_Online/01_clone_build.sh) | Clones Online Boutique, runs `weaver generate`, builds binary |
| [02_run_1vm_experiments.sh](file:///home/yash/ssp/SSP_Online/02_run_1vm_experiments.sh) | Runs 4×1VM configs × 7 workload levels (~2.3 hours) |
| [02_run_2vm_experiments.sh](file:///home/yash/ssp/SSP_Online/02_run_2vm_experiments.sh) | Runs 4×2VM configs via SSH deployer (requires VM2) |
| [03_collect_results.sh](file:///home/yash/ssp/SSP_Online/03_collect_results.sh) | Parses Locust CSVs -> `results/summary.csv` |

### Analysis Scripts

| File | Purpose |
|---|---|
| [04_plot_results.py](file:///home/yash/ssp/SSP_Online/04_plot_results.py) | Generates dark-themed grouped bar charts (1VM + 2VM) |
| [locustfile.py](file:///home/yash/ssp/SSP_Online/locustfile.py) | Locust load test: 8 weighted tasks (browse, cart, checkout, ...) |

### TOML Deployment Configs (all syntax-verified)

#### 1-VM Configurations

| File | Granularity |
|---|---|
| [1vm_monolith.toml](file:///home/yash/ssp/SSP_Online/configs/1vm_monolith.toml) | All 11 components in 1 process |
| [1vm_frontend_colocated.toml](file:///home/yash/ssp/SSP_Online/configs/1vm_frontend_colocated.toml) | 2 process groups (frontend+light / heavy backend) |
| [1vm_two_colocated.toml](file:///home/yash/ssp/SSP_Online/configs/1vm_two_colocated.toml) | 3 process groups (frontend / catalog / checkout) |
| [1vm_distributed.toml](file:///home/yash/ssp/SSP_Online/configs/1vm_distributed.toml) | 11 separate processes (fully distributed) |

#### 2-VM Configurations (SSH Deployer)

| File | VM1 | VM2 |
|---|---|---|
| [2vm_frontend_colocated.toml](file:///home/yash/ssp/SSP_Online/configs/2vm_frontend_colocated.toml) | frontend | all backend co-located |
| [2vm_frontend_distributed.toml](file:///home/yash/ssp/SSP_Online/configs/2vm_frontend_distributed.toml) | frontend | each backend separate |
| [2vm_colocated_colocated.toml](file:///home/yash/ssp/SSP_Online/configs/2vm_colocated_colocated.toml) | frontend + catalog group | cart/checkout group |
| [2vm_distributed_distributed.toml](file:///home/yash/ssp/SSP_Online/configs/2vm_distributed_distributed.toml) | half components | other half |

### Other Files

| File | Purpose |
|---|---|
| [README.md](file:///home/yash/ssp/SSP_Online/README.md) | Full step-by-step guide |
| [experiment.log](file:///home/yash/ssp/SSP_Online/experiment.log) | Append-only run log (updated by scripts) |
| [ssh_locations_2vm.txt](file:///home/yash/ssp/SSP_Online/ssh_locations_2vm.txt) | VM IPs for SSH deployer (needs VM2 IP filled in) |

---

## Validation Results

- All 8 TOML config files passed Python `tomllib` syntax validation
- All `.sh` scripts are marked executable
- Locust file correctly targets Online Boutique endpoints (`/`, `/product/{id}`, `/cart`, `/cart/checkout`, `/setCurrency`, `/cart/empty`)
- `results/summary.csv` schema matches paper metrics (avg, p50, p95, p99, max, RPS, failure_pct)

---

## Execution Order for User

### Phase 1 — 1-VM (on this machine)
```bash
cd /home/yash/ssp/SSP_Online
./00_install_deps.sh && source ~/.bashrc
./01_clone_build.sh
source ~/ssp_venv/bin/activate
./02_run_1vm_experiments.sh        # ~2.3 hours total
./03_collect_results.sh
python3 04_plot_results.py
```

### Phase 2 — 2-VM (requires second VM via SSH)
```bash
# Setup passwordless SSH + copy binary to VM2 (see README.md for full steps)
export VM2_HOST="<your-vm2-ip>"
./02_run_2vm_experiments.sh        # ~2.3 hours total
./03_collect_results.sh
python3 04_plot_results.py
```

---

## Output Artifacts (generated after running)

```
results/
  1vm/<config>/<vus>/locust_stats.csv     # raw Locust output per run
  2vm/<config>/<vus>/locust_stats.csv
  summary.csv                             # aggregated metrics table

plots/
  1vm/avg_ms.png   p95_ms.png   p99_ms.png
       max_ms.png   rps.png     overview.png
  2vm/ (same structure)
```
