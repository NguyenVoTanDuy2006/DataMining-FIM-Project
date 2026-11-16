"""Kiểm tra CSV, vẽ biểu đồ và tạo báo cáo phép đo toàn bộ tiến trình."""

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
        ratio = float(row["julia_median_seconds"]) / float(row["spmf_median_seconds"])
        assert abs(ratio - float(row["julia_over_spmf"])) < 1e-10, row
    assert set(groups) == expected_keys
    assert len(runs) == sum(2 * int(row["n_runs"]) for row in summary)


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
    count_fig.suptitle("Output size versus minimum support\nJulia and SPMF itemsets/support counts match exactly")
    for figure, stem in ((fig, "runtime_processes"), (count_fig, "itemset_counts")):
        figure.savefig(output_dir / f"{stem}.png", dpi=240)
        figure.savefig(output_dir / f"{stem}.svg")
        plt.close(figure)


def write_report(summary, runs, output_dir):
    # Chỉ kết luận trong phạm vi đã đo; không gọi đây là tốc độ thuần của thuật toán.
    lines = [
        "# Báo cáo runtime Julia baseline và SPMF",
        "",
        f"Đã chạy {len(summary)} cấu hình và ghi nhận {len(runs)} lần đo. "
        "Mọi lần đo đều được đối chiếu toàn bộ itemset và support count giữa hai chương trình.",
        "",
        "## Cách đo",
        "",
        "Mỗi mẫu tạo tiến trình mới, tính khởi động Julia/Java, nạp package/lớp, JIT, "
        "đọc đầu vào, dựng TID-set, khai thác và ghi kết quả/log. Hai bên dùng cùng file đã chuẩn hóa "
        "và cùng minsup. Mỗi cấu hình có một lượt chuẩn bị mỗi backend không ghi nhận, "
        "sau đó đo lặp; lượt đo vẫn là tiến trình mới và vẫn tính JIT. Thứ tự hai backend đảo "
        "giữa các lần. Chuẩn hóa dữ liệu và so sánh kết quả thực hiện ngoài đồng hồ.",
        "",
        "Các số này là thời gian toàn bộ tiến trình. Không ghép trực tiếp với các CSV "
        "`*_baseline.csv` trước đó vốn đo riêng `mine` trên dữ liệu trong RAM sau warm-up. "
        "Các lần chạy dùng cache hệ điều hành có sẵn; không phải thí nghiệm cold disk cache. "
        "Các tiến trình nền của Windows không được kiểm soát hoàn toàn.",
        "",
        "Cấu hình máy, phiên bản Java/Julia và checksum nằm trong [metadata.md](metadata.md). "
        "SPMF được nhận diện bằng SHA-256 của JAR; nhãn ECLAT v2.65 trong log không được dùng "
        "để suy ra phiên bản toàn bộ thư viện.",
        "",
        "Mã chạy lại nằm trong `scripts/` của dự án. Metadata chỉ lưu checksum mã tại thời điểm đo; "
        "checksum có thể khác nếu sửa script sau lần đo.",
        "",
        "## Kết quả tại minsup thấp nhất của mỗi bộ",
        "",
        "| Dataset | Minsup | Itemset | Julia median (s) | SPMF median (s) | Julia/SPMF |",
        "| --- | ---: | ---: | ---: | ---: | ---: |",
    ]
    for dataset in DATASET_ORDER:
        rows = [r for r in summary if r["dataset"] == dataset]
        if not rows:
            continue
        row = min(rows, key=lambda r: float(r["minsup"]))
        lines.append(
            f"| {dataset} | {float(row['minsup']):g} | {row['n_itemsets']} | "
            f"{float(row['julia_median_seconds']):.4f} | "
            f"{float(row['spmf_median_seconds']):.4f} | {float(row['julia_over_spmf']):.2f} |"
        )
    n_spmf_faster = sum(float(r["julia_over_spmf"]) > 1 for r in summary)
    lines.extend([
        "",
        f"SPMF có median toàn bộ tiến trình thấp hơn tại {n_spmf_faster}/{len(summary)} cấu hình. "
        "Tỉ số Julia/SPMF lớn hơn 1 nghĩa là Julia mất nhiều thời gian hơn trong phép đo này.",
        "",
        "## Phân tích và giới hạn",
        "",
        "- Khi minsup giảm, số itemset tăng hoặc giữ nguyên. Output lớn hơn tạo thêm việc "
        "giao TID-set, duyệt nhánh, cấp phát và ghi file. Runtime thực tế còn chịu chi phí "
        "khởi động, JIT, GC và dao động hệ thống, nên không bắt buộc tăng tại mọi điểm.",
        "- Dense/sparse là một yếu tố, nhưng không thể dùng riêng số giao dịch hoặc số itemset "
        "để giải thích hết runtime. Chi phí giao Set còn phụ thuộc kích thước TID-set và số ứng viên.",
        "- Không suy ra ngôn ngữ hay thuật toán nào luôn nhanh hơn từ phép đo này. Chưa có "
        "phép đo kernel Julia và Java cùng warm-up trong tiến trình lâu dài; chưa tách riêng "
        "thời gian I/O/JIT. Khoảng min-max trên hình là độ dao động quan sát, không phải khoảng tin cậy.",
        "- Correctness xác nhận trên các dữ liệu và ngưỡng đã chạy; không thay thế kiểm thử "
        "tổng quát và không chứng minh backend chưa được cài đặt.",
        "",
        "## Bảng đầy đủ",
        "",
        "| Dataset | Minsup | Itemset | Julia median (s) | SPMF median (s) | Julia/SPMF | Khớp |",
        "| --- | ---: | ---: | ---: | ---: | ---: | --- |",
    ])
    for row in summary:
        lines.append(
            f"| {row['dataset']} | {float(row['minsup']):g} | {row['n_itemsets']} | "
            f"{float(row['julia_median_seconds']):.4f} | "
            f"{float(row['spmf_median_seconds']):.4f} | "
            f"{float(row['julia_over_spmf']):.2f} | {row['exact_match']} |"
        )
    lines.extend([
        "",
        "## Biểu đồ và dữ liệu gốc",
        "",
        "![Runtime toàn bộ tiến trình](runtime_processes.png)",
        "",
        "![Số itemset](itemset_counts.png)",
        "",
        "- [summary.csv](summary.csv): median/min/max và tỉ số từng cấu hình.",
        "- [runs.csv](runs.csv): từng mẫu thời gian và kết quả đối chiếu.",
        "- Có thêm bản SVG để dùng trong báo cáo.",
        "",
        "## Phần Lab 2 còn lại",
        "",
        "- Backend BitVector của TV1 chưa có, nên chưa so sánh baseline với optimized.",
        "- Chưa đo peak RSS cho baseline/optimized tại minsup trung bình. "
        "Không dùng số allocation hoặc thống kê memory nội bộ Java thay thế peak RSS.",
        "- Chưa đo scalability Retail 10%, 25%, 50%, 75%, 100%.",
        "- Chưa chạy thí nghiệm tổng hợp thay đổi độ dài giao dịch.",
        "- Hướng tối ưu đề xuất để đánh giá tiếp: giao tidset bằng BitVector/popcount khi phù hợp; "
        "sắp xếp nhánh theo support và giảm các bản sao/cấp phát Set. Chưa có bằng chứng "
        "thực nghiệm trong lần đo này rằng các thay đổi đó chắc chắn nhanh hơn.",
        "",
        "## Chạy lại",
        "",
        "Tại thư mục dự án, chạy tuần tự:",
        "",
        "```powershell",
        "julia --startup-file=no --project=. scripts/benchmark_processes.jl",
        "python scripts/plot_process_benchmarks.py",
        "```",
        "",
        "Python cần matplotlib cho bước vẽ; khai thác và đo thời gian dùng Julia/Java. "
        "Lệnh đo mặc định ghi đè runs.csv, summary.csv và metadata của lần đo trước trong "
        "thư mục processes; dùng --output-dir để giữ một lần đo riêng.",
    ])
    (output_dir / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


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
    write_report(summary, runs, output_dir)
    print(f"Đã kiểm tra {len(summary)} cấu hình, {len(runs)} mẫu; median khớp CSV gốc.")
    print(f"Đã tạo biểu đồ và báo cáo: {output_dir / 'report.md'}")


if __name__ == "__main__":
    main()
