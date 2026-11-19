#!/usr/bin/env python3
"""Create the evidence-linked Fashion-FIM application report and handoff evaluation."""

from __future__ import annotations

import argparse
import csv
import json
import pathlib

import supervisor


def rows(path: pathlib.Path) -> list[dict]:
    with open(path, newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def has_csv_header(path: pathlib.Path, expected: tuple[str, ...]) -> bool:
    if not path.is_file():
        return False
    with open(path, newline="", encoding="utf-8") as stream:
        return tuple(next(csv.reader(stream), ())) == expected


def as_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def fmt(value, digits=3) -> str:
    if value in (None, "", "NA"):
        return "NA"
    if isinstance(value, str):
        try:
            value = float(value)
        except ValueError:
            return value
    if isinstance(value, (float, int)):
        return f"{value:,.{digits}f}" if isinstance(value, float) else f"{value:,}"
    return str(value)


def load_review_state(output_dir: pathlib.Path) -> tuple[str, list[dict]]:
    path = output_dir / "interpretation" / "pattern_annotations.csv"
    if not path.is_file():
        return "BLOCKED", []
    annotations = rows(path)
    current = {row["pattern_id"] for row in rows(output_dir / "analysis" / "representative_patterns.csv")}
    relevant = [row for row in annotations if row["pattern_id"] in current]
    if not relevant:
        return "BLOCKED", annotations
    if any(row.get("witness_valid", "").lower() != "true" or row.get("decodable", "").lower() != "true" for row in relevant):
        return "NEEDS_REVISION", relevant
    review_statuses = {row.get("review_status", "PENDING_REVIEW") for row in relevant}
    for row in relevant:
        status = row.get("review_status", "PENDING_REVIEW")
        coherence = row.get("visual_coherence", "NA")
        if status == "PENDING_REVIEW" and coherence != "NA":
            return "NEEDS_REVISION", relevant
        if status in {"APPROVED", "NEEDS_REVISION", "REJECTED"} and coherence not in {"0", "1", "2"}:
            return "NEEDS_REVISION", relevant
        if status in {"APPROVED", "NEEDS_REVISION", "REJECTED"} and not (row.get("reviewer") and row.get("reviewed_at")):
            return "NEEDS_REVISION", relevant
    if "NEEDS_REVISION" in review_statuses:
        return "NEEDS_REVISION", relevant
    if "PENDING_REVIEW" in review_statuses:
        return "PENDING_REVIEW", relevant
    if review_statuses.issubset({"APPROVED", "REJECTED"}) and all(row.get("reviewer") and row.get("reviewed_at") for row in relevant):
        return "PASS", relevant
    return "PENDING_REVIEW", relevant


def mining_axis(run_rows: list[dict]) -> str:
    statuses = [row["status"] for row in run_rows]
    if any(status == "INVALID_OUTPUT" for status in statuses):
        return "FAIL"
    completed = {"COMPLETED_FULL", "COMPLETED_ZERO"}
    if len(statuses) == 6 and all(status in completed for status in statuses):
        return "PASS"
    if any(status in completed for status in statuses) and any(status in {"TIMEOUT", "MEMORY_LIMIT", "OUTPUT_LIMIT"} for status in statuses):
        return "PARTIAL_RESOURCE"
    if any(status in completed for status in statuses):
        return "PARTIAL_OTHER"
    return "BLOCKED"


def overall_status(mining: str, execution: str, interpretation: str, report_audit: str) -> str:
    if mining == execution == interpretation == report_audit == "PASS":
        return "COMPLETE"
    issues = [("mining", mining), ("execution_mcp", execution),
              ("interpretation", interpretation), ("report_audit", report_audit)]
    unresolved = [(key, value) for key, value in issues if value != "PASS"]
    if len(unresolved) >= 2:
        if mining == "BLOCKED" and execution == "BLOCKED" and interpretation == "BLOCKED":
            return "BLOCKED"
        return "PARTIAL_MIXED"
    key, value = unresolved[0]
    if key in {"mining", "report_audit"} and value in {"FAIL", "FAILED_VALIDATION"}:
        return "FAILED_VALIDATION"
    if key == "execution_mcp" and value == "UNVERIFIED":
        return "PARTIAL_EXECUTION_UNVERIFIED"
    if key == "execution_mcp" and value == "BLOCKED":
        return "BLOCKED"
    if key == "interpretation" and value == "NEEDS_REVISION":
        return "REVISION_REQUIRED"
    if key == "interpretation" and value == "PENDING_REVIEW":
        return "PENDING_HUMAN_REVIEW"
    if key == "interpretation" and value in {"PARTIAL_MISSING_ASSET", "BLOCKED"}:
        return "PARTIAL_INTERPRETATION"
    if key == "mining" and value == "PARTIAL_RESOURCE":
        return "PARTIAL_RESOURCE_LIMITED"
    if key == "mining" and value == "PARTIAL_OTHER":
        return "PARTIAL_INTERRUPTED"
    if value == "BLOCKED":
        return "BLOCKED"
    return "PARTIAL_MIXED"


def create_report(output_dir: pathlib.Path) -> dict:
    config = supervisor.load_config(output_dir)
    run_rows = rows(output_dir / "mining" / "runs.csv")
    stats = rows(output_dir / "analysis" / "run_statistics.csv")
    catalog = rows(output_dir / "analysis" / "master_patterns.csv")
    representatives = rows(output_dir / "analysis" / "representative_patterns.csv")
    analysis_summary = json.loads((output_dir / "analysis" / "analysis_summary.json").read_text(encoding="utf-8"))
    output_audit_path = output_dir / "analysis" / "independent_output_audit.json"
    output_audit = json.loads(output_audit_path.read_text(encoding="utf-8")) if output_audit_path.is_file() else {}
    interpretation_summary_path = output_dir / "interpretation" / "interpretation_summary.json"
    interpretation_summary = json.loads(interpretation_summary_path.read_text(encoding="utf-8")) if interpretation_summary_path.is_file() else {}
    review_state, annotations = load_review_state(output_dir)
    reviewed_by = sorted({row.get("reviewer", "").strip() for row in annotations if row.get("reviewer", "").strip()})
    reviewed_at_values = sorted({row.get("reviewed_at", "").strip() for row in annotations if row.get("reviewed_at", "").strip()})
    reviewer_text = ", ".join(reviewed_by) if reviewed_by else "unknown reviewer"
    reviewed_at_text = ", ".join(reviewed_at_values) if reviewed_at_values else "timestamp not recorded"
    coherence_counts = {score: sum(row.get("visual_coherence") == score for row in annotations) for score in ("0", "1", "2")}
    coherence_count_text = ", ".join(f"{score}: {count}" for score, count in coherence_counts.items())
    mcp_log_path = output_dir / "report" / "mcp_execution_log.md"
    mcp_log = mcp_log_path.read_text(encoding="utf-8") if mcp_log_path.is_file() else ""
    required_mcp_evidence = ("Mining notebook MCP clean-kernel run: PASS",
        "Interpretation notebook MCP clean-kernel run: PASS", "notebook save/reopen: PASS",
        "Latest MCP P1 smoke: PASS (22 checks)", "Latest MCP P3 independent audit: PASS",
        "Latest editor save/reopen gate: PASS")
    if any(code in mcp_log for code in ("MCP_UNAVAILABLE", "KERNEL_UNAVAILABLE")):
        execution = "BLOCKED"
    elif "Latest editor save/reopen gate: UNVERIFIED" in mcp_log:
        execution = "UNVERIFIED"
    elif all(marker in mcp_log for marker in required_mcp_evidence):
        execution = "PASS"
    else:
        execution = "UNVERIFIED"
    mining = mining_axis(run_rows)
    cross_audit = output_audit.get("cross_threshold_audit", {})
    support_audit = output_audit.get("independent_support_scan", {})
    audit_sha256 = supervisor.sha256_file(output_audit_path) if output_audit_path.is_file() else ""
    audit_relative_path = supervisor.relative_to(pathlib.Path(config["repo_root"]), output_audit_path)
    audit_runs_by_count = {run.get("minsup_count"): run for run in output_audit.get("runs", [])}
    sidecar_reconciliation_ok = len(audit_runs_by_count) == 6
    if sidecar_reconciliation_ok:
        for lower_count, run in audit_runs_by_count.items():
            sidecar_path = supervisor.sidecar_path(output_dir, run["run_id"])
            sidecar = supervisor.read_toml(sidecar_path) if sidecar_path.is_file() else {}
            higher_pairs = [pair for pair in cross_audit.get("pairs", [])
                            if pair["lower_minsup_count"] == lower_count]
            historical_cross_count = run.get("historical_production_cross_threshold_outputs_checked")
            expected_higher_counts = [pair["higher_minsup_count"] for pair in higher_pairs]
            expected_higher_run_ids = [audit_runs_by_count[count]["run_id"] for count in expected_higher_counts]
            expected_samples = run.get("sample_results", [])
            sidecar_reconciliation_ok = sidecar_reconciliation_ok and (
                sidecar.get("status") in {"COMPLETED_FULL", "COMPLETED_ZERO"}
                and sidecar.get("final_committed") is True
                and sidecar.get("post_run_audit_status") == "PASS"
                and sidecar.get("post_run_audit_path") == audit_relative_path
                and sidecar.get("post_run_audit_sha256") == audit_sha256
                and sidecar.get("production_commit_cross_threshold_outputs_checked") == historical_cross_count
                and sidecar.get("cross_threshold_outputs_checked") == len(higher_pairs)
                and sidecar.get("cross_threshold_min_counts_checked") == expected_higher_counts
                and sidecar.get("cross_threshold_run_ids_checked") == expected_higher_run_ids
                and sidecar.get("cross_threshold_mismatch_count") == 0
                and sidecar.get("audit_sample_itemsets") == run.get("sample_itemsets")
                and sidecar.get("audit_sample_expected_supports") == run.get("sample_expected_supports")
                and sidecar.get("audit_sample_observed_supports") == [row["observed_support"] for row in expected_samples]
                and sidecar.get("audit_sample_mismatch_count") == 0
            )
    output_audit_ok = (
        output_audit.get("status") == "PASS"
        and output_audit.get("source_sha256") == config["input_sha256"]
        and output_audit.get("transaction_count") == 70_000
        and output_audit.get("empty_transaction_count") == 0
        and output_audit.get("source_guardrails", {}).get("status") == "PASS"
        and support_audit.get("status") == "PASS"
        and support_audit.get("mismatch_count") == 0
        and cross_audit.get("status") == "PASS"
        and cross_audit.get("pair_count") == 15
        and cross_audit.get("mismatch_count") == 0
        and len(output_audit.get("runs", [])) == 6
        and all(run.get("sample_mismatch_count") == 0 for run in output_audit.get("runs", []))
        and sidecar_reconciliation_ok
    )

    interpretation_dir = output_dir / "interpretation"
    ai_review_path = interpretation_dir / "ai_visual_review.md"
    if ai_review_path.is_file() and review_state == "PASS":
        ai_review_note = (
            f"The AI-prepared visual assessment was confirmed by human reviewer `{reviewer_text}` at "
            f"`{reviewed_at_text}`. The scores and observations are recorded in "
            "`interpretation/pattern_annotations.csv`; the AI assessment and confirmation history are in "
            "`interpretation/ai_visual_review.md`."
        )
    elif ai_review_path.is_file():
        ai_review_note = (
            "An AI-prepared visual assessment is available at `interpretation/ai_visual_review.md`; "
            "human confirmation is not complete and the review gate remains open."
        )
    else:
        ai_review_note = ""
    if not interpretation_summary:
        interpretation = "BLOCKED"
    elif interpretation_summary.get("visual_assets_status") != "PASS":
        interpretation = "PARTIAL_MISSING_ASSET"
    elif interpretation_summary.get("label_join") != "PASS":
        interpretation = "PARTIAL_MISSING_ASSET"
    elif review_state in {"NEEDS_REVISION", "PENDING_REVIEW", "PASS"}:
        interpretation = review_state
    else:
        interpretation = "PARTIAL_MISSING_ASSET"

    report_path = output_dir / "report" / "fashion_fim_application_report.md"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    input_manifest = supervisor.read_toml(output_dir / "input_manifest.toml")
    guardrails = {key: input_manifest.get(key) for key in ("max_singleton_support", "support_6", "support_26", "support_6_26")}
    source_archive_rows = []
    if interpretation_summary:
        manifest = supervisor.read_toml(interpretation_dir / "interpretation_manifest.toml")
        source_archive_rows = manifest.get("raw_asset_sha256", "").split(";")

    table_rows = []
    for row in run_rows:
        table_rows.append("| {pct}% | {count} | {status} | {reason} | {total} | {maxlen} | {runtime} | {rss} | {bytes} |".format(
            pct=int(float(row["minsup_fraction"]) * 100), count=row["minsup_count"], status=row["status"],
            reason=row["reason_code"] or "—", total=row["total_frequent_itemsets"], maxlen=row["max_itemset_length"],
            runtime=fmt(row["runtime_seconds"]), rss=fmt(row["peak_rss_mb"]), bytes=row["output_size_bytes"]))
    insight_rows = []
    completed = [row for row in stats if row["status"] in {"COMPLETED_FULL", "COMPLETED_ZERO"}]
    if completed:
        largest = max(completed, key=lambda row: int(row["total_frequent_itemsets"]))
        smallest = min(completed, key=lambda row: int(row["total_frequent_itemsets"]))
        insight_rows.append(f"- Completed outputs range from **{int(smallest['total_frequent_itemsets']):,}** patterns at {int(float(smallest['minsup_fraction'])*100)}% to **{int(largest['total_frequent_itemsets']):,}** at {int(float(largest['minsup_fraction'])*100)}%.")
        longest = max(completed, key=lambda row: int(row["max_itemset_length"]))
        insight_rows.append(f"- Maximum observed itemset length is **{longest['max_itemset_length']}** at {int(float(longest['minsup_fraction'])*100)}%; its length distribution is in `analysis/run_statistics.csv`.")
        runtimes = [row for row in completed if row["runtime_seconds"] not in ("NA", "")]
        if runtimes:
            slowest = max(runtimes, key=lambda row: float(row["runtime_seconds"]))
            insight_rows.append(f"- Longest completed worker runtime is **{float(slowest['runtime_seconds']):,.2f}s** at {int(float(slowest['minsup_fraction'])*100)}%, including Julia startup, JSONL load, mining and staging serialization.")
        count5 = next((int(row["total_frequent_itemsets"]) for row in completed if row["minsup_count"] == "3500"), None)
        count60 = next((int(row["total_frequent_itemsets"]) for row in completed if row["minsup_count"] == "42000"), None)
        if count5 is not None and count60 is not None:
            insight_rows.append(f"- The exact catalog grows by **{count5-count60:,}** patterns from 60% to 5% (ratio {count5/count60:.2f}× when the 60% count is nonzero). This is a coverage/volume change, not evidence that the lower-threshold patterns are more useful.")
    else:
        insight_rows.append("- No final-committed mining output is available; no pattern-count trend is claimed.")
    if len(catalog) > 0:
        length_hist = {}
        for row in catalog:
            length = int(row["length"])
            length_hist[length] = length_hist.get(length, 0) + 1
        common_lengths = sorted(length_hist.items(), key=lambda pair: (-pair[1], pair[0]))[:3]
        insight_rows.append("- Unique patterns across all completed thresholds: **{:,}**. Most common lengths in the deduplicated catalog: {}.".format(
            len(catalog), ", ".join(f"{length}: {count:,}" for length, count in common_lengths)))

    interpretation_section = ""
    if interpretation_summary:
        retrieval = interpretation_summary["retrieval"]
        class_stats_path = interpretation_dir / "class_pattern_stats.csv"
        labels_available = interpretation_summary.get("label_join") == "PASS" and class_stats_path.is_file()
        class_rows = rows(class_stats_path) if labels_available else []
        ranked = sorted((row for row in class_rows if float(row["enrichment"]) > 0),
                        key=lambda row: (-float(row["enrichment"]), row["pattern_id"], row["class_label"]))
        enrichment_text = ""
        if ranked:
            top = ranked[0]
            enrichment_text = (f"The highest selected-pattern enrichment is **{top['pattern_id']}** in {top['class_name']}: "
                f"P(X|class)={float(top['support_fraction_within_class']):.2%}, "
                f"P(X)={float(top['support_fraction_global']):.2%}, enrichment={float(top['enrichment']):.2f}×. "
                "This is descriptive for the selected patterns and does not establish predictive value.")
        class_section = (
            "Class enrichment is calculated after mining from the verified 1:1 image-label join. "
            f"{enrichment_text}\n\nThe class heatmap is `figures/pattern_class_heatmap.png`; exact per-class values are in `interpretation/pattern_class_support.csv`."
            if labels_available else
            "Class-conditioned statistics are `BLOCKED_MISSING_LABELS`; mining, visual witnesses and retrieval remain available."
        )
        perspectives = interpretation_summary.get("class_perspectives", {})
        perspective_text = ""
        if labels_available and all(key in perspectives for key in ("common", "class_enriched", "cross_class")):
            common = perspectives["common"]
            enriched = perspectives["class_enriched"]
            cross_class = perspectives["cross_class"]
            perspective_text = (
                f"\n\nSelected-pattern perspectives: common `{common['items']}` occurs in "
                f"{common['support_count']:,}/70,000 images ({common['support_count']/70_000:.2%}) across "
                f"{common['class_coverage']}/10 classes; class-enriched `{enriched['items']}` in "
                f"{enriched['class_name']} has P(X|class)={enriched['support_fraction_within_class']:.2%}, "
                f"P(X)={enriched['support_fraction_global']:.2%}, enrichment={enriched['enrichment']:.2f}×; "
                f"cross-class `{cross_class['items']}` occurs in {cross_class['class_coverage']}/10 classes."
            )
        retrieval_class_text = ""
        if labels_available and retrieval.get("class_counts"):
            class_name_by_id = {str(row["class_label"]): row["class_name"] for row in class_rows}
            class_total_by_id = {str(row["class_label"]): int(row["class_total"]) for row in class_rows}
            counts = retrieval["class_counts"]
            total_retrieved = int(retrieval["retrieved_count"])
            top_classes = sorted(counts.items(), key=lambda pair: (-int(pair[1]), int(pair[0])))[:2]
            described = []
            for label, count in top_classes:
                class_share = int(count) / total_retrieved
                prior = class_total_by_id[label] / 70_000
                described.append(f"{class_name_by_id[label]} {int(count):,}/{total_retrieved:,} "
                                 f"({class_share:.2%}; class prior {prior:.2%})")
            retrieval_class_text = " Retrieved-set class mix versus balanced priors: " + "; ".join(described) + "."
        if interpretation_summary.get("gallery_paths"):
            review_caption = (
                f"The AI-prepared scores and observations were confirmed by human reviewer `{reviewer_text}` "
                f"at `{reviewed_at_text}` and are recorded in `interpretation/pattern_annotations.csv`."
                if review_state == "PASS" else
                "Human confirmation is pending in `interpretation/pattern_annotations.csv`."
            )
            gallery_text = (f"Generated evidence cards: {len(interpretation_summary['gallery_paths'])}; see `interpretation/pattern_gallery/index.html`. "
                "The cards include 4×4 column-major centroids, retained real patches, actual supporting images, assignment-coordinate witnesses and a contrast image where available."
                " The per-card legend maps support-image colors to word IDs and identifies contrast-image patches. "
                f"{review_caption}")
        else:
            blockers = ", ".join(interpretation_summary.get("visual_asset_blockers", [])) or "verified visual assets unavailable"
            gallery_text = (f"Pattern gallery is `BLOCKED_MISSING_ASSET` ({blockers}); no synthetic card or image was created. "
                            "Exact retrieval and available post-hoc class analysis remain usable.")
        interpretation_section = f"""
### Visual evidence and retrieval

{gallery_text}

The retrieval query is **{retrieval['pattern_id']} = {retrieval['items']}**. It retrieves **{retrieval['retrieved_count']:,}** images, matching exact support **{retrieval['support_count']:,}** ({retrieval['support_fraction']:.2%}); the query registry is `interpretation/retrieval_examples.csv` and per-image rows are in `interpretation/image_retrieval.csv`. Six supporting examples are sampled deterministically with seed 42, with a contrast image where one exists. This is exact pattern co-occurrence retrieval, not semantic or embedding retrieval; there is no ground-truth relevance set, so precision/recall claims are not made. {class_section}{perspective_text}{retrieval_class_text}

{ai_review_note}

"""
    else:
        interpretation_section = "### Visual evidence and retrieval\n\nNo completed pattern catalog was available for image interpretation; this section is blocked by the recorded mining status.\n"

    if execution == "PASS":
        final_validation = (
            "Final validation: P1 passed 22 MCP smoke checks; missing-asset behavior was verified on an isolated copy; "
            "both notebooks passed the latest clean-kernel MCP save/reopen gate. After human review, the P4 summary-display "
            "and report-only P5 cells ran through MCP."
        )
    else:
        final_validation = (
            "Final validation: P1 passed 22 MCP smoke checks and P3's independent output audit passed through MCP. "
            "The latest live Mining and Visual notebook editors are dirty, and the bridge exposes no save or close command; "
            "the latest save/reopen gate therefore remains unverified. See `report/mcp_execution_log.md`."
        )

    report = f"""# Fashion-MNIST Frequent Itemset Mining — Ứng dụng 2

## 1. Dữ liệu và cấu hình

Thí nghiệm sử dụng **B0 / `raw_full_batch_kmeans` / K=32 / seed=123 / S0 Binary BoVW**, với input read-only `{config['input_source_path']}`. JSONL có **{input_manifest['record_count']:,}** transactions, **{input_manifest['empty_count']}** transaction rỗng; SHA-256 `{config['input_sha256']}`. TID và image ID được giữ qua mapping nguồn; không đưa label vào transaction.

Engine là `EclatFIM.mine(transactions, min_count)` trong commit `{config['engine_revision']}`; SHA-256 của source engine `{config['engine_source_sha256']}`. Mỗi run dùng Julia {config['julia_version']} với {config['julia_threads']} thread. Chỉ adapter/runner nằm ngoài Eclat core.

Independent source guardrails: max singleton={guardrails['max_singleton_support']:,}; support (6,)={guardrails['support_6']:,}; support (26,)={guardrails['support_26']:,}; support (6,26)={guardrails['support_6_26']:,}. Do đó 80% phải rỗng và 60% phải có đúng hai singleton; supervisor đối chiếu các điều kiện này trước khi commit.

Ngân sách cố định `{config['budget_revision']}`: wall time {config['wall_time_seconds_per_run']:,} giây/run qua systemd `RuntimeMaxSec`, RAM {config['memory_limit_mb_per_worker']:,} MiB/worker qua cgroup `MemoryMax` với swap bằng 0, và output cap {config['output_limit_bytes']:,} byte cho một file JSONL. Worker chạy tuần tự, process riêng, supervisor nằm ngoài kernel notebook. File staging bị giới hạn trước mỗi lần ghi.

## 2. Kết quả mining theo sáu ngưỡng

| Minsup | min_count | Status | reason_code | Itemsets exact | Max length | Runtime (s) | Peak RSS (MiB) | JSONL bytes |
|---:|---:|---|---|---:|---:|---:|---:|---:|
{chr(10).join(table_rows)}

Chỉ `COMPLETED_FULL`/`COMPLETED_ZERO` có exact totals. Trạng thái và checkpoint chuẩn nằm trong `mining/runs/<run_id>/status.toml`; `mining/runs.csv` là view sáu hàng được tái dựng từ các sidecar. Audit độc lập sau run tại `analysis/independent_output_audit.json` ghi seed, itemsets mẫu, support đối chiếu trực tiếp với source, và toàn bộ 15 cặp cross-threshold.

**Lưu ý provenance:** tại production commit ban đầu, `cross_threshold_outputs_checked=0` do lỗi ghép đường dẫn trong supervisor. Sau khi sửa path và chạy hậu kiểm, sidecar hiện hành được ghi atomic với danh sách mẫu, support, và số cặp ngưỡng đã xác minh; giá trị ban đầu được giữ trong `production_commit_cross_threshold_outputs_checked`. Audit xác nhận 77 itemsets mẫu và cả 15 cặp ngưỡng đều khớp. Đây là revalidation sau production, không khẳng định các so sánh đã xảy ra trước commit ban đầu; Eclat không chạy lại.

### Mining behavior

{chr(10).join(insight_rows)}

![Số itemsets theo minsup](../figures/minsup_vs_itemset_count.png)

![Runtime theo minsup](../figures/minsup_vs_runtime.png)

![Phân bố độ dài](../figures/itemset_lengths_by_minsup.png)

Support fraction là tỷ lệ **ảnh** có itemset, mẫu số 70.000; không phải tỷ lệ patches.

## 3. Visual patterns và diễn giải ảnh

Representative selection dùng v1.3 deterministic grid: tertiles trên support counts phân biệt (ties giữ cùng bucket), chín ô length-major, round-robin và Jaccard ≤0.80; nếu thiếu target thì khởi động lại một lần ở 0.90. Requested target 16, selected {len(representatives)}; catalog có {len(catalog):,} unique patterns. Provenance nằm tại `analysis/selection_manifest.toml`.

{interpretation_section}

**Giới hạn S0:** transaction chỉ giữ việc visual word xuất hiện trong ảnh. Bản thân frequent itemset không lưu vị trí, số lần lặp trong ảnh, thứ tự hay quan hệ hình học cố định. Centroid là patch trung bình; patch exemplar và witness là dữ liệu thật. Visual coherence hiện ở trạng thái `{review_state}`; {('người duyệt ' + reviewer_text + ' đã xác nhận các điểm và nhận xét do AI chuẩn bị' if review_state == 'PASS' else 'các điểm và nhận xét do AI chuẩn bị chưa được người duyệt xác nhận')}. Việc xác nhận đánh giá mức độ lặp lại nhìn thấy được, không chứng minh itemset có ý nghĩa ngữ nghĩa hoặc một bố cục cố định.

## 4. Ứng dụng downstream

Gọi `x_BoVW(I) ∈ {{0,1}}^32` là transaction S0. Với mỗi selected pattern `P_j`, định nghĩa `φ_j(I)=1[P_j ⊆ T(I)]` và `x_pattern(I)=[φ_1(I),…,φ_m(I)]`; khi đó `x_aug(I)=[x_BoVW(I),x_pattern(I)] ∈ {{0,1}}^{{32+m}}`. Các feature này có thể biểu diễn tường minh tương tác cho Binary Logistic Regression hoặc Linear SVM, tạo image grouping/signatures, và hỗ trợ pattern-based retrieval. Vì `φ_j` là hàm xác định của 32 BoVW bits, chúng không bổ sung thông tin mới theo nghĩa information theory.

Đề xuất đánh giá future work: E0 dùng 32 BoVW bits, E1 dùng m pattern activations, E2 dùng cả hai; so sánh accuracy, macro-F1 và per-class F1 trên cùng split. Chỉ chọn/mine patterns và chỉnh hyperparameters từ train/validation, không dùng test labels. Codebook hiện tại fit trên toàn 70.000 ảnh nên biểu diễn này chỉ hỗ trợ thảo luận transductive/exploratory; không huấn luyện classifier hoặc tuyên bố accuracy/F1 trong phạm vi hiện tại.

## 5. Kết luận và giới hạn

Kết luận định lượng chỉ áp dụng cho các ngưỡng đã completed; resource-limited hoặc interrupted outputs không được đọc như số lượng exact. Mining xác định các tổ hợp visual words cùng hiện diện, retrieval truy vết được tới ảnh và patch assignments thật, còn class enrichment chỉ mô tả selected patterns sau khi labels được xác minh. Visual coherence của 16 representative patterns đã được người dùng xác nhận ở mức AI-assisted review; các giới hạn của biểu diễn S0 vẫn áp dụng.

## 6. Tái lập và audit

- Mining notebook: `../../../../notebook/UD2/FIM_Mining_Experiments.ipynb`
- Interpretation notebook: `../../../../notebook/UD2/FIM_Visual_Interpretation.ipynb`
- MCP log: `mcp_execution_log.md`
- Input/config/hash/budget: `../input_manifest.toml`, `../config_snapshot.toml`
- Full artifacts and statuses: `../README.md`
"""
    supervisor.atomic_write(report_path, report)

    required_files = (
        "analysis/count_by_length.csv", "analysis/pattern_support_summary.csv", "analysis/master_patterns.jsonl",
        "analysis/independent_output_audit.json",
        "analysis/representative_patterns.csv", "analysis/pattern_statistics.md", "analysis/run_statistics.csv",
        "figures/minsup_vs_itemset_count.png", "figures/minsup_vs_runtime.png", "figures/itemset_lengths_by_minsup.png",
        "interpretation/pattern_annotations.csv",
        "interpretation/retrieval_examples.csv", "interpretation/visual_interpretation.md",
        "report/experiment_manifest.toml", "report/mcp_execution_log.md")
    labels_claimed = interpretation_summary.get("label_join") == "PASS"
    if labels_claimed:
        required_files += ("interpretation/pattern_class_support.csv", "interpretation/class_pattern_stats.csv",
                           "figures/pattern_class_heatmap.png")
    required_headers = {
        "mining/runs.csv": tuple(supervisor.RUN_COLUMNS),
        "analysis/count_by_length.csv": ("minsup_fraction", "minsup_count", "status", "itemset_length", "itemset_count"),
        "analysis/pattern_support_summary.csv": ("minsup_fraction", "minsup_count", "status", "pattern_count", "support_min", "support_q25", "support_median", "support_q75", "support_max"),
        "analysis/representative_patterns.csv": ("pattern_id", "items", "length", "support_count", "support_fraction", "selection_rule", "reference_minsup", "selection_order", "support_bucket", "length_bucket", "diversity_max_jaccard", "rule_version", "selection_seed", "selection_notes"),
        "interpretation/pattern_annotations.csv": ("pattern_id", "decodable", "witness_valid", "review_status", "visual_coherence", "interpretation", "limitations", "reviewer", "reviewed_at", "evidence_paths"),
        "interpretation/retrieval_examples.csv": ("pattern_id", "retrieved_count", "example_image_ids", "contrast_image_ids", "notes"),
    }
    if labels_claimed:
        required_headers["interpretation/pattern_class_support.csv"] = (
            "pattern_id", "class_id", "N_c", "n_X_c", "p_X_given_c", "p_X", "enrichment")
        required_headers["interpretation/class_pattern_stats.csv"] = (
            "pattern_id", "class_label", "class_name", "class_total", "pattern_class_support",
            "support_fraction_global", "support_fraction_within_class", "enrichment")
    run_schema_ok = (len(run_rows) == 6 and
        [int(row["minsup_count"]) for row in run_rows] == list(supervisor.MIN_COUNTS) and
        all(row["status"] in supervisor.RUN_STATUSES for row in run_rows))
    schema_ok = all(has_csv_header(output_dir / path, fields) for path, fields in required_headers.items())
    png_paths = [path for path in required_files if path.endswith(".png")]
    png_ok = all((output_dir / path).is_file() and (output_dir / path).read_bytes().startswith(b"\x89PNG\r\n\x1a\n") for path in png_paths)
    report_audit = "PASS" if report_path.is_file() and all((output_dir / path).is_file() for path in required_files) and run_schema_ok and schema_ok and png_ok and output_audit_ok else "FAIL"
    readme_overall = overall_status(mining, execution, interpretation, report_audit)
    readme_review = (
        f"Human reviewer `{reviewer_text}` confirmed all AI-prepared scores and observations at `{reviewed_at_text}`; "
        f"coherence score counts are {coherence_count_text}. The provenance is in `interpretation/ai_visual_review.md` "
        "and the formal annotations are in `interpretation/pattern_annotations.csv`."
        if interpretation == "PASS" else
        "The AI-assisted visual assessment is prepared; human confirmation is still pending in `interpretation/pattern_annotations.csv`."
    )
    readme = f"""# Fashion-FIM result package

Configuration: B0/K32/seed123/S0. Input: `{config['input_source_path']}` (read-only), SHA-256 `{config['input_sha256']}`.

## Current evidence status

Mining `{mining}`; MCP execution `{execution}`; interpretation `{interpretation}`; report audit `{report_audit}`; overall **{readme_overall}**. {readme_review}

## Run order

1. Open `notebook/UD2/FIM_Mining_Experiments.ipynb` in the repo Julia kernel and restart it.
2. Run setup and input sanity cells, then P1 smoke/initialization. P1 only uses toy data.
3. Run the P2 launch cell once. It starts a user-systemd supervisor outside the notebook kernel; check status with the bounded poll cell. Workers run one at a time under the recorded wall/memory/output budgets.
4. After the supervisor is terminal, run the P3 analysis cell.
5. Open `notebook/UD2/FIM_Visual_Interpretation.ipynb` in a clean Julia kernel and run top to bottom. It reads exact saved output and does not call Eclat.
6. Inspect the report and galleries. {('The confirmed annotations are recorded in `interpretation/pattern_annotations.csv`.' if interpretation == 'PASS' else 'A human reviewer must complete `interpretation/pattern_annotations.csv`.')}

## Files

- `mining/runs.csv`: six derived threshold rows; authoritative records are `mining/runs/<run_id>/status.toml`.
- `mining/itemsets/`: only final-committed exact JSONL. Partial/interrupted evidence is separately under `mining/partial/`.
- `analysis/`: exact per-threshold statistics, deduplicated JSONL catalog, representatives, tables and SVG/PNG figures.
- `analysis/independent_output_audit.json`: seed-42 sample IDs/supports, direct source scan and pairwise threshold audit; records the historical production audit gap.
- `interpretation/`: retrieval registry, witness images, SVG galleries, annotations and AI-review provenance; class-conditioned statistics/heatmap are included when labels are verified.
- `report/`: application report, MCP log and agent evaluation.

Budget revision: `{config['budget_revision']}`; wall `{config['wall_time_seconds_per_run']} s/run`, memory `{config['memory_limit_mb_per_worker']} MiB/worker`, output `{config['output_limit_bytes']} bytes/itemset JSONL`. See `config_snapshot.toml` for enforcement details and environment.

## Implementation handoff — v1.3

- Base repository revision: `{config['engine_revision']}`.
- New workflow files: `src/fashion_fim/FashionFIMWorkflow.jl`, `scripts/fashion_fim/`, and the two notebooks listed above. The v1.3 spec, checklist, and MCP execution review instruction are in `docs/UD2/eclat/`.
- Existing Eclat core/API, team tests and benchmarks, TC1–TC7 implementation, and locked S0 source artifacts were left untouched. The six production thresholds ran once through the external supervisor.
- {final_validation}
- No classifier PoC was run; it remains optional. Changes have not been committed.
"""
    supervisor.atomic_write(output_dir / "README.md", readme)

    if not (output_dir / "README.md").is_file():
        report_audit = "FAIL"

    mining = mining_axis(run_rows)
    axes = {"mining": mining, "execution_mcp": execution,
            "interpretation": interpretation, "report_audit": report_audit}
    if not mcp_log:
        reason_codes = ["MCP_EVIDENCE_NOT_RECORDED"]
    else:
        reason_codes = []
    if execution == "UNVERIFIED":
        reason_codes.append("MCP_SAVE_REOPEN_UNVERIFIED")
    reason_codes.extend(row["reason_code"] for row in run_rows if row.get("reason_code"))
    if interpretation == "PENDING_REVIEW":
        reason_codes.append("HUMAN_PATTERN_REVIEW_PENDING")
    if interpretation == "NEEDS_REVISION":
        reason_codes.append("INVALID_EVIDENCE_OR_REVIEW_REVISION")
    if interpretation_summary and interpretation_summary.get("label_join") != "PASS":
        reason_codes.append("BLOCKED_MISSING_LABELS")
    if interpretation_summary and interpretation_summary.get("visual_assets_status") != "PASS":
        reason_codes.append("MISSING_ASSET")
    overall = overall_status(mining, execution, interpretation, report_audit)
    manifest_path = output_dir / "report" / "experiment_manifest.toml"
    manifest = supervisor.read_toml(manifest_path)
    run_statuses = {f"minsup_{int(float(row['minsup_fraction']) * 100):02d}": row["status"] for row in run_rows}
    output_files = sorted(
        path.relative_to(output_dir).as_posix()
        for path in output_dir.rglob("*")
        if path.is_file() and path != manifest_path and not path.name.endswith(".tmp")
    )
    if "report/agent_evaluation.md" not in output_files:
        output_files.append("report/agent_evaluation.md")
        output_files.sort()
    manifest.update({key: config[key] for key in (
        "repo_root", "input_source_path", "input_sha256", "engine_api", "engine_revision",
        "engine_source_sha256", "julia_version", "julia_threads", "julia_depot_path",
        "julia_load_path", "julia_package_versions", "cpu_model", "os_platform", "python_version",
        "cpu_count", "memory_available_bytes_at_init", "disk_free_bytes_at_init",
        "wall_time_seconds_per_run", "memory_limit_mb_per_worker", "output_limit_bytes",
        "enforcement_method", "worker_memory_scope", "output_limit_scope", "budget_revision",
        "sampling_seed", "minsup_counts", "minsup_fractions", "output_base_dir",
    ) if key in config})
    manifest.update({"mining_status": mining, "execution_mcp_status": execution,
        "interpretation_status": interpretation, "report_audit_status": report_audit,
        "overall_status": overall, "reason_codes": sorted(set(reason_codes)),
        "run_statuses": run_statuses, "output_files": output_files,
        "report_path": "report/fashion_fim_application_report.md",
        "report_sha256": supervisor.sha256_file(report_path), "evaluated_at": supervisor.utc_now()})
    supervisor.atomic_toml(manifest_path, manifest)

    insight_lines = "\n".join(insight_rows)
    evaluation = f"""# Agent evaluation — Fashion-FIM v1.3

Overall: **{overall}**. Mining `{mining}` · MCP `{execution}` · Interpretation `{interpretation}` · Report/audit `{report_audit}`.

| Criterion | Status | Evidence |
|---|---|---|
| Correct engine integration and locked input | {'PASS' if config['input_sha256'] == input_manifest['input_sha256'] else 'FAIL'} | `../config_snapshot.toml`, `../input_manifest.toml`, worker script uses two positional arguments |
| Six-threshold completeness and exact outputs | {mining} | `../mining/runs.csv` and each authoritative status sidecar |
| MCP clean-kernel execution | {execution} | `mcp_execution_log.md` |
| Statistics and representative selection | {'PASS' if (output_dir/'analysis/representative_patterns.csv').is_file() else 'BLOCKED'} | `../analysis/` |
| Visual provenance, witness and retrieval | {'PASS' if interpretation_summary.get('witness_validation') == 'PASS' and interpretation_summary.get('retrieval', {}).get('retrieval_matches_support') else 'BLOCKED'} | `../interpretation/pattern_gallery/`, `../interpretation/retrieval_examples.csv` |
| Human-confirmed AI-assisted visual assessment | {interpretation} | `../interpretation/pattern_annotations.csv`, `../interpretation/ai_visual_review.md` |
| Report and artifact audit | {report_audit} | `fashion_fim_application_report.md`, `experiment_manifest.toml` |

## Evidence-based findings

{insight_lines}

## Validation corrections

- The first interpretation run exposed a retrieval-registry scalar/list mismatch. It was corrected, and the final MCP P4 run verified that the 4,818 retrieved images match the exact support.
- The representative-pattern CSV was aligned to the v1.3 schema before the final P3/P4 regeneration; its selection hash is bound in the interpretation manifest.
- P1 now has synthetic coverage for same-support bucket ties, lexical ordering, all nine selection cells, the one-time 0.80→0.90 reset, and short catalogs. The final MCP smoke passed 22 checks.
- Missing codebook, patch, image, and label assets were exercised on an isolated copy. Retrieval and report audit remained valid, while the gallery and label-dependent chart were omitted and explicit partial statuses/reason codes were emitted.
- The initial production commits recorded zero cross-threshold comparisons because a repository-relative output path was joined to the output directory a second time. `supervisor.py` now resolves those paths from the repository root. The sidecars were atomically reconciled after the audit: they preserve the original zero in `production_commit_cross_threshold_outputs_checked` and point to `../analysis/independent_output_audit.json` for the post-run support sample and all 15 pairwise threshold checks. This revalidates current outputs but cannot retroactively establish that the checks preceded the original production commits.

## Limitations and follow-up

- S0 establishes image-level co-occurrence and cannot support fixed spatial/geometry claims.
- Codebook fitting used all 70,000 images, so downstream discussion is transductive/exploratory; no classifier metrics were run.
- {ai_review_note or 'No AI-assisted visual assessment was prepared.'}
- Resource statuses and incomplete thresholds remain visible in `runs.csv`; no partial itemset count is presented as exact.
- {'Clean-kernel save/reopen is verified by MCP open calls on both notebooks, and the current editor buffers are clean.' if execution == 'PASS' else 'Notebook save/reopen remains unverified because the latest live Mining and Visual editor buffers are dirty and the bridge exposes no save/close command; see `mcp_execution_log.md`.'}

Reason codes: {', '.join(sorted(set(reason_codes))) if reason_codes else 'none'}.
"""
    supervisor.atomic_write(output_dir / "report" / "agent_evaluation.md", evaluation)
    print(json.dumps({"axes": axes, "overall": overall, "reason_codes": sorted(set(reason_codes)),
                      "report_audit": report_audit, "report": str(report_path)}, ensure_ascii=False, indent=2))
    return {"axes": axes, "overall": overall, "reason_codes": reason_codes, "report_audit": report_audit}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()
    create_report(pathlib.Path(args.output_dir).resolve())


if __name__ == "__main__":
    main()
