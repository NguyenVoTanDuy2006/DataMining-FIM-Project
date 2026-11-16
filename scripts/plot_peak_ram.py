"""Validate raw process peaks, then create the Peak RAM figure and report."""

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


def write_report(summary, runs, output_dir):
    lines = [
        "# Peak RAM: Eclat baseline và optimized", "",
        "Đối chiếu yêu cầu tại [đề bài](https://hcmus-cs-ta.github.io/lab-book/data-mining/projects/itemset/) "
        "và `docs/itemset.md`: đo RAM tối đa cho mỗi dataset tại minsup trung bình, so sánh bản cơ bản và tối ưu.", "",
        "## Phương pháp", "",
        f"- Dùng toàn bộ giao dịch của {len(summary)} dataset FIMI đã chọn, cùng file chuẩn hóa và minsup cho Set/BitVector; giữ các giỏ trùng. "
        "Retail và T10I4D100K cộng 1 vào ID. Phiên bản Mushroom này có 8.124 giao dịch; "
        "không gộp với bộ 8.416 giao dịch trong thí nghiệm TV1.",
        "- Minsup trung bình được định nghĩa là điểm thứ 4 trong dải 7 điểm đã pilot, "
        "không phải trung bình cộng hai đầu dải. Retail 4%, Chess 87,5%, Mushroom 70%, T10I4D100K 1,5%.",
        "- Mỗi mẫu tạo một tiến trình Julia mới, chỉ chạy một backend, một luồng. "
        "Warm-up backend trên cùng một toy database rồi GC; đọc dữ liệu thật rồi GC trước `mine`. "
        "Đảo thứ tự Set/BitVector giữa các lần; báo cáo median của các peak cùng khoảng min–max quan sát.",
        "- Đọc `Sys.maxrss()` ngay sau `mine`, khi input/output còn sống, trước khi sort/ghi output. "
        "Đây là high-water mark do hệ điều hành ghi nhận, đơn vị byte; MiB = byte / 1024². "
        "Trên Windows tương ứng PeakWorkingSetSize qua GetProcessMemoryInfo. Không dùng `@allocated` "
        "hay tổng kích thước object để thay peak RSS.",
        "- Phạm vi gồm khởi động Julia, package/JIT, toy warm-up, đọc input và mining tới lúc lấy số đo. "
        "Peak của tiến trình không reset được sau warm-up. Cột `pre_mine_peak_rss_bytes` chỉ dùng chẩn đoán; "
        "không trừ nó để gọi phần chênh là peak RAM riêng của thuật toán.",
        f"- {len(runs)} mẫu đều so sánh toàn bộ itemset và support với tham chiếu SPMF được tạo mới "
        "từ đúng file chuẩn hóa trước thí nghiệm. Không dùng lại tham chiếu cũ có thể khác mapping ID. "
        "Vì cả hai backend đều bằng tham chiếu này, chúng cũng bằng nhau hoàn toàn. "
        "SPMF không được đo RAM trong thí nghiệm này.", "",
        "## Kết quả", "",
        "| Dataset | Minsup | Giao dịch | Itemsets | Set median MiB [min–max] | BitVector median MiB [min–max] | Giảm RAM (%) |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for r in summary:
        lines.append(
            f"| {r['dataset']} | {100 * float(r['minsup']):g}% | {r['n_transactions']} | {r['n_itemsets']} | "
            f"{float(r['baseline_median_mib']):.2f} [{float(r['baseline_min_mib']):.2f}–{float(r['baseline_max_mib']):.2f}] | "
            f"{float(r['optimized_median_mib']):.2f} [{float(r['optimized_min_mib']):.2f}–{float(r['optimized_max_mib']):.2f}] | "
            f"{float(r['reduction_percent']):+.2f} |"
        )
    lines += ["", "Giảm RAM = 100 × (1 − median BitVector / median Set). Giá trị âm nghĩa là optimized dùng nhiều RAM hơn.", "",
              "![Peak RAM baseline và optimized](peak_ram.png)", "", "## Phân tích và giới hạn", ""]
    for r in summary:
        change = float(r["reduction_percent"])
        direction = "thấp hơn" if change >= 0 else "cao hơn"
        lines.append(f"- {r['dataset']}: median peak của BitVector {direction} Set {abs(change):.2f}% "
                     "trong cấu hình này. Đây là so sánh peak của cả tiến trình tới hết mining.")
    lines += [
        "- Diễn giải từ cấu trúc code: mỗi BitVector cần khoảng N bit. Nếu cấp phát trước khi lọc "
        "singleton, cả item hiếm cũng chiếm một vector đầy đủ; lọc support trước sẽ tránh chi phí đó. "
        "Set lưu các TID có mặt nhưng chịu overhead bảng băm. Chi phí BitVector còn phụ thuộc số item "
        "được giữ lại và mật độ TID-set, nên dữ liệu thưa không đồng nghĩa với luôn tốn RAM hơn. Ngoài biểu diễn dọc, "
        "peak còn chịu input, output, giao ứng viên, GC, allocator và JIT; chưa tách được đóng góp từng phần.",
        "- Khoảng min–max phản ánh dao động quan sát, không phải khoảng tin cậy. "
        "Một backend được đặt tên optimized không đảm bảo giảm RAM trên mọi dataset. "
        "Không suy rộng kết luận sang ngưỡng support khác hoặc coi số này là peak riêng của hàm `mine`.",
        "- Thí nghiệm này hoàn thành phép so sánh bộ nhớ tại minsup trung bình; "
        "không thay thế scalability hoặc thí nghiệm thay đổi độ dài giao dịch.", "",
        "## Dữ liệu và chạy lại", "",
        "- [runs.csv](runs.csv): từng peak OS tính bằng byte, peak trước mining, số itemset và trạng thái kiểm chứng.",
        "- [summary.csv](summary.csv): median/min/max theo MiB, tỉ số và phần trăm giảm.",
        "- [metadata.md](metadata.md): máy, Julia/Java, quy trình, checksum dữ liệu/JAR/tham chiếu/core/runner.",
        "- `spmf/`: tham chiếu SPMF mới ở đúng minsup và mapping ID đã đo.",
        "- `peak_ram.svg`: bản vector để đưa vào báo cáo.", "",
        "```powershell",
        "julia --startup-file=no --project=. scripts/benchmark_peak_ram.jl",
        "python scripts/plot_peak_ram.py", "```", "",
        "Julia không cần package đo RAM bên ngoài; Java và `data/benchmark/tools/spmf.jar` dùng "
        "để tạo tham chiếu correctness ngoài phép đo RAM; Python cần matplotlib để vẽ. "
        "Nếu đã có kết quả, chọn thư mục mới bằng `--output-dir`; runner từ chối ghi đè. "
        "Script vẽ nhận đường dẫn thư mục kết quả làm đối số tùy chọn.", "",
        "Nguồn định nghĩa metric: [Julia Sys.maxrss](https://docs.julialang.org/en/v1/base/base/#Base.Sys.maxrss), "
        "[Windows PROCESS_MEMORY_COUNTERS](https://learn.microsoft.com/en-us/windows/win32/api/psapi/ns-psapi-process_memory_counters).",
    ]
    (output_dir / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    output_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else PROJECT_DIR / "results/benchmarks/peak_ram"
    summary, runs = read_csv(output_dir / "summary.csv"), read_csv(output_dir / "runs.csv")
    validate(summary, runs)
    plot_results(summary, output_dir)
    write_report(summary, runs, output_dir)
    print(f"Validated {len(summary)} datasets / {len(runs)} process peaks. Report: {output_dir / 'report.md'}")


if __name__ == "__main__":
    main()
