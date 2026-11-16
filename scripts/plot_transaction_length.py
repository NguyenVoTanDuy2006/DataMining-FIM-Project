"""Read and validate the synthetic-length CSV experiment, then draw figures."""

import csv
from collections import defaultdict
from math import ceil, isclose, isfinite
from pathlib import Path
from statistics import median
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

PROJECT_DIR = Path(__file__).resolve().parents[1]
MEASUREMENT = "mine_after_full_database_warmup"
BACKENDS = ("set", "bitvector")


def read_csv(path):
    with path.open(encoding="utf-8", newline="") as stream:
        return list(csv.DictReader(stream))


def validate(summary, runs):
    if not summary or not runs:
        raise ValueError("Thiếu dữ liệu benchmark")
    lengths = sorted({int(r["transaction_length"]) for r in summary})
    expected = {(l, b) for l in lengths for b in BACKENDS}
    if len(summary) != len(expected):
        raise ValueError("Thiếu hoặc trùng cấu hình")
    groups = defaultdict(list)
    for row in runs:
        if row["dataset"] != "synthetic" or row["measurement"] != MEASUREMENT or int(row["julia_threads"]) != 1:
            raise ValueError("Sai phạm vi đo")
        if row["status"] != "ok" or row["exact_match"] != "true" or row["spmf_match"] != "true":
            raise ValueError("Mẫu thất bại hoặc chưa kiểm chứng")
        elapsed = float(row["mining_seconds"])
        if not isfinite(elapsed) or elapsed <= 0:
            raise ValueError("Thời gian không hợp lệ")
        groups[int(row["transaction_length"]), row["backend"]].append(row)
    keys, settings, itemset_counts = set(), set(), {}
    for row in summary:
        l, backend = int(row["transaction_length"]), row["backend"]
        key = l, backend
        if key not in expected or key in keys:
            raise ValueError("Cấu hình không hợp lệ")
        keys.add(key)
        n, m, n_runs = int(row["n_transactions"]), int(row["n_items"]), int(row["n_runs"])
        minsup = float(row["minsup"])
        if n <= 0 or m <= 0 or n_runs <= 0 or not 1 <= l <= m:
            raise ValueError("Sai kích thước thiết kế")
        if int(row["observed_items"]) != m or int(row["total_occurrences"]) != n * l or float(row["mean_length"]) != l:
            raise ValueError("Số item, số lần xuất hiện hoặc độ dài không đúng thiết kế")
        density = float(row["density"])
        if not isfinite(density) or not isclose(density, l / m, rel_tol=1e-12):
            raise ValueError("Sai mật độ")
        if not isfinite(minsup) or not 0 < minsup <= 1 or int(row["min_count"]) != ceil(minsup * n):
            raise ValueError("Sai ngưỡng support")
        settings.add((n, m, minsup, n_runs))
        if row["dataset"] != "synthetic" or row["measurement"] != MEASUREMENT or row["exact_match"] != "true" or row["spmf_match"] != "true":
            raise ValueError("Bảng tổng hợp chưa kiểm chứng")
        count = int(row["n_itemsets"])
        if count < 0 or (l in itemset_counts and itemset_counts[l] != count):
            raise ValueError("Số itemset hai backend khác nhau")
        itemset_counts[l] = count
        samples = groups[key]
        if len(samples) != n_runs or {int(s["run_id"]) for s in samples} != set(range(1, n_runs + 1)):
            raise ValueError("Thiếu hoặc trùng lần đo")
        for sample in samples:
            for field in ("n_transactions", "n_items", "observed_items", "mean_length", "total_occurrences",
                          "density", "minsup", "min_count", "n_itemsets"):
                if sample[field] != row[field]:
                    raise ValueError(f"Mẫu không khớp {field}")
            first = "set" if int(sample["run_id"]) % 2 else "bitvector"
            if int(sample["order_in_pair"]) != (1 if backend == first else 2):
                raise ValueError("Không đảo thứ tự backend")
        times = [float(s["mining_seconds"]) for s in samples]
        for field, value in (("median_seconds", median(times)), ("min_seconds", min(times)),
                             ("max_seconds", max(times)), ("transactions_per_second", n / median(times))):
            actual = float(row[field])
            if not isfinite(actual) or actual <= 0 or not isclose(actual, value, rel_tol=1e-10, abs_tol=1e-12):
                raise ValueError(f"Sai giá trị tổng hợp {field}")
    if set(groups) != expected or keys != expected or len(settings) != 1:
        raise ValueError("Không giữ cố định N, M, minsup hoặc số lần đo")
    if any(itemset_counts[a] > itemset_counts[b] for a, b in zip(lengths, lengths[1:])):
        raise ValueError("Số itemset giảm dù giao dịch được mở rộng theo quan hệ lồng nhau")


def backend_rows(summary, backend):
    return sorted((r for r in summary if r["backend"] == backend), key=lambda r: int(r["transaction_length"]))


def plot_results(summary, output_dir):
    figure, axes = plt.subplots(1, 2, figsize=(12, 4.8), layout="constrained")
    for backend, label, color in (("set", "Set — baseline", "#3977a8"),
                                  ("bitvector", "BitVector — optimized", "#279b82")):
        rows = backend_rows(summary, backend)
        x = [float(r["mean_length"]) for r in rows]
        y = [1000 * float(r["median_seconds"]) for r in rows]
        errors = [[v - 1000 * float(r["min_seconds"]) for r, v in zip(rows, y)],
                  [1000 * float(r["max_seconds"]) - v for r, v in zip(rows, y)]]
        axes[0].errorbar(x, y, yerr=errors, marker="o", capsize=4, label=label, color=color)
    rows = backend_rows(summary, "set")
    x = [float(r["mean_length"]) for r in rows]
    axes[1].plot(x, [int(r["n_itemsets"]) for r in rows], marker="o", color="#8056a3", label="Hai backend khớp SPMF")
    axes[0].set_yscale("log")
    axes[0].set_ylabel("Thời gian mine (ms, thang log)")
    axes[0].set_title("Runtime sau warm-up — median và min–max")
    axes[1].set_ylabel("Số frequent itemsets")
    axes[1].set_ylim(bottom=0)
    axes[1].set_title("Output size theo độ dài giao dịch")
    for axis in axes:
        axis.set_xlabel("Độ dài giao dịch trung bình (item/giỏ)")
        axis.set_xticks(x)
        axis.grid(alpha=0.2)
        axis.legend(fontsize=8)
    for extension in ("png", "svg"):
        path = output_dir / f"transaction_length.{extension}"
        figure.savefig(path, dpi=240, bbox_inches="tight")
        if extension == "svg":
            path.write_text("\n".join(line.rstrip() for line in path.read_text(encoding="utf-8").splitlines()) + "\n", encoding="utf-8")
    plt.close(figure)


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    output_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else PROJECT_DIR / "results/benchmarks/transaction_length"
    summary, runs = read_csv(output_dir / "summary.csv"), read_csv(output_dir / "runs.csv")
    validate(summary, runs)
    plot_results(summary, output_dir)
    print(f"Đã kiểm chứng {len(summary)} cấu hình / {len(runs)} mẫu. Biểu đồ: {output_dir}")


if __name__ == "__main__":
    main()
