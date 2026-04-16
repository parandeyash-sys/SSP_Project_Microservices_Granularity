#!/usr/bin/env python3
"""
04_plot_results.py — Generate bar charts from results/summary.csv
=================================================================
Produces two sets of publication-quality bar charts:
  • plots/1vm/  — one chart per metric for 1-VM configs
  • plots/2vm/  — one chart per metric for 2-VM configs

Each chart:
  X-axis: Virtual Users (workload level)
  Y-axis: Response time (ms) or Requests/s
  Bars: one grouped bar per configuration

Run:
  python3 04_plot_results.py
"""

import os
import sys
import pandas as pd
import matplotlib
matplotlib.use("Agg")  # headless rendering
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import numpy as np

# ── Config ────────────────────────────────────────────────────────────────────
SUMMARY_CSV = "results/summary.csv"
PLOT_DIR = "plots"

# Human-readable labels for each configuration
CONFIG_LABELS = {
    # 1-VM
    "1vm_monolith":             "Monolith",
    "1vm_frontend_colocated":   "Frontend+Backend\nGroups",
    "1vm_two_colocated":        "Three\nGroups",
    "1vm_distributed":          "Distributed",
    # 2-VM
    "2vm_frontend_colocated":   "Frontend | \nColocated Backend",
    "2vm_frontend_distributed": "Frontend | \nDistributed Backend",
    "2vm_colocated_colocated":  "Colocated | \nColocated",
    "2vm_distributed_distributed": "Distributed | \nDistributed",
}

# Metrics to produce charts for
METRICS = [
    ("avg_ms",  "Average Response Time (ms)",  "Avg"),
    ("p95_ms",  "P95 Response Time (ms)",       "P95"),
    ("p99_ms",  "P99 Response Time (ms)",       "P99"),
    ("max_ms",  "Max Response Time (ms)",       "Max"),
    ("rps",     "Requests per Second (RPS)",    "RPS"),
]

# Colour palettes (one per config, consistent across charts)
PALETTE_1VM = ["#4C72B0", "#DD8452", "#55A868", "#C44E52"]
PALETTE_2VM = ["#8172B3", "#937860", "#CCB974", "#64B5CD"]


def load_data():
    if not os.path.exists(SUMMARY_CSV):
        print(f"[ERROR] {SUMMARY_CSV} not found. Run 03_collect_results.sh first.")
        sys.exit(1)
    df = pd.read_csv(SUMMARY_CSV)
    # Coerce numeric columns
    for col in ["avg_ms", "p50_ms", "p95_ms", "p99_ms", "max_ms", "rps", "failure_pct"]:
        df[col] = pd.to_numeric(df[col], errors="coerce")
    return df


def make_grouped_bar_chart(df, configs, vms_label, metric_col, y_label,
                           title_suffix, palette, out_path):
    """
    Draw a grouped bar chart.
      df:         filtered DataFrame for this VM set
      configs:    ordered list of config names to plot
      metric_col: column name to plot on Y-axis
      palette:    list of bar colours (one per config)
    """
    workloads = sorted(df["vus"].unique())
    n_configs = len(configs)
    n_workloads = len(workloads)

    x = np.arange(n_workloads)
    bar_width = 0.8 / n_configs
    offsets = np.linspace(-(n_configs - 1) / 2, (n_configs - 1) / 2, n_configs) * bar_width

    fig, ax = plt.subplots(figsize=(12, 6))
    fig.patch.set_facecolor("#1a1a2e")
    ax.set_facecolor("#16213e")

    for i, (cfg, color) in enumerate(zip(configs, palette)):
        vals = []
        for vu in workloads:
            row = df[(df["config"] == cfg) & (df["vus"] == vu)]
            vals.append(row[metric_col].values[0] if not row.empty else 0)

        bars = ax.bar(
            x + offsets[i],
            vals,
            width=bar_width * 0.92,
            label=CONFIG_LABELS.get(cfg, cfg),
            color=color,
            edgecolor="white",
            linewidth=0.4,
            alpha=0.92,
        )
        # Value labels on bars
        for bar, val in zip(bars, vals):
            if val > 0:
                ax.text(
                    bar.get_x() + bar.get_width() / 2,
                    bar.get_height() + max(vals) * 0.01,
                    f"{val:.0f}",
                    ha="center", va="bottom",
                    fontsize=7, color="white", alpha=0.85,
                )

    ax.set_xticks(x)
    ax.set_xticklabels([str(int(v)) for v in workloads],
                       color="white", fontsize=10)
    ax.set_xlabel("Virtual Users (Workload Level)", color="white", fontsize=12, labelpad=8)
    ax.set_ylabel(y_label, color="white", fontsize=12, labelpad=8)
    ax.set_title(
        f"{vms_label} Configurations — {title_suffix}",
        color="white", fontsize=14, fontweight="bold", pad=14,
    )
    ax.tick_params(colors="white")
    ax.yaxis.set_major_formatter(mticker.FuncFormatter(lambda v, _: f"{v:,.0f}"))
    ax.spines[:].set_color("#444")

    legend = ax.legend(
        loc="upper left", framealpha=0.3,
        labelcolor="white", facecolor="#0d0d1a",
        fontsize=9, title=f"{vms_label} Config",
        title_fontsize=9,
    )
    legend.get_title().set_color("white")

    ax.yaxis.grid(True, linestyle="--", alpha=0.25, color="white")
    ax.set_axisbelow(True)

    plt.tight_layout()
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    plt.savefig(out_path, dpi=150, bbox_inches="tight",
                facecolor=fig.get_facecolor())
    plt.close()
    print(f"  ✔  Saved: {out_path}")


