"""Validate Retail scalability evidence, draw figures, and write a Vietnamese report."""

import csv
from collections import defaultdict
from math import ceil, isfinite, isclose
from pathlib import Path
from statistics import mean, median
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


def linear_fit(rows):
    x = [int(r["n_transactions"]) for r in rows]
    y = [float(r["median_seconds"]) for r in rows]
    x_mean, y_mean = mean(x), mean(y)
    slope = sum((a - x_mean) * (b - y_mean) for a, b in zip(x, y)) / sum((a - x_mean)**2 for a in x)
    intercept = y_mean - slope * x_mean
    residual = sum((b - (slope * a + intercept))**2 for a, b in zip(x, y))
    total = sum((b - y_mean)**2 for b in y)
    return slope, intercept, (1 - residual / total if total else None)


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


def write_report(summary, runs, output_dir):
    set_rows, bit_rows = backend_rows(summary, "set"), backend_rows(summary, "bitvector")
    minsup = float(set_rows[0]["minsup"])
    lines = ["# Scalability: Retail 10%, 25%, 50%, 75%, 100%", "",
        f"Đã đo {len(runs)} mẫu Julia trên năm kích thước Retail, cho cả Set và BitVector, "
        f"giữ minsup tương đối cố định ở {100 * minsup:g}%. Mọi output được đối chiếu toàn bộ itemset/support với SPMF.", "",
        "## Phương pháp", "",
        "- Retail đầy đủ có 88.162 giao dịch; cộng 1 vào ID để đáp ứng hợp đồng ID dương. "
        "Từ một hoán vị chỉ số dòng có seed cố định, lấy lần lượt floor(N × tỷ lệ) chỉ số đầu, "
        "rồi sắp lại theo thứ tự dòng gốc. Tập nhỏ nằm trong tập lớn. Giao dịch trùng vẫn giữ riêng. "
        "Seed, thuật toán chọn và checksum từng tập con/chỉ số nằm trong [metadata.md](metadata.md).",
        "- Mỗi mẫu tạo tiến trình Julia mới, một luồng; đọc tập con và warm-up mine một lần "
        "trên đúng tập con/cùng minsup. Sau GC, đo một lần mine bằng @elapsed. "
        "Không tính khởi động, đọc input, warm-up/JIT, GC trước đo, ghi output hoặc correctness. "
        "GC bên trong mine được tính. Thứ tự hai backend đảo giữa các lần.",
        "- Đây là wall-clock của hàm mine sau warm-up, khác phép đo toàn bộ tiến trình trong processes/. "
        "SPMF tạo tham chiếu ngoài phép đo, không được đặt lên cùng đường runtime với kernel Julia.",
        "- Giữ minsup tương đối nên min_count tăng theo số giao dịch. Số itemset có thể thay đổi do "
        "phân bố tập con và làm tròn support. Runtime không bắt buộc tăng tại mọi điểm.", "",
        "## Kết quả", "",
        "| Retail | Giao dịch | Min count | Itemsets | Set median ms [min–max] | BitVector median ms [min–max] | Set / BitVector |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for s, b in zip(set_rows, bit_rows):
        lines.append(f"| {s['percent']}% | {s['n_transactions']} | {s['min_count']} | {s['n_itemsets']} | "
            f"{1000 * float(s['median_seconds']):.3f} [{1000 * float(s['min_seconds']):.3f}–{1000 * float(s['max_seconds']):.3f}] | "
            f"{1000 * float(b['median_seconds']):.3f} [{1000 * float(b['min_seconds']):.3f}–{1000 * float(b['max_seconds']):.3f}] | "
            f"{float(s['median_seconds']) / float(b['median_seconds']):.2f} |")
    lines += ["", "Tỉ số Set / BitVector lớn hơn 1 nghĩa là Set mất nhiều thời gian hơn trong cấu hình tương ứng.", "",
        "![Scalability Retail](scalability.png)", "", "## Nhận xét về xu hướng", ""]
    n_factor = int(set_rows[-1]["n_transactions"]) / int(set_rows[0]["n_transactions"])
    lines.append(f"Số giao dịch ở mức 100% gấp {n_factor:.4f} lần mức 10%. Đường y = x ở hình chuẩn hóa "
                 "là tham chiếu tăng tỷ lệ thuận với N, không phải đường dự đoán bắt buộc của Eclat.")
    lines.append("")
    for backend, label in (("set", "Set"), ("bitvector", "BitVector")):
        rows = backend_rows(summary, backend)
        slope, intercept, r_squared = linear_fit(rows)
        growth = float(rows[-1]["median_seconds"]) / float(rows[0]["median_seconds"])
        relative_growth = growth / n_factor
        r_text = f"{r_squared:.4f}" if r_squared is not None else "không xác định"
        trend = ("Năm điểm phù hợp khá tốt với xu hướng tăng gần tuyến tính trong miền đo."
                 if r_squared is not None and r_squared >= 0.95 and slope > 0 else
                 "Năm điểm chưa cho thấy xu hướng tăng gần tuyến tính đủ rõ theo tiêu chí mô tả R² ≥ 0,95.")
        lines.append(f"- {label}: tỉ số median thời gian 100% / 10% = {growth:.3f}; "
                     f"tỉ số tăng thời gian / tăng số giao dịch = {relative_growth:.3f}. "
                     f"Khớp mô tả tuyến tính t = aN + b trên năm median: a = {slope:.8g} s/giao dịch, "
                     f"b = {intercept:.6f} s, R² = {r_text}. {trend}")
    lines += [
        "- Tỉ số tăng thời gian / tăng số giao dịch lớn hơn 1 nghĩa là thời gian tăng nhanh hơn "
        "tỷ lệ N khi xét hai mốc 10% và 100%. Khớp tốt với t = aN + b có hệ số chặn khác 0 "
        "không đồng nghĩa với tỷ lệ thuận t = aN; cần đọc cả đường chuẩn hóa và các số đo gốc.",
        "- Eclat còn phụ thuộc số item, support TID-set, số ứng viên và số frequent itemset. "
        "Vì vậy năm điểm trên chỉ mô tả miền đo ở minsup này; R² hoặc tỉ số thời gian không chứng minh "
        "độ phức tạp tuyến tính tổng quát. Độ lệch khỏi đường tỷ lệ thuận có thể đến từ cấu trúc tập con, "
        "cấp phát/GC, cache và dao động hệ thống; chưa tách riêng từng nguyên nhân.",
        "- Với Set, TID-set lớn hơn làm tăng chi phí dựng bảng băm và giao tập. Với BitVector, "
        "vector dài theo số giao dịch; bản hiện tại lọc singleton trước khi cấp vector. "
        "Các chi phí này tăng cùng N nhưng số nhánh/output cũng có thể thay đổi.",
        "- Đường thời gian dùng median; min–max chỉ là độ dao động quan sát, không phải khoảng tin cậy. "
        "Một hoán vị cố định giúp tái lập và lồng các tập con, nhưng chưa đánh giá độ nhạy trên nhiều seed.", "",
        "## Tệp kết quả và chạy lại", "",
        "- [runs.csv](runs.csv): từng thời gian mine và correctness.",
        "- [summary.csv](summary.csv): median/min/max và throughput theo cấu hình.",
        "- [metadata.md](metadata.md): phương pháp tiếng Việt, máy, phiên bản, seed và checksum.",
        "- `spmf/`: năm tham chiếu được tạo từ đúng các tập con.",
        "- `scalability.svg`: bản vector để đưa vào báo cáo.", "",
        "```powershell", "julia --startup-file=no --project=. scripts/benchmark_scalability.jl",
        "python scripts/plot_scalability.py", "```", "",
        "Runner từ chối ghi đè kết quả. Khi chạy lại, dùng --output-dir mới và truyền cùng thư mục "
        "cho script vẽ. Có thể chọn --runs, --minsup, --seed và --timeout-seconds; metadata ghi lại "
        "đúng các thiết lập. Python cần matplotlib; Julia dùng thư viện chuẩn và package cục bộ.", ""]
    (output_dir / "report.md").write_text("\n".join(lines), encoding="utf-8")


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    output_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else PROJECT_DIR / "results/benchmarks/scalability"
    summary, runs = read_csv(output_dir / "summary.csv"), read_csv(output_dir / "runs.csv")
    validate(summary, runs)
    plot_results(summary, output_dir)
    write_report(summary, runs, output_dir)
    print(f"Đã kiểm chứng {len(summary)} cấu hình / {len(runs)} mẫu. Báo cáo: {output_dir / 'report.md'}")


if __name__ == "__main__":
    main()
