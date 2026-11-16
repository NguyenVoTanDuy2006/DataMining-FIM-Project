"""Read and validate Retail scalability CSV evidence, then draw figures."""

import csv
from collections import defaultdict
from math import ceil, isfinite, isclose
from pathlib import Path
from statistics import median
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

PROJECT_DIR = Path(__file__).resolve().parents[1]
PERCENTAGES = (10, 25, 50, 75, 100)
BACKENDS = ("set", "bitvector")
MEASUREMENT = "mine_after_full_subset_warmup"


def read_csv(path):
    with path.open(encoding="utf-8", newline="") as stream:
        return list(csv.DictReader(stream))


def validate(summary, runs):
    expected_keys = {(p, b) for p in PERCENTAGES for b in BACKENDS}
    if len(summary) != len(expected_keys) or not runs:
        raise ValueError("Thiếu kết quả của năm tập con và hai backend")
    groups = defaultdict(list)
    for row in runs:
        if row["status"] != "ok" or row["exact_match"] != "true" or row["spmf_match"] != "true":
            raise ValueError("Mẫu thất bại hoặc chưa kiểm chứng")
        if row["dataset"] != "retail" or row["measurement"] != MEASUREMENT or int(row["julia_threads"]) != 1:
            raise ValueError("Sai dữ liệu, phạm vi đo hoặc số luồng")
        elapsed = float(row["mining_seconds"])
        if not isfinite(elapsed) or elapsed <= 0:
            raise ValueError("Thời gian không hợp lệ")
        groups[int(row["percent"]), row["backend"]].append(row)

    keys, common_settings, counts = set(), set(), {}
    for row in summary:
        percent, backend = int(row["percent"]), row["backend"]
        key = percent, backend
        if key not in expected_keys or key in keys:
            raise ValueError("Cấu hình bị lặp hoặc không hợp lệ")
        keys.add(key)
        total, size, n_runs = int(row["n_total"]), int(row["n_transactions"]), int(row["n_runs"])
        minsup = float(row["minsup"])
        if total <= 0 or size != total * percent // 100 or size <= 0 or n_runs <= 0:
            raise ValueError("Sai kích thước tập con hoặc số lần đo")
        if not isfinite(minsup) or not 0 < minsup <= 1 or int(row["min_count"]) != ceil(size * minsup):
            raise ValueError("Sai ngưỡng support")
        if row["dataset"] != "retail" or row["measurement"] != MEASUREMENT or row["exact_match"] != "true" or row["spmf_match"] != "true":
            raise ValueError("Sai phạm vi hoặc correctness của bảng tổng hợp")
        common_settings.add((total, minsup, n_runs))
        count = int(row["n_itemsets"])
        if count < 0 or (percent in counts and counts[percent] != count):
            raise ValueError("Số itemset hai backend khác nhau")
        counts[percent] = count
        samples = groups[key]
        if len(samples) != n_runs or {int(s["run_id"]) for s in samples} != set(range(1, n_runs + 1)):
            raise ValueError("Thiếu hoặc trùng lần đo")
        for sample in samples:
            for field in ("dataset", "n_total", "n_transactions", "minsup", "min_count", "n_itemsets", "measurement"):
                if sample[field] != row[field]:
                    raise ValueError(f"Mẫu không khớp trường {field}")
            first = "set" if int(sample["run_id"]) % 2 else "bitvector"
            if int(sample["order_in_pair"]) != (1 if backend == first else 2):
                raise ValueError("Thứ tự backend không được đảo")
        times = [float(s["mining_seconds"]) for s in samples]
        for field, expected in (("median_seconds", median(times)), ("min_seconds", min(times)),
                                ("max_seconds", max(times)), ("transactions_per_second", size / median(times))):
            actual = float(row[field])
            if not isfinite(actual) or actual <= 0 or not isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-12):
                raise ValueError(f"Bảng tổng hợp sai {field}")
    if keys != expected_keys or set(groups) != expected_keys or len(common_settings) != 1:
        raise ValueError("Các cấu hình thiếu hoặc không giữ điều kiện chung")


def backend_rows(summary, backend):
    return sorted((r for r in summary if r["backend"] == backend), key=lambda r: int(r["percent"]))


def save_figure(figure, output_dir, stem):
    for extension in ("png", "svg"):
        path = output_dir / f"{stem}.{extension}"
        figure.savefig(path, dpi=240, bbox_inches="tight")
        if extension == "svg":
            # Matplotlib emits cosmetic trailing spaces in SVG path data.
            path.write_text("\n".join(line.rstrip() for line in path.read_text(encoding="utf-8").splitlines()) + "\n", encoding="utf-8")
    plt.close(figure)


def plot_results(summary, output_dir):
    figure, axes = plt.subplots(1, 2, figsize=(12, 4.8), layout="constrained")
    for backend, label, color in (("set", "Set — baseline", "#3977a8"),
                                  ("bitvector", "BitVector — optimized", "#279b82")):
        rows = backend_rows(summary, backend)
        x = [int(r["n_transactions"]) for r in rows]
        y = [1000 * float(r["median_seconds"]) for r in rows]
        errors = [[a - 1000 * float(r["min_seconds"]) for r, a in zip(rows, y)],
                  [1000 * float(r["max_seconds"]) - a for r, a in zip(rows, y)]]
        axes[0].errorbar(x, y, yerr=errors, marker="o", capsize=4, label=label, color=color)
        axes[1].plot([a / x[0] for a in x], [a / y[0] for a in y], marker="o", label=label, color=color)
    first = backend_rows(summary, "set")
    x = [int(r["n_transactions"]) for r in first]
    axes[0].set_xticks(x, [f"{r['percent']}%\n{r['n_transactions']}" for r in first])
    axes[0].set_xlabel("Tỷ lệ Retail và số giao dịch")
    axes[0].set_ylabel("Thời gian mine sau warm-up (ms)")
    axes[0].set_title("Scalability — median và min–max")
    factor = x[-1] / x[0]
    axes[1].plot([1, factor], [1, factor], linestyle="--", color="gray", label="Tham chiếu tuyến tính y = x")
    axes[1].set_xlabel("Số giao dịch / mức 10%")
    axes[1].set_ylabel("Thời gian / mức 10%")
    axes[1].set_title("Chuẩn hóa theo tập con 10%")
    for axis in axes:
        axis.set_ylim(bottom=0)
        axis.grid(alpha=0.2)
        axis.legend(fontsize=8)
    save_figure(figure, output_dir, "scalability")


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    output_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else PROJECT_DIR / "results/benchmarks/scalability"
    summary, runs = read_csv(output_dir / "summary.csv"), read_csv(output_dir / "runs.csv")
    validate(summary, runs)
    plot_results(summary, output_dir)
    print(f"Đã kiểm chứng {len(summary)} cấu hình / {len(runs)} mẫu. Biểu đồ: {output_dir}")


if __name__ == "__main__":
    main()