def main():
    df = load_data()

    for vm_count, vms_label, palette, configs in [
        (1, "1-VM", PALETTE_1VM, [
            "1vm_monolith", "1vm_frontend_colocated",
            "1vm_two_colocated", "1vm_distributed",
        ]),
        (2, "2-VM", PALETTE_2VM, [
            "2vm_frontend_colocated", "2vm_frontend_distributed",
            "2vm_colocated_colocated", "2vm_distributed_distributed",
        ]),
    ]:
        subset = df[df["vm_count"] == vm_count]
        if subset.empty:
            print(f"[WARN] No data for {vms_label} — skipping charts.")
            continue

        print(f"\nGenerating {vms_label} charts...")
        out_dir = os.path.join(PLOT_DIR, f"{vm_count}vm")

        for metric_col, y_label, title_suffix in METRICS:
            if metric_col not in subset.columns:
                continue
            out_path = os.path.join(out_dir, f"{metric_col}.png")
            make_grouped_bar_chart(
                subset, configs, vms_label, metric_col,
                y_label, title_suffix, palette, out_path,
            )

        # ── Combined overview chart (all 5 metrics as subplots) ──────────────
        fig, axes = plt.subplots(2, 3, figsize=(18, 10))
        fig.patch.set_facecolor("#1a1a2e")
        fig.suptitle(
            f"{vms_label} Performance Overview — All Metrics",
            color="white", fontsize=16, fontweight="bold", y=1.01,
        )
        axes_flat = axes.flatten()

        for ax_i, (metric_col, y_label, title_suffix) in enumerate(METRICS):
            ax = axes_flat[ax_i]
            ax.set_facecolor("#16213e")
            workloads = sorted(subset["vus"].unique())
            x = np.arange(len(workloads))
            n = len(configs)
            bw = 0.8 / n
            offs = np.linspace(-(n - 1) / 2, (n - 1) / 2, n) * bw
            for i, (cfg, color) in enumerate(zip(configs, palette)):
                vals = [
                    subset[(subset["config"] == cfg) & (subset["vus"] == vu)][metric_col].values[0]
                    if not subset[(subset["config"] == cfg) & (subset["vus"] == vu)].empty else 0
                    for vu in workloads
                ]
                ax.bar(x + offs[i], vals, width=bw * 0.9,
                       label=CONFIG_LABELS.get(cfg, cfg),
                       color=color, edgecolor="white", linewidth=0.3, alpha=0.9)
            ax.set_xticks(x)
            ax.set_xticklabels([str(int(v)) for v in workloads], color="white", fontsize=8)
            ax.set_title(title_suffix, color="white", fontsize=10)
            ax.set_xlabel("VUs", color="white", fontsize=8)
            ax.set_ylabel(y_label, color="white", fontsize=8)
            ax.tick_params(colors="white")
            ax.spines[:].set_color("#444")
            ax.yaxis.grid(True, linestyle="--", alpha=0.2, color="white")
            ax.set_axisbelow(True)

        # Hide unused 6th subplot
        axes_flat[-1].set_visible(False)

        # Shared legend
        handles, labels = axes_flat[0].get_legend_handles_labels()
        fig.legend(handles, labels, loc="lower right",
                   ncol=2, framealpha=0.3,
                   labelcolor="white", facecolor="#0d0d1a",
                   fontsize=9, bbox_to_anchor=(0.98, 0.02))

        plt.tight_layout()
        overview_path = os.path.join(out_dir, "overview.png")
        plt.savefig(overview_path, dpi=150, bbox_inches="tight",
                    facecolor=fig.get_facecolor())
        plt.close()
        print(f"  ✔  Overview saved: {overview_path}")

    print("\n✅ All charts generated in:", PLOT_DIR)


if __name__ == "__main__":
    main()
