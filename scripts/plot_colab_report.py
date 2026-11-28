"""Validate all four Colab benchmark groups and rebuild report figures.

Run: python scripts/plot_colab_report.py
"""
import csv
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

import plot_process_benchmarks
import plot_peak_ram
import plot_scalability
import plot_transaction_length

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "results/benchmarks/colab_20261125"
OUT = ROOT / "reports/figures/benchmarks"
ORDER = ("chess", "mushroom", "retail", "T10I4D100K")
COLORS = ("#315a86", "#b35a32", "#39856b")


def read_csv(path):
    with path.open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def error_line(axis, rows, x, prefix, label, color, scale=1):
    center = [scale * float(r[f"{prefix}median_seconds"]) for r in rows]
    errors = [[v - scale * float(r[f"{prefix}min_seconds"]) for r, v in zip(rows, center)],
              [scale * float(r[f"{prefix}max_seconds"]) - v for r, v in zip(rows, center)]]
    axis.errorbar(x, center, yerr=errors, fmt="o-", capsize=2, markersize=3,
                  linewidth=1, label=label, color=color)


def save(fig, name):
    for axis in fig.axes:
        axis.grid(axis="y", alpha=0.2)
        axis.set_axisbelow(True)
    fig.savefig(OUT / f"{name}.pdf")
    plt.close(fig)


def main():
    groups = {}
    for name, module, expected in (("processes", plot_process_benchmarks, 420),
                                   ("peak_ram", plot_peak_ram, 40),
                                   ("scalability", plot_scalability, 50),
                                   ("transaction_length", plot_transaction_length, 50)):
        summary = read_csv(DATA / name / "summary.csv")
        raw = read_csv(DATA / name / "runs.csv")
        module.validate(summary, raw)
        assert len(raw) == expected and all(r["n_runs"] == "5" for r in summary)
        groups[name] = summary
    OUT.mkdir(parents=True, exist_ok=True)
    plt.rcParams.update({"font.family": "serif", "font.serif": ["Times New Roman"], "font.size": 8})

    fig, axes = plt.subplots(2, 4, figsize=(7.1, 4.2), layout="constrained")
    for column, dataset in enumerate(ORDER):
        rows = sorted((r for r in groups["processes"] if r["dataset"] == dataset),
                      key=lambda r: -float(r["minsup"]))
        x = [100 * float(r["minsup"]) for r in rows]
        for prefix, label, color in zip(("julia_", "optimized_", "spmf_"),
                                         ("Set", "BitVector", "SPMF"), COLORS):
            error_line(axes[0, column], rows, x, prefix, label, color)
        axes[0, column].set(title=dataset.capitalize() if dataset != "T10I4D100K" else dataset,
                            yscale="log")
        axes[1, column].plot(x, [int(r["n_itemsets"]) for r in rows], "o-",
                             color=COLORS[0], markersize=3, linewidth=1)
        axes[1, column].set(yscale="log", xlabel="Minsup (%)")
        for row in range(2):
            axes[row, column].set_xticks([x[0], x[3], x[-1]])
            axes[row, column].invert_xaxis()
    axes[0, 0].set_ylabel("Toàn tiến trình (s, log)")
    axes[1, 0].set_ylabel("Số itemset (log)")
    axes[0, 0].legend(fontsize=6, frameon=False)
    save(fig, "runtime_counts")

    fig, axis = plt.subplots(figsize=(3.45, 2.4), layout="constrained")
    rows = [next(r for r in groups["peak_ram"] if r["dataset"] == d) for d in ORDER]
    for prefix, label, offset, color in (("baseline", "Set", -0.18, COLORS[0]),
                                        ("optimized", "BitVector", 0.18, COLORS[1])):
        values = [float(r[f"{prefix}_median_mib"]) for r in rows]
        error = [[v-float(r[f"{prefix}_min_mib"]) for r,v in zip(rows, values)],
                 [float(r[f"{prefix}_max_mib"])-v for r,v in zip(rows, values)]]
        axis.bar([i+offset for i in range(4)], values, width=0.34, yerr=error,
                 capsize=2, label=label, color=color)
    axis.set(ylabel="Peak RSS tiến trình (MiB)", ylim=(0, 520))
    axis.set_xticks(range(4), ("Chess", "Mushroom", "Retail", "T10I4D100K"), fontsize=7)
    axis.legend(frameon=False, fontsize=7)
    save(fig, "peak_ram")

    fig, axis = plt.subplots(figsize=(3.45, 2.4), layout="constrained")
    for backend, label, color in zip(("set", "bitvector"), ("Set", "BitVector"), COLORS):
        rows = sorted((r for r in groups["scalability"] if r["backend"] == backend),
                      key=lambda r: int(r["n_transactions"]))
        error_line(axis, rows, [int(r["n_transactions"])/1000 for r in rows], "", label, color, 1000)
    axis.set(xlabel="Số giao dịch (nghìn)", ylabel="Mine sau warm-up (ms)")
    axis.legend(frameon=False, fontsize=7)
    save(fig, "scalability")

    fig, axes = plt.subplots(1, 2, figsize=(7.1, 2.35), layout="constrained")
    for backend, label, color in zip(("set", "bitvector"), ("Set", "BitVector"), COLORS):
        rows = sorted((r for r in groups["transaction_length"] if r["backend"] == backend),
                      key=lambda r: int(r["transaction_length"]))
        x = [int(r["transaction_length"]) for r in rows]
        error_line(axes[0], rows, x, "", label, color, 1000)
    axes[0].set(yscale="log", ylabel="Mine sau warm-up (ms, log)")
    axes[0].legend(frameon=False, fontsize=7)
    axes[1].plot(x, [int(r["n_itemsets"]) for r in rows], "o-", color=COLORS[0], markersize=3)
    axes[1].set(ylabel="Số itemset", ylim=(0, 2300))
    for axis in axes:
        axis.set(xlabel="Độ dài giao dịch", xticks=x)
    save(fig, "transaction_length")
    print("PASS: 560 Colab measurements, all four validators; report figures regenerated.")


if __name__ == "__main__":
    main()
