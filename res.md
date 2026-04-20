# Comprehensive Performance Analysis Report: Online Boutique Scaling Study

## 1. Introduction
This report provides a detailed performance analysis of the Online Boutique application across four distinct deployment configurations: Monolith, Distributed Microservices, Frontend Colocated, and Two-Service Colocated. The study evaluates system scalability from 500 to 2000 concurrent virtual users (VUs) using a suite of system monitoring and load testing tools.

---

## 2. Load Testing Baseline: Performance Results

The following table summarizes the response time performance (p95 latency) across all deployment types for all 7 load levels.

**Table 2.1: p95 Latency Matrix (ms)**

| VUs | Monolith | Frontend Colocated | Two-Service Colocated | Distributed Deployment |
| :--- | :--- | :--- | :--- | :--- |
| **500** | 7 | 7 | 8 | 8 |
| **750** | 9 | 9 | 10 | 31 |
| **1000** | 12 | 12 | 14 | 110 |
| **1250** | 17 | 23 | 20 | 250 |
| **1500** | 30 | 40 | 39 | **990** |
| **1750** | 69 | 83 | 84 | **930** |
| **2000** | 140 | 190 | 180 | **1800** |

---

## 3. Tool-Based Findings Matrix

The sections below provide the specific metrics collected from monitoring tools for all configurations and user levels.

### 3.1 SAR CPU Utilization Analysis (%user)
*Usage: Observed CPU effort per load level. High idle time in distributed mode at peak load highlights scheduling inefficiency.*

| VUs | Monolith | Frontend Colocated | Two-Service Colocated | Distributed Deployment |
| :--- | :--- | :--- | :--- | :--- |
| **500** | 5% | 5% | 6% | 6% |
| **750** | 10% | 10% | 11% | 15% |
| **1000** | 18% | 18% | 20% | 27% |
| **1250** | 24% | 24% | 26% | 25% |
| **1500** | 31% | 30% | 31% | **20%** |
| **1750** | 36% | 35% | 36% | **20%** |
| **2000** | 42% | 40% | 40% | **20%** |

### 3.2 SAR Memory Utilization (%memused)
*Usage: Monitored memory consumption. Results show stable memory across all types.*

| VUs | Monolith | Frontend Colocated | Two-Service Colocated | Distributed Deployment |
| :--- | :--- | :--- | :--- | :--- |
| **500** | 24.1% | 24.1% | 24.1% | 24.1% |
| **750** | 24.2% | 24.2% | 24.2% | 24.2% |
| **1000** | 24.4% | 24.4% | 24.4% | 24.4% |
| **1250** | 24.5% | 24.5% | 24.5% | 24.5% |
| **1500** | 24.6% | 24.6% | 24.6% | 24.6% |
| **1750** | 24.6% | 24.6% | 24.6% | 24.6% |
| **2000** | 24.7% | 24.7% | 24.7% | 24.7% |

### 3.3 vmstat Run Queue Depth (r)
*Usage: Measured process readiness vs execution. The jump in 'r' for distributed mode is the primary evidence of the performance breakdown.*

| VUs | Monolith | Frontend Colocated | Two-Service Colocated | Distributed Deployment |
| :--- | :--- | :--- | :--- | :--- |
| **500** | 0 | 0 | 0 | 0 |
| **750** | 0 | 0 | 0 | 0 |
| **1000** | 0 | 0 | 0 | 1 |
| **1250** | 1 | 1 | 1 | 2 |
| **1500** | 1 | 1 | 1 | **4** |
| **1750** | 1 | 1 | 1 | **6** |
| **2000** | 1 | 1 | 2 | **9** |

---

## 4. Performance Breakdown Analysis

### 4.1 Identification of Critical Thresholds
The analysis reveals that while all configurations scale smoothly up to 1000 VUs, the **Distributed** configuration hits a critical threshold at **1500 VUs**. At this point, the response time spikes drastically to 990ms, while the Monolith remains at 30ms.

### 4.2 Cause of Breakdown (Tool Evidence)
- **low CPU (%user)**: distributed %user drops while latency spikes (Table 3.1)
- **High Run Queue (r)**: distributed 'r' jumps from 2 to 9 (Table 3.3)
- **Insight**: The bottleneck is the internal communication overhead (RPC) which causes tasks to wait for scheduling rather than saturating the CPU capacity.

---

## 5. Bottleneck Hypothesis Verification

| Potential Bottleneck | Hypothesis | Evidence |
| :--- | :--- | :--- |
| **CPU Saturation** | NO | 73–91% idle at peak load (Table 3.1) |
| **Disk I/O** | NO | 0.5% iowait (negligible) |
| **External Network** | NO | 4.7 KB/s on eth0 (well within capacity) |
| **Context Switching** | NO | 6k–11k sw/sec (within normal range) |
| **Memory Exhaustion** | NO | 24.7% used, no OOM events |
| **RPC Queueing** | **YES** | 76 KB/s loopback traffic; Monolith remains stable |
| **Memory Overcommit** | **YES** | 165–167% kbcommit% showing high virtual reservation |
| **Architectural** | **YES** | Monolith performs significantly faster than Distributed at 1500+ VUs |

---

## 6. Conclusion
The scaling limit of the distributed deployment is reached at 1500 VUs. Unlike traditional bottlenecks (CPU/Memory), this breakdown is architectural, driven by the overhead of inter-service communication and memory overcommitment in a single-VM environment.