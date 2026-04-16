# Microservice Granularity Study — Online Boutique + Service Weaver

> Replication of *"Performance Impact of Microservice Granularity Decisions: An Empirical Evaluation Using the Service Weaver Framework"* using a **Minikube (Kubernetes) environment**.

## Project Directory: `/home/yash/ssp/SSP_Online/`

## Prerequisites

- **OS**: Ubuntu 22.04+ (or compatible Linux)
- **Virtualization**: **VirtualBox** installed (required for Minikube `virtualbox` driver)
- **Minikube**: Installed and configured
- **Kubectl**: Installed
- **RAM**: ≥ 8 GB (16 GB highly recommended for 2-node experiments)
- **Disk**: ≥ 10 GB free

---

## Directory Structure

```text
SSP_Online/
├── 00_install_deps.sh         # Install Go, weaver, Minikube, kubectl, VBox
├── 01_clone_build.sh          # Clone & build Online Boutique
├── 02_run_1vm_experiments.sh  # Run 4 × 1-VM configs (1-node Minikube)
├── 02_run_2vm_experiments.sh  # Run 4 × 2-VM configs (2-node Minikube)
├── 03_collect_results.sh      # Parse CSVs → results/summary.csv
├── 04_plot_results.py         # Generate bar charts (1VM + 2VM)
├── 05_setup_prometheus.sh     # Download Prometheus & Node Exporter
├── monitoring/
│   ├── lib_monitor.sh         # Sysstat remote handlers (minikube ssh)
│   ├── start_prometheus.sh    # Starts Prom + Exporter
│   └── stop_prometheus.sh     # Stops Prom + Exporter
├── scripts/
│   └── inject_nodes.py        # Helper to pin pods to nodes in 2nd VM suite
├── locustfile.py              # Locust load test user flows
├── configs/                   # YAML (K8s) & TOML (Weaver) configurations
└── results/                   # Isolated telemetry data per run
```

---

## Step-by-Step Execution

### Phase 1: Environment Setup

1. **Install Dependencies**
   ```bash
   chmod +x *.sh
   ./00_install_deps.sh
   source ~/.bashrc
   ```

2. **Clone & Build**
   ```bash
   ./01_clone_build.sh
   ```

3. **Setup Monitoring**
   ```bash
   ./05_setup_prometheus.sh
   ./monitoring/start_prometheus.sh
   ```

---

### Phase 2: Running 1-VM Experiments
This runs tests on a single-node Minikube cluster.

```bash
source ~/ssp_venv/bin/activate
./02_run_1vm_experiments.sh
```

**What it does:**
- Starts Minikube with `--nodes 1 --driver=virtualbox`.
- Deploys 4 configurations sequentially.
- Collects 1s-interval system metrics via `minikube ssh`.

---

### Phase 3: Running 2-VM Experiments
This runs tests on a two-node Minikube cluster (`minikube` + `minikube-m02`).

```bash
source ~/ssp_venv/bin/activate
./02_run_2vm_experiments.sh
```

**What it does:**
- Starts Minikube with `--nodes 2 --driver=virtualbox`.
- Injects `nodeSelector` into manifests to distribute pods between Node 1 and Node 2.
- Collects metrics from *both* nodes simultaneously.

---

### Phase 4: Data Processing & Visualization

1. **Collect Results**
   ```bash
   ./03_collect_results.sh
   ```

2. **Generate Plots**
   ```bash
   source ~/ssp_venv/bin/activate
   python3 04_plot_results.py
   ```

**Outputs:**
- `results/summary.csv`: Aggregated performance data.
- `plots/`: Comparison charts (e.g., `avg_ms.png`, `overview.png`).

---

## Troubleshooting

| Error | Fix |
|---|---|
| `VirtualBox is not installed` | Ensure `virtualbox` is in your host path. |
| `minikube start` hangs | Verify VT-x/AMD-V is enabled. |
| `GUEST_DRIVER_MISMATCH` | The script uses a private profile `ssp-study` to avoid this. If it persists, run `minikube delete -p ssp-study`. |
| `weaver-kube: command not found` | `source ~/.bashrc` or check `$HOME/go/bin`. |
| Port 8080 busy | `fuser -k 8080/tcp` |

---
*Citation: Performance Impact of Microservice Granularity Decisions: An Empirical Evaluation Using the Service Weaver Framework.*
