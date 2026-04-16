# Microservice Granularity Study – Task Checklist

## Phase 1: Planning
- [x] Research Service Weaver Online Boutique component graph
- [x] Read Service Weaver config (TOML colocate + SSH deployer) docs
- [/] Create implementation plan (`implementation_plan.md`)
- [ ] Get user approval on plan

## Phase 2: Execution – Project Structure & Scripts
- [ ] Create project directory structure in `/home/yash/ssp/SSP_Online/`
- [ ] Create `00_install_deps.sh` – install Go, weaver CLI, Locust, deps
- [ ] Create `01_clone_build.sh` – clone Online Boutique, build binary
- [ ] Create TOML config files for 8 configurations (4×1VM + 4×2VM)
- [ ] Create `02_run_experiment.sh` – orchestrate all experiments
- [ ] Create `locustfile.py` – load test script with Online Boutique user flows
- [ ] Create `03_collect_results.sh` – parse Locust CSV → structured metrics
- [ ] Create `04_plot_results.py` – generate bar charts (1VM + 2VM)
- [ ] Create `experiment.log` template / init script
- [ ] Create `README.md` with step-by-step instructions

## Phase 3: Verification
- [ ] Dry-run config syntax check (weaver.toml TOML validity)
- [ ] Confirm Locust script targets correct Online Boutique endpoints
- [ ] Verify bar chart output structure matches paper format

## Phase 4: User Execution
- [ ] User runs 1-VM experiments (4 configs)
- [ ] User runs 2-VM experiments (4 configs, requires 2nd VM/host)
- [ ] User collects p50/p95/p99/avg/max/RPS metrics
- [ ] User reviews plots and analysis
