"""Đọc, kiểm tra CSV và vẽ biểu đồ phép đo toàn bộ tiến trình."""

import csv
from collections import defaultdict
from pathlib import Path
from statistics import median
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter


PROJECT_DIR = Path(__file__).resolve().parents[1]
DATASET_ORDER = ("retail", "chess", "mushroom", "T10I4D100K")


def read_csv(path):
    with path.open(encoding="utf-8", newline="") as stream:
        return list(csv.DictReader(stream))


def validate(summary, runs):
    # Tính median độc lập từ CSV gốc, không tin ngay bảng tổng hợp.
    groups = defaultdict(list)
    for row in runs:
        assert row["exact_match"] == "true", row
        assert row["measurement"] == "end_to_end_fresh_process", row
        key = (row["dataset"], float(row["minsup"]), row["backend"])
        groups[key].append(row)

    expected_keys = set()
    summary_keys = set()
    for row in summary:
        assert row["exact_match"] == "true", row
        dataset, minsup = row["dataset"], float(row["minsup"])
        assert (dataset, minsup) not in summary_keys, row
        summary_keys.add((dataset, minsup))
        for backend, field in (
            ("julia_set", "julia_median_seconds"),
            ("julia_bitvector", "optimized_median_seconds"),
            ("spmf_eclat", "spmf_median_seconds"),
        ):
            key = (dataset, minsup, backend)
            expected_keys.add(key)
            samples = groups[key]
            assert len(samples) == int(row["n_runs"]), key
            assert {int(s["run_id"]) for s in samples} == set(
                range(1, int(row["n_runs"]) + 1)
            ), key
            assert all(s["n_itemsets"] == row["n_itemsets"] for s in samples), key
            measured = [float(s["runtime_seconds"]) for s in samples]
            assert all(t > 0 for t in measured), key
            assert abs(median(measured) - float(row[field])) < 1e-10, key
            prefix = field.removesuffix("_median_seconds")
            assert abs(min(measured) - float(row[f"{prefix}_min_seconds"])) < 1e-10, key
            assert abs(max(measured) - float(row[f"{prefix}_max_seconds"])) < 1e-10, key
        ratio = float(row["julia_median_seconds"]) / float(row["spmf_median_seconds"])
        assert abs(ratio - float(row["julia_over_spmf"])) < 1e-10, row
        optimized = float(row["optimized_median_seconds"])
        assert abs(optimized / float(row["spmf_median_seconds"]) - float(row["optimized_over_spmf"])) < 1e-10, row
        assert abs(float(row["julia_median_seconds"]) / optimized - float(row["set_over_optimized"])) < 1e-10, row
    assert set(groups) == expected_keys
    assert len(runs) == sum(3 * int(row["n_runs"]) for row in summary)


def plot_results(summary, output_dir):
    fig, axes = plt.subplots(2, 2, figsize=(12, 8), constrained_layout=True)
    count_fig, count_axes = plt.subplots(2, 2, figsize=(12, 8), constrained_layout=True)
    for dataset, ax, count_ax in zip(DATASET_ORDER, axes.flat, count_axes.flat):
        rows = sorted(
            (r for r in summary if r["dataset"] == dataset),
            key=lambda r: float(r["minsup"]),
            reverse=True,
        )
        if not rows:
            ax.set_visible(False)
            count_ax.set_visible(False)
            continue
        x = [100 * float(r["minsup"]) for r in rows]
        for prefix, label, color in (
            ("julia", "Julia Set baseline", "#1f77b4"),
            ("optimized", "Julia BitVector optimized", "#2b8c45"),
            ("spmf", "SPMF Eclat", "#d95f02"),
        ):
            y = [float(r[f"{prefix}_median_seconds"]) for r in rows]
            low = [float(r[f"{prefix}_min_seconds"]) for r in rows]
            high = [float(r[f"{prefix}_max_seconds"]) for r in rows]
            ax.plot(x, y, "o-", color=color, label=label)
            ax.fill_between(x, low, high, color=color, alpha=0.14)
        ax.set(title=dataset, xlabel="Minimum support (%)", ylabel="Wall-clock time (s, log scale)")
        ax.invert_xaxis()
        ax.set_yscale("log")
        ax.yaxis.set_major_formatter(FuncFormatter(lambda value, _: f"{value:g}"))
        ax.yaxis.set_minor_formatter(FuncFormatter(lambda value, _: f"{value:g}"))
        ax.grid(True, alpha=0.25)
        ax.legend(fontsize=8)

        count_ax.plot(x, [int(r["n_itemsets"]) for r in rows], "o-", color="#2b8c45")
        count_ax.set(title=dataset, xlabel="Minimum support (%)", ylabel="Frequent itemsets")
        count_ax.invert_xaxis()
        count_ax.set_yscale("log")
        count_ax.grid(True, alpha=0.25)

    fig.suptitle("Fresh-process end-to-end runtime\nMedian; shaded band = min-max of recorded runs")
    count_fig.suptitle("Output size versus minimum support\nSet, BitVector and SPMF itemsets/support counts match exactly")
    for figure, stem in ((fig, "runtime_processes"), (count_fig, "itemset_counts")):
        figure.savefig(output_dir / f"{stem}.png", dpi=240)
        svg_path = output_dir / f"{stem}.svg"
        figure.savefig(svg_path)
        svg_path.write_text(
            "\n".join(line.rstrip() for line in svg_path.read_text(encoding="utf-8").splitlines()) + "\n",
            encoding="utf-8",
        )
        plt.close(figure)


def main():
    # Terminal Windows có thể mặc định cp1252, không in được tiếng Việt.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    output_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else (
        PROJECT_DIR / "results" / "benchmarks" / "processes"
    )
    summary = read_csv(output_dir / "summary.csv")
    runs = read_csv(output_dir / "runs.csv")
    validate(summary, runs)
    plot_results(summary, output_dir)
    print(f"Đã kiểm tra {len(summary)} cấu hình, {len(runs)} mẫu; median khớp CSV gốc.")
    print(f"Đã lưu biểu đồ tại: {output_dir}")


if __name__ == "__main__":
    main()
