"""Read and validate CSV process peaks, then draw the Peak RAM figure."""

import csv
from collections import defaultdict
from pathlib import Path
from math import ceil, isfinite
from statistics import median
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

MIB = 1024**2
PROJECT_DIR = Path(__file__).resolve().parents[1]
EXPECTED_MINSUPS = {"retail": 0.04, "chess": 0.875, "mushroom": 0.7, "T10I4D100K": 0.015}


def read_csv(path):
    with path.open(encoding="utf-8", newline="") as stream:
        return list(csv.DictReader(stream))


def validate(summary, runs):
    if not summary or not runs:
        raise ValueError("Empty or incomplete benchmark")
    groups = defaultdict(list)
    for row in runs:
        if row["status"] != "ok" or row["exact_match"] != "true" or row["spmf_match"] != "true":
            raise ValueError("Failed or unchecked sample")
        if row["backend"] not in ("set", "bitvector") or int(row["julia_threads"]) != 1:
            raise ValueError("Unexpected backend/threads")
        if not 0 < int(row["pre_mine_peak_rss_bytes"]) <= int(row["peak_rss_bytes"]):
            raise ValueError("Invalid OS peak counters")
        groups[row["dataset"], row["backend"]].append(row)

    expected_keys, datasets = set(), set()
    for row in summary:
        dataset = row["dataset"]
        if dataset not in EXPECTED_MINSUPS or dataset in datasets or float(row["minsup"]) != EXPECTED_MINSUPS[dataset]:
            raise ValueError("Duplicate dataset or incorrect middle minsup")
        datasets.add(dataset)
        if row["exact_match"] != "true" or row["spmf_match"] != "true":
            raise ValueError("Unchecked summary")
        n_runs, n_transactions = int(row["n_runs"]), int(row["n_transactions"])
        if n_runs <= 0 or n_transactions <= 0 or int(row["n_itemsets"]) < 0 or int(row["min_count"]) != ceil(float(row["minsup"]) * n_transactions):
            raise ValueError("Invalid benchmark settings")
        for field in ("baseline_median_mib", "optimized_median_mib", "baseline_min_mib",
                      "baseline_max_mib", "optimized_min_mib", "optimized_max_mib",
                      "optimized_over_baseline", "reduction_percent"):
            if not isfinite(float(row[field])):
                raise ValueError("Non-finite summary value")
        for backend, prefix in (("set", "baseline"), ("bitvector", "optimized")):
            key = dataset, backend
            expected_keys.add(key)
            samples = groups[key]
            if len(samples) != n_runs or {int(s["run_id"]) for s in samples} != set(range(1, n_runs + 1)):
                raise ValueError("Missing or repeated run")
            for sample in samples:
                for field in ("n_transactions", "min_count", "n_itemsets", "minsup"):
                    if sample[field] != row[field]:
                        raise ValueError(f"Inconsistent {field}")
                first_backend = "set" if int(sample["run_id"]) % 2 else "bitvector"
                if int(sample["order_in_pair"]) != (1 if backend == first_backend else 2):
                    raise ValueError("Backend order did not alternate")
            peaks = [int(s["peak_rss_bytes"]) / MIB for s in samples]
            for suffix, value in (("median", median(peaks)), ("min", min(peaks)), ("max", max(peaks))):
                if abs(float(row[f"{prefix}_{suffix}_mib"]) - value) > 1e-9:
                    raise ValueError(f"Summary {prefix} {suffix} does not match raw peaks")
        ratio = float(row["optimized_median_mib"]) / float(row["baseline_median_mib"])
        if abs(float(row["optimized_over_baseline"]) - ratio) > 1e-9:
            raise ValueError("Incorrect peak ratio")
        if abs(float(row["reduction_percent"]) - 100 * (1 - ratio)) > 1e-9:
            raise ValueError("Incorrect reduction percentage")
    if set(groups) != expected_keys:
        raise ValueError("Unexpected raw samples")


def plot_results(summary, output_dir):
    fig, ax = plt.subplots(figsize=(10, 5.5), layout="constrained")
    positions = list(range(len(summary)))
    for prefix, label, offset, color in (
        ("baseline", "Baseline (Set)", -0.19, "#3977a8"),
        ("optimized", "Optimized (BitVector)", 0.19, "#e18b35"),
    ):
        values = [float(r[f"{prefix}_median_mib"]) for r in summary]
        errors = [
            [v - float(r[f"{prefix}_min_mib"]) for r, v in zip(summary, values)],
            [float(r[f"{prefix}_max_mib"]) - v for r, v in zip(summary, values)],
        ]
        bars = ax.bar([p + offset for p in positions], values, width=0.36,
                      label=label, color=color, yerr=errors, capsize=4)
        ax.bar_label(bars, labels=[f"{v:.1f}" for v in values], padding=5, fontsize=9)
    ax.set_xticks(positions, [f"{r['dataset']}\nminsup={100 * float(r['minsup']):g}%" for r in summary])
    ax.set_ylabel("Process peak RSS (MiB)")
    ax.set_title("Peak RAM at middle minsup: baseline vs optimized")
    ax.set_ylim(bottom=0)
    ax.margins(y=0.22)
    ax.grid(axis="y", alpha=0.2)
    ax.set_axisbelow(True)
    ax.legend()
    fig.text(0.5, -0.025, "Median of fresh processes; whiskers: observed min–max. Includes Julia/JIT and input.",
             ha="center", fontsize=9)
    for extension in ("png", "svg"):
        fig.savefig(output_dir / f"peak_ram.{extension}", dpi=240, bbox_inches="tight")
    plt.close(fig)


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    output_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else PROJECT_DIR / "results/benchmarks/peak_ram"
    summary, runs = read_csv(output_dir / "summary.csv"), read_csv(output_dir / "runs.csv")
    validate(summary, runs)
    plot_results(summary, output_dir)
    print(f"Đã kiểm chứng {len(summary)} tập dữ liệu / {len(runs)} mẫu Peak RAM. Biểu đồ: {output_dir}")


if __name__ == "__main__":
    main()
