"""Validate the selected Colab evidence and regenerate the report figure.

Run: python scripts/plot_fashion_report.py
"""
import csv
from pathlib import Path
from statistics import median
import tomllib

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "results/fashion/colab_report_20261125"


def read_csv(name):
    with (DATA / name).open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def main():
    rows = read_csv("comparison.csv")
    timings = read_csv("timings_raw.csv")
    lengths = read_csv("length_distribution.csv")
    patterns = read_csv("patterns.csv")
    meta = tomllib.loads((DATA / "runtime_observations.toml").read_text())
    assert meta["images"] == meta["transaction_count"] == 70000
    assert meta["kmeans_converged"] and meta["kmeans_iterations"] == 372
    assert len(rows) == 6 and len(timings) == 60 and len(patterns) == 4
    for row in rows:
        assert row["exact_parity"] == row["direct_support_audit"] == "true"
        total = sum(int(x["itemsets"]) for x in lengths if x["minsup"] == row["minsup"])
        assert total == int(row["itemsets"])
        for backend in ("set", "bitvector"):
            samples = [x for x in timings if x["minsup"] == row["minsup"] and x["backend"] == backend]
            assert len(samples) == 5 and {int(x["repeat"]) for x in samples} == set(range(1, 6))
            assert all(x["itemsets"] == row["itemsets"] for x in samples)
            values = [float(x["seconds"]) for x in samples]
            assert min(values) > 0
            for name, function in (("median", median), ("min", min), ("max", max)):
                assert function(values) == float(row[f"{backend}_{name}"])
    for pattern in patterns:
        assert sum(int(pattern[f"class_{i}"]) for i in range(10)) == int(pattern["support_count"])

    plt.rcParams.update({"font.family": "serif", "font.serif": ["Times New Roman"], "font.size": 8})
    fig, axes = plt.subplots(1, 3, figsize=(7.1, 2.35), layout="constrained")
    ticks = [f"{100 * float(row['minsup']):g}" for row in rows]
    positions = list(range(len(rows)))
    counts = [int(row["itemsets"]) for row in rows]
    axes[0].plot(positions, counts, "o-", color="#315a86", markersize=3)
    axes[0].set(yscale="symlog", ylabel="Số itemset", title="(a) Kích thước kết quả")
    for backend, label, color in (("set", "Set", "#b35a32"), ("bitvector", "BitVector", "#315a86")):
        center = [float(row[f"{backend}_median"]) for row in rows]
        errors = [[center[i] - float(row[f"{backend}_min"]) for i, row in enumerate(rows)],
                  [float(row[f"{backend}_max"]) - center[i] for i, row in enumerate(rows)]]
        axes[1].errorbar(positions, center, yerr=errors, fmt="o-", color=color, label=label,
                         capsize=2, markersize=3, linewidth=1)
    axes[1].set(yscale="log", ylabel="Mine-only (s)", title="(b) Median và min–max")
    axes[1].legend(frameon=False, fontsize=7)
    for axis in axes[:2]:
        axis.set_xticks(positions, ticks)
        axis.set_xlabel("Minsup (%)")
    distribution = [int(x["itemsets"]) for x in lengths if float(x["minsup"]) == 0.05]
    axes[2].bar(range(1, 7), distribution, color="#315a86")
    axes[2].set(xlabel="Độ dài itemset", ylabel="Số itemset", title="(c) Phân bố tại minsup 5%", xticks=range(1, 7))
    for axis in axes:
        axis.grid(axis="y", alpha=0.2)
        axis.set_axisbelow(True)
    target = ROOT / "reports/figures/fashion/colab_mining.pdf"
    fig.savefig(target)
    plt.close(fig)
    print("PASS: 60 timings, summaries, length counts and class totals; wrote", target)


if __name__ == "__main__":
    main()
