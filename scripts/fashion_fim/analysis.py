#!/usr/bin/env python3
"""Build exact FIM summaries, a master catalog, deterministic representatives, and SVG figures."""

from __future__ import annotations

import argparse
import csv
import hashlib
import heapq
import html
import itertools
import json
import math
import os
import pathlib
import shutil
import sqlite3
import subprocess
import tempfile

import supervisor

LENGTH_CELLS = (("1", "low"), ("1", "mid"), ("1", "high"),
                ("2", "low"), ("2", "mid"), ("2", "high"),
                (">=3", "low"), (">=3", "mid"), (">=3", "high"))


def run_records(output_dir: pathlib.Path) -> list[dict]:
    config = supervisor.load_config(output_dir)
    manifest = supervisor.canonical_manifest(output_dir)[1]
    records = []
    for count in supervisor.MIN_COUNTS:
        pct = int(supervisor.FRACTIONS[count] * 100)
        run_id = manifest.get("canonical_runs", {}).get(f"{pct:02d}")
        if not run_id:
            records.append({"run_id": "", "minsup_count": count, "minsup_fraction": supervisor.FRACTIONS[count],
                            "status": "NOT_RUN", "path": None, "sidecar": {"status": "NOT_RUN", "reason_code": ""}})
            continue
        sidecar_file = supervisor.sidecar_path(output_dir, run_id)
        if not sidecar_file.is_file():
            records.append({"run_id": run_id, "minsup_count": count, "minsup_fraction": supervisor.FRACTIONS[count],
                            "status": "NOT_RUN", "path": None, "sidecar": {"status": "NOT_RUN", "reason_code": "SIDECAR_MISSING"}})
            continue
        sidecar = supervisor.read_toml(sidecar_file)
        path = None
        if sidecar.get("status") in {"COMPLETED_FULL", "COMPLETED_ZERO"}:
            if not supervisor.verify_reusable(output_dir, config, sidecar):
                raise ValueError(f"Final output failed identity/checksum/read-back verification: {run_id}")
            path = pathlib.Path(config["repo_root"]) / sidecar["output_path"]
        records.append({"run_id": run_id, "minsup_count": count, "minsup_fraction": supervisor.FRACTIONS[count],
                        "status": sidecar.get("status", "NOT_RUN"), "path": path, "sidecar": sidecar})
    return records


def iter_records(path: pathlib.Path, min_count: int):
    for key, support in supervisor.read_itemsets(path, min_count):
        yield {"items": list(key[1]), "length": key[0], "support_count": support,
               "support_fraction": support / 70_000, "minsup_count": min_count}


def quantile(histogram: list[int], population: int, probability: float):
    if population == 0:
        return "NA"
    rank = max(1, math.ceil(population * probability))
    cumulative = 0
    for support, count in enumerate(histogram):
        cumulative += count
        if cumulative >= rank:
            return support
    raise AssertionError("Support histogram rank exceeded population")


def stats_for_run(run: dict) -> dict:
    if run["path"] is None:
        sidecar = run["sidecar"]
        return {"run_id": run["run_id"], "minsup_fraction": run["minsup_fraction"],
            "minsup_count": run["minsup_count"], "status": run["status"],
            "reason_code": sidecar.get("reason_code", ""), "total_frequent_itemsets": "NA",
            "max_itemset_length": "NA", "length_1_count": "NA", "length_2_count": "NA",
            "length_ge_3_count": "NA", "singleton_fraction": "NA", "pair_fraction": "NA",
            "length_ge_3_fraction": "NA", "support_min": "NA", "support_q25": "NA",
            "support_median": "NA", "support_q75": "NA", "support_max": "NA",
            "runtime_seconds": sidecar.get("runtime_seconds", "NA"),
            "peak_rss_mb": sidecar.get("peak_rss_mb", "NA"),
            "output_size_bytes": sidecar.get("output_size_bytes", "NA"), "length_counts": {}}
    length_counts: dict[int, int] = {}
    histogram = [0] * 70_001
    count = 0
    minimum = None
    maximum = None
    for record in iter_records(run["path"], run["minsup_count"]):
        support = record["support_count"]
        length = record["length"]
        count += 1
        histogram[support] += 1
        length_counts[length] = length_counts.get(length, 0) + 1
        minimum = support if minimum is None else min(minimum, support)
        maximum = support if maximum is None else max(maximum, support)
    observed = run["sidecar"].get("total_frequent_itemsets")
    if count != observed:
        raise ValueError(f"Analysis count mismatch for {run['run_id']}: {count} != {observed}")
    singleton = length_counts.get(1, 0)
    pairs = length_counts.get(2, 0)
    long_sets = sum(number for length, number in length_counts.items() if length >= 3)
    total = count
    return {
        "run_id": run["run_id"], "minsup_fraction": run["minsup_fraction"],
        "minsup_count": run["minsup_count"], "status": run["status"],
        "reason_code": run["sidecar"].get("reason_code", ""),
        "total_frequent_itemsets": total, "max_itemset_length": run["sidecar"].get("max_itemset_length", 0),
        "length_1_count": singleton, "length_2_count": pairs, "length_ge_3_count": long_sets,
        "singleton_fraction": singleton / total if total else 0.0,
        "pair_fraction": pairs / total if total else 0.0,
        "length_ge_3_fraction": long_sets / total if total else 0.0,
        "support_min": minimum if minimum is not None else 0,
        "support_q25": quantile(histogram, total, 0.25),
        "support_median": quantile(histogram, total, 0.50),
        "support_q75": quantile(histogram, total, 0.75),
        "support_max": maximum if maximum is not None else 0,
        "runtime_seconds": run["sidecar"].get("runtime_seconds", "NA"),
        "peak_rss_mb": run["sidecar"].get("peak_rss_mb", "NA"),
        "output_size_bytes": run["sidecar"].get("output_size_bytes", 0),
        "length_counts": {str(key): value for key, value in sorted(length_counts.items())},
    }


def write_run_stats(output_dir: pathlib.Path, stats: list[dict]) -> pathlib.Path:
    path = output_dir / "analysis" / "run_statistics.csv"
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = ["run_id", "minsup_fraction", "minsup_count", "status", "reason_code",
              "total_frequent_itemsets", "max_itemset_length", "length_1_count", "length_2_count",
              "length_ge_3_count", "singleton_fraction", "pair_fraction", "length_ge_3_fraction",
              "support_min", "support_q25", "support_median", "support_q75", "support_max",
              "runtime_seconds", "peak_rss_mb", "output_size_bytes"]
    with open(path, "w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        for row in stats:
            writer.writerow({key: row.get(key, "NA") for key in fields})
    return path


def pattern_id(items: tuple[int, ...]) -> str:
    canonical = ",".join(map(str, items))
    return "P-" + hashlib.sha256(canonical.encode("ascii")).hexdigest()


def build_master_catalog(output_dir: pathlib.Path, runs: list[dict]) -> tuple[pathlib.Path, sqlite3.Connection, dict]:
    analysis_dir = output_dir / "analysis"
    analysis_dir.mkdir(parents=True, exist_ok=True)
    master_path = analysis_dir / "master_patterns.csv"
    master_jsonl_path = analysis_dir / "master_patterns.jsonl"
    db_file = tempfile.NamedTemporaryFile(prefix="fim-selection-", suffix=".sqlite", dir=analysis_dir, delete=False)
    db_file.close()
    connection = sqlite3.connect(db_file.name)
    connection.execute("PRAGMA journal_mode=OFF")
    connection.execute("PRAGMA synchronous=OFF")
    connection.execute("PRAGMA temp_store=FILE")
    connection.execute("PRAGMA cache_size=-8192")
    connection.execute("CREATE TABLE patterns (pattern_id TEXT PRIMARY KEY, items TEXT NOT NULL, items_key TEXT NOT NULL, length INTEGER NOT NULL, support INTEGER NOT NULL, observed_at_minsup TEXT NOT NULL, source_run_ids TEXT NOT NULL, length_bucket TEXT NOT NULL, support_bucket TEXT)")
    connection.execute("CREATE INDEX patterns_support_idx ON patterns(support)")
    histogram = [0] * 70_001
    master_fields = ["pattern_id", "items", "length", "support_count", "support_fraction", "observed_at_minsup", "source_run_ids"]
    batch = []

    iterators = [iter(iter_records(run["path"], run["minsup_count"])) for run in runs]
    merged = heapq.merge(*iterators, key=lambda row: (row["length"], tuple(row["items"])))
    with open(master_path, "w", newline="", encoding="utf-8") as stream, \
            open(master_jsonl_path, "w", encoding="utf-8") as jsonl_stream:
        writer = csv.DictWriter(stream, fieldnames=master_fields, lineterminator="\n")
        writer.writeheader()
        for items, group in itertools.groupby(merged, key=lambda row: tuple(row["items"])):
            rows = list(group)
            supports = {row["support_count"] for row in rows}
            if len(supports) != 1:
                raise ValueError(f"Same itemset has different supports across minsups: {items}")
            support = supports.pop()
            observed_counts = {row["minsup_count"] for row in rows}
            observed = [f"{int(round(run['minsup_fraction'] * 100))}%" for run in runs
                        if run["minsup_count"] in observed_counts]
            run_ids = [run["run_id"] for run in runs if run["minsup_count"] in observed_counts]
            csv_items = ";".join(map(str, items))
            identifier = pattern_id(items)
            record = {"pattern_id": identifier, "items": csv_items, "length": len(items),
                      "support_count": support, "support_fraction": support / 70_000,
                      "observed_at_minsup": ";".join(observed), "source_run_ids": ";".join(run_ids)}
            writer.writerow(record)
            jsonl_stream.write(json.dumps({"pattern_id": identifier, "items": list(items), "length": len(items),
                "support_count": support, "support_fraction": support / 70_000,
                "observed_at_minsup": observed, "source_run_ids": run_ids},
                separators=(",", ":"), ensure_ascii=False) + "\n")
            length_bucket = "1" if len(items) == 1 else "2" if len(items) == 2 else ">=3"
            items_key = ",".join(f"{item:02d}" for item in items)
            batch.append((identifier, csv_items, items_key, len(items), support,
                          record["observed_at_minsup"], record["source_run_ids"], length_bucket))
            histogram[support] += 1
            if len(batch) >= 10_000:
                connection.executemany("INSERT INTO patterns VALUES (?,?,?,?,?,?,?,?,NULL)", batch)
                batch.clear()
        if batch:
            connection.executemany("INSERT INTO patterns VALUES (?,?,?,?,?,?,?,?,NULL)", batch)
        stream.flush()
        os.fsync(stream.fileno())
        jsonl_stream.flush()
        os.fsync(jsonl_stream.fileno())
    connection.commit()

    distinct_supports = [support for support, frequency in enumerate(histogram) if frequency]
    distinct_count = len(distinct_supports)
    q1 = math.ceil(distinct_count / 3) if distinct_count else 0
    q2 = math.ceil(2 * distinct_count / 3) if distinct_count else 0
    rank_bucket = {}
    for rank, support in enumerate(distinct_supports, 1):
        rank_bucket[support] = "low" if rank <= q1 else "mid" if rank <= q2 else "high"
    for support, bucket in rank_bucket.items():
        connection.execute("UPDATE patterns SET support_bucket=? WHERE support=?", (bucket, support))
    connection.commit()
    connection.execute("CREATE INDEX patterns_grid_idx ON patterns(length_bucket,support_bucket,support DESC,length,items_key)")
    connection.commit()
    metadata = {"catalog_sha256": supervisor.sha256_file(master_jsonl_path), "unique_pattern_count": sum(histogram),
                "distinct_support_count": distinct_count, "support_tertile_q1_rank": q1,
                "support_tertile_q2_rank": q2, "rule_version": "v1.3-deterministic-grid"}
    return master_jsonl_path, connection, metadata


def write_analysis_tables(output_dir: pathlib.Path, stats: list[dict]) -> None:
    analysis_dir = output_dir / "analysis"
    completed_statuses = {"COMPLETED_FULL", "COMPLETED_ZERO"}
    count_path = analysis_dir / "count_by_length.csv"
    with open(count_path, "w", newline="", encoding="utf-8") as stream:
        fields = ["minsup_fraction", "minsup_count", "status", "itemset_length", "itemset_count"]
        writer = csv.DictWriter(stream, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        for run in stats:
            completed = run["status"] in completed_statuses
            lengths = run.get("length_counts", {})
            for length in range(1, 33):
                writer.writerow({"minsup_fraction": run["minsup_fraction"], "minsup_count": run["minsup_count"],
                    "status": run["status"], "itemset_length": length,
                    "itemset_count": lengths.get(str(length), 0) if completed else "NA"})

    support_path = analysis_dir / "pattern_support_summary.csv"
    with open(support_path, "w", newline="", encoding="utf-8") as stream:
        fields = ["minsup_fraction", "minsup_count", "status", "pattern_count", "support_min",
                  "support_q25", "support_median", "support_q75", "support_max"]
        writer = csv.DictWriter(stream, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        for run in stats:
            writer.writerow({"minsup_fraction": run["minsup_fraction"], "minsup_count": run["minsup_count"],
                "status": run["status"], "pattern_count": run["total_frequent_itemsets"],
                **{key: run[key] for key in fields[4:]}})


def write_statistics_markdown(output_dir: pathlib.Path, stats: list[dict], catalog_meta: dict) -> None:
    completed_statuses = {"COMPLETED_FULL", "COMPLETED_ZERO"}
    completed = [row for row in stats if row["status"] in completed_statuses]
    lines = ["# Fashion-MNIST FIM pattern statistics", "",
        "## Observed results", "",
        "All quantities below are calculated from final-committed, read-back-verified outputs.", ""]
    for row in stats:
        pct = int(round(float(row["minsup_fraction"]) * 100))
        if row["status"] not in completed_statuses:
            lines.append(f"- **{pct}%:** `{row['status']}` ({row['reason_code'] or 'no reason code'}); exact count and length distribution are unavailable.")
            continue
        lengths = row["length_counts"]
        length_text = ", ".join(f"{length}:{count}" for length, count in sorted(lengths.items(), key=lambda pair: int(pair[0]))) or "none"
        lines.append(f"- **{pct}%:** {row['total_frequent_itemsets']:,} itemsets; max length {row['max_itemset_length']}; "
            f"support min/median/max {row['support_min']}/{row['support_median']}/{row['support_max']}; "
            f"runtime {row['runtime_seconds']} s; counts by length `{length_text}`.")
    lines.extend(["", "## Cross-threshold observations", ""])
    if completed:
        ordered = sorted(completed, key=lambda row: float(row["minsup_fraction"]), reverse=True)
        if len(ordered) > 1:
            pairs = [f"{int(a['minsup_fraction']*100)}%→{int(b['minsup_fraction']*100)}%: "
                     f"{int(a['total_frequent_itemsets']):,}→{int(b['total_frequent_itemsets']):,}"
                     for a, b in zip(ordered, ordered[1:])]
            lines.append("- Observed itemset counts at completed thresholds: " + "; ".join(pairs) + ".")
        lines.append(f"- The deduplicated catalog contains {catalog_meta['unique_pattern_count']:,} unique patterns "
                     f"across {catalog_meta['distinct_support_count']:,} distinct support counts.")
        lines.append("- These are descriptive coverage counts. They do not establish semantic usefulness or class discrimination.")
    else:
        lines.append("- No completed run is available, so no cross-threshold trend is reported.")
    lines.extend(["", "## Interpretation boundary", "",
        "Lower minsup can add patterns because it admits lower-support combinations; this is a threshold effect, not evidence by itself that those patterns are more useful. "
        "Observed runtime and output size describe only the completed worker runs. Any stopped run is shown by status and is not treated as a complete enumeration.", ""])
    (output_dir / "analysis" / "pattern_statistics.md").write_text("\n".join(lines), encoding="utf-8")


def render_png(svg_path: pathlib.Path, png_path: pathlib.Path) -> None:
    renderer = shutil.which("rsvg-convert")
    if renderer is None:
        raise RuntimeError("rsvg-convert is required to render required PNG figures")
    png_path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([renderer, "--format=png", "--output", str(png_path), str(svg_path)],
                   check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)


def jaccard(left: tuple[int, ...], right: tuple[int, ...]) -> float:
    a, b = set(left), set(right)
    return len(a & b) / len(a | b)


def deterministic_selection_for_test(candidates: list[dict], target: int, threshold: float) -> list[dict]:
    """Small, in-memory reference used by P1 smoke for selection boundary cases."""
    supports = sorted({candidate["support_count"] for candidate in candidates})
    q1, q2 = math.ceil(len(supports) / 3), math.ceil(2 * len(supports) / 3)
    buckets = {}
    for index, support in enumerate(supports, 1):
        buckets[support] = "low" if index <= q1 else "mid" if index <= q2 else "high"
    cells = {cell: [] for cell in LENGTH_CELLS}
    for candidate in candidates:
        length = candidate["length"]
        length_bucket = "1" if length == 1 else "2" if length == 2 else ">=3"
        cells[(length_bucket, buckets[candidate["support_count"]])].append(candidate)
    for pool in cells.values():
        pool.sort(key=lambda row: (-row["support_count"], row["length"], tuple(row["items"])))
    selected, considered = [], set()
    while len(selected) < target:
        progress = False
        for cell in LENGTH_CELLS:
            for candidate in cells[cell]:
                if candidate["pattern_id"] in considered:
                    continue
                considered.add(candidate["pattern_id"])
                diversity = max((jaccard(tuple(candidate["items"]), tuple(row["items"])) for row in selected), default=0.0)
                if diversity <= threshold:
                    selected.append({**candidate, "diversity_max_jaccard": diversity,
                                     "length_bucket": cell[0], "support_bucket": cell[1]})
                    progress = True
                    break
            if len(selected) >= target:
                break
        if not progress:
            break
    return selected


def selection_pass(connection: sqlite3.Connection, target: int, threshold: float) -> list[dict]:
    selected = []
    considered = set()
    while len(selected) < target:
        progress = False
        for length_bucket, support_bucket in LENGTH_CELLS:
            cursor = connection.execute(
                "SELECT pattern_id,items,length,support,observed_at_minsup,source_run_ids "
                "FROM patterns WHERE length_bucket=? AND support_bucket=? "
                "ORDER BY support DESC,length ASC,items_key ASC", (length_bucket, support_bucket))
            for row in cursor:
                identifier, csv_items, length, support, observed, run_ids = row
                if identifier in considered:
                    continue
                considered.add(identifier)
                items = tuple(int(item) for item in csv_items.split(";"))
                diversity = max((jaccard(items, tuple(chosen["items"])) for chosen in selected), default=0.0)
                if diversity <= threshold:
                    selected.append({"pattern_id": identifier, "items": items, "length": length,
                        "support_count": support, "support_fraction": support / 70_000,
                        "observed_at_minsup": observed, "source_run_ids": run_ids,
                        "length_bucket": length_bucket, "support_bucket": support_bucket,
                        "diversity_max_jaccard": diversity, "selection_threshold": threshold})
                    progress = True
                    break
            if len(selected) >= target:
                break
        if not progress:
            break
    return selected


def select_with_relaxation(connection: sqlite3.Connection, target: int) -> tuple[list[dict], float, bool]:
    selected = selection_pass(connection, target, 0.80)
    if len(selected) < target:
        return selection_pass(connection, target, 0.90), 0.90, True
    return selected, 0.80, False


def save_selection(output_dir: pathlib.Path, selected: list[dict], metadata: dict, target: int,
                   threshold: float, relaxed: bool) -> pathlib.Path:
    path = output_dir / "analysis" / "representative_patterns.csv"
    fields = ["pattern_id", "items", "length", "support_count", "support_fraction", "selection_rule",
              "reference_minsup", "selection_order", "support_bucket", "length_bucket",
              "diversity_max_jaccard", "rule_version", "selection_seed", "selection_notes"]
    with open(path, "w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        for index, row in enumerate(selected, 1):
            writer.writerow({"pattern_id": row["pattern_id"],
                "items": ";".join(map(str, row["items"])), "length": row["length"],
                "support_count": row["support_count"], "support_fraction": row["support_fraction"],
                "selection_rule": "v1.3-deterministic-grid",
                "reference_minsup": row["observed_at_minsup"], "selection_order": index,
                "length_bucket": row["length_bucket"], "support_bucket": row["support_bucket"],
                "diversity_max_jaccard": row["diversity_max_jaccard"],
                "rule_version": metadata["rule_version"], "selection_seed": 42,
                "selection_notes": (f"Selected with Jaccard <= {threshold:.2f}; seed 42 is reserved for gallery sampling"
                                    if relaxed else "Deterministic grid selection; seed 42 is reserved for gallery sampling")})
    manifest = {"target_requested": target, "target_selected": len(selected),
        "relaxation_used": relaxed, "actual_jaccard_threshold": threshold,
        "rule_version": metadata["rule_version"], "selection_seed": 42,
        "selection_threshold": threshold, "catalog_sha256": metadata["catalog_sha256"],
        "unique_pattern_count": metadata["unique_pattern_count"],
        "selection_order": [row["pattern_id"] for row in selected],
        "selection_notes": ("" if len(selected) == target else
            f"Only {len(selected)} distinct candidates passed the deterministic grid/diversity rule")}
    supervisor.atomic_toml(output_dir / "analysis" / "selection_manifest.toml", manifest)
    return path


def esc(value) -> str:
    return html.escape(str(value), quote=True)


def write_counts_figure(path: pathlib.Path, stats: list[dict]) -> None:
    width, height = 960, 540
    left, right, top, bottom = 100, 34, 65, 105
    plot_w, plot_h = width - left - right, height - top - bottom
    completed = [row for row in stats if row["status"] in {"COMPLETED_FULL", "COMPLETED_ZERO"}]
    max_value = max((row["total_frequent_itemsets"] for row in completed), default=1)
    upper = max(1.0, math.log10(max_value + 1))
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#ffffff"/>',
        '<text x="480" y="32" text-anchor="middle" font-family="sans-serif" font-size="22" font-weight="700">Frequent itemsets theo minsup</text>']
    for tick in range(0, int(math.ceil(upper)) + 1):
        y = top + plot_h - plot_h * tick / upper
        label = "0" if tick == 0 else f"10^{tick}"
        parts.append(f'<line x1="{left}" y1="{y:.1f}" x2="{left + plot_w}" y2="{y:.1f}" stroke="#e6eaf0"/>')
        parts.append(f'<text x="{left - 12}" y="{y + 4:.1f}" text-anchor="end" font-family="sans-serif" font-size="12">{label}</text>')
    parts += [f'<line x1="{left}" y1="{top + plot_h}" x2="{left + plot_w}" y2="{top + plot_h}" stroke="#455468"/>',
              f'<line x1="{left}" y1="{top}" x2="{left}" y2="{top + plot_h}" stroke="#455468"/>',
              f'<text x="{left + plot_w/2}" y="{height - 25}" text-anchor="middle" font-family="sans-serif" font-size="14">minsup (phần trăm transactions)</text>',
              f'<text x="23" y="{top + plot_h/2}" transform="rotate(-90 23 {top + plot_h/2})" text-anchor="middle" font-family="sans-serif" font-size="14">Số itemsets (log10)</text>']
    points = []
    for index, row in enumerate(stats):
        x = left + plot_w * index / max(1, len(stats) - 1)
        label = f"{int(row['minsup_fraction']*100)}%"
        parts.append(f'<text x="{x:.1f}" y="{top + plot_h + 24}" text-anchor="middle" font-family="sans-serif" font-size="13">{label}</text>')
        if row["status"] in {"COMPLETED_FULL", "COMPLETED_ZERO"}:
            count = row["total_frequent_itemsets"]
            y = top + plot_h if count == 0 else top + plot_h - plot_h * math.log10(count + 1) / upper
            points.append((x, y))
            parts.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="6" fill="#2077b4"/>')
            parts.append(f'<text x="{x:.1f}" y="{y - 12:.1f}" text-anchor="middle" font-family="sans-serif" font-size="12" fill="#173f5f">{count:,}</text>')
        else:
            y = top + 22
            parts.append(f'<path d="M{x-6:.1f},{y-6:.1f} L{x+6:.1f},{y+6:.1f} M{x+6:.1f},{y-6:.1f} L{x-6:.1f},{y+6:.1f}" stroke="#c33d3d" stroke-width="3"/>')
            parts.append(f'<text x="{x:.1f}" y="{y + 22:.1f}" text-anchor="middle" font-family="sans-serif" font-size="10" fill="#9f2727">{esc(row["status"])}</text>')
    if len(points) > 1:
        coords = " ".join(f"{x:.1f},{y:.1f}" for x, y in points)
        parts.insert(-1, f'<polyline points="{coords}" fill="none" stroke="#2077b4" stroke-width="2.5"/>')
    parts.append('</svg>')
    path.write_text("\n".join(parts), encoding="utf-8")


def write_runtime_figure(path: pathlib.Path, stats: list[dict]) -> None:
    width, height = 960, 540
    left, right, top, bottom = 100, 34, 65, 105
    plot_w, plot_h = width - left - right, height - top - bottom
    complete = [row["runtime_seconds"] for row in stats
                if row["status"] in {"COMPLETED_FULL", "COMPLETED_ZERO"} and isinstance(row["runtime_seconds"], (int, float))]
    upper = max(1.0, max(complete, default=1) * 1.15)
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#ffffff"/>',
        '<text x="480" y="32" text-anchor="middle" font-family="sans-serif" font-size="22" font-weight="700">Runtime theo minsup</text>']
    for fraction in (0, .25, .5, .75, 1):
        y = top + plot_h * (1 - fraction)
        val = upper * fraction
        parts.append(f'<line x1="{left}" y1="{y:.1f}" x2="{left+plot_w}" y2="{y:.1f}" stroke="#e6eaf0"/>')
        parts.append(f'<text x="{left-12}" y="{y+4:.1f}" text-anchor="end" font-family="sans-serif" font-size="12">{val:.0f}</text>')
    parts += [f'<line x1="{left}" y1="{top+plot_h}" x2="{left+plot_w}" y2="{top+plot_h}" stroke="#455468"/>',
        f'<text x="{left+plot_w/2}" y="{height-25}" text-anchor="middle" font-family="sans-serif" font-size="14">minsup (phần trăm transactions)</text>',
        f'<text x="22" y="{top+plot_h/2}" transform="rotate(-90 22 {top+plot_h/2})" text-anchor="middle" font-family="sans-serif" font-size="14">Giây (mỗi worker, startup→exit)</text>']
    points = []
    for index, row in enumerate(stats):
        x = left + plot_w * index / max(1, len(stats) - 1)
        parts.append(f'<text x="{x:.1f}" y="{top+plot_h+24}" text-anchor="middle" font-family="sans-serif" font-size="13">{int(row["minsup_fraction"]*100)}%</text>')
        runtime = row["runtime_seconds"]
        if row["status"] in {"COMPLETED_FULL", "COMPLETED_ZERO"} and isinstance(runtime, (int, float)):
            y = top + plot_h * (1 - runtime / upper)
            points.append((x, y))
            parts.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="6" fill="#2c8c63"/>')
            parts.append(f'<text x="{x:.1f}" y="{y-12:.1f}" text-anchor="middle" font-family="sans-serif" font-size="12">{runtime:.1f}s</text>')
        else:
            y = top + 20
            parts.append(f'<rect x="{x-5:.1f}" y="{y-5:.1f}" width="10" height="10" fill="#c33d3d"/>')
            parts.append(f'<text x="{x:.1f}" y="{y+20:.1f}" text-anchor="middle" font-family="sans-serif" font-size="10" fill="#9f2727">{esc(row["status"])}</text>')
    if len(points) > 1:
        parts.append('<polyline points="' + " ".join(f"{x:.1f},{y:.1f}" for x, y in points) + '" fill="none" stroke="#2c8c63" stroke-width="2.5"/>')
    parts.append('</svg>')
    path.write_text("\n".join(parts), encoding="utf-8")


def write_length_figure(path: pathlib.Path, stats: list[dict]) -> None:
    width, height = 960, 520
    left, right, top, bottom = 90, 36, 75, 85
    plot_w, plot_h = width - left - right, height - top - bottom
    bar_w = min(72, plot_w / max(1, len(stats)) * .55)
    colors = {"length_1_count": "#4c78a8", "length_2_count": "#f2a541", "length_ge_3_count": "#59a14f"}
    labels = {"length_1_count": "|X|=1", "length_2_count": "|X|=2", "length_ge_3_count": "|X|≥3"}
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#ffffff"/>',
        '<text x="480" y="34" text-anchor="middle" font-family="sans-serif" font-size="22" font-weight="700">Phân bố độ dài itemsets</text>',
        f'<line x1="{left}" y1="{top+plot_h}" x2="{left+plot_w}" y2="{top+plot_h}" stroke="#455468"/>']
    for idx, row in enumerate(stats):
        x = left + plot_w * (idx + .5) / max(1, len(stats))
        parts.append(f'<text x="{x:.1f}" y="{top+plot_h+24}" text-anchor="middle" font-family="sans-serif" font-size="13">{int(row["minsup_fraction"]*100)}%</text>')
        if row["status"] not in {"COMPLETED_FULL", "COMPLETED_ZERO"}:
            parts.append(f'<text x="{x:.1f}" y="{top+plot_h/2:.1f}" text-anchor="middle" font-family="sans-serif" font-size="10" fill="#9f2727">{esc(row["status"])}</text>')
            continue
        total = row["total_frequent_itemsets"]
        if total == 0:
            parts.append(f'<rect x="{x-bar_w/2:.1f}" y="{top+plot_h-2}" width="{bar_w:.1f}" height="2" fill="#9da7b3"/>')
            parts.append(f'<text x="{x:.1f}" y="{top+plot_h-12}" text-anchor="middle" font-family="sans-serif" font-size="11">0 patterns</text>')
            continue
        cursor = top + plot_h
        for key in ("length_1_count", "length_2_count", "length_ge_3_count"):
            proportion = row[key] / total
            segment_h = plot_h * proportion
            cursor -= segment_h
            parts.append(f'<rect x="{x-bar_w/2:.1f}" y="{cursor:.1f}" width="{bar_w:.1f}" height="{segment_h:.1f}" fill="{colors[key]}"/>')
            if proportion >= .12:
                parts.append(f'<text x="{x:.1f}" y="{cursor+segment_h/2+4:.1f}" text-anchor="middle" font-family="sans-serif" font-size="11" fill="#ffffff">{proportion:.0%}</text>')
    legend_x = left + 8
    for idx, key in enumerate(("length_1_count", "length_2_count", "length_ge_3_count")):
        x = legend_x + idx * 190
        parts.append(f'<rect x="{x}" y="{height-35}" width="14" height="14" fill="{colors[key]}"/>')
        parts.append(f'<text x="{x+21}" y="{height-23}" font-family="sans-serif" font-size="12">{labels[key]}</text>')
    parts.append('</svg>')
    path.write_text("\n".join(parts), encoding="utf-8")


def write_analysis_summary(output_dir: pathlib.Path, completed_count: int, stats: list[dict],
                           catalog_meta: dict, selected: list[dict], threshold: float, relaxed: bool,
                           target: int) -> dict:
    summary = {"configuration": "B0_K32_seed123_S0", "completed_threshold_count": completed_count,
        "official_threshold_count": len(supervisor.MIN_COUNTS), "run_statistics": stats,
        "catalog": catalog_meta, "representatives": {"target_requested": target,
            "target_selected": len(selected), "actual_jaccard_threshold": threshold,
            "relaxation_used": relaxed, "pattern_ids": [row["pattern_id"] for row in selected]}}
    path = output_dir / "analysis" / "analysis_summary.json"
    path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return summary


def analyze(output_dir: pathlib.Path, target: int) -> dict:
    if not 12 <= target <= 20:
        raise ValueError("representative_patterns_target must be between 12 and 20")
    all_runs = run_records(output_dir)
    runs = [run for run in all_runs if run["path"] is not None]
    if not runs:
        raise RuntimeError("No final-committed completed outputs are available for analysis")
    stats = [stats_for_run(run) for run in all_runs]
    write_run_stats(output_dir, stats)
    write_analysis_tables(output_dir, stats)
    master_path, connection, catalog_meta = build_master_catalog(output_dir, runs)
    database_path = pathlib.Path(connection.execute("PRAGMA database_list").fetchone()[2])
    try:
        selected, threshold, relaxed = select_with_relaxation(connection, target)
        save_selection(output_dir, selected, catalog_meta, target, threshold, relaxed)
    finally:
        connection.close()
        database_path.unlink(missing_ok=True)
    write_counts_figure(output_dir / "analysis" / "minsup_vs_itemset_count.svg", stats)
    write_runtime_figure(output_dir / "analysis" / "minsup_vs_runtime.svg", stats)
    write_length_figure(output_dir / "analysis" / "itemset_length_distribution.svg", stats)
    figures = output_dir / "figures"
    render_png(output_dir / "analysis" / "minsup_vs_itemset_count.svg", figures / "minsup_vs_itemset_count.png")
    render_png(output_dir / "analysis" / "minsup_vs_runtime.svg", figures / "minsup_vs_runtime.png")
    render_png(output_dir / "analysis" / "itemset_length_distribution.svg", figures / "itemset_lengths_by_minsup.png")
    write_statistics_markdown(output_dir, stats, catalog_meta)
    summary = write_analysis_summary(output_dir, len(runs), stats, catalog_meta, selected, threshold, relaxed, target)
    summary["master_catalog_path"] = "analysis/master_patterns.jsonl"
    summary["master_catalog_sha256"] = supervisor.sha256_file(master_path)
    (output_dir / "analysis" / "analysis_summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"analysis": "PASS", "completed_runs": len(runs), "unique_patterns": catalog_meta["unique_pattern_count"],
                      "representatives": len(selected), "threshold": threshold, "relaxed": relaxed,
                      "files": ["analysis/count_by_length.csv", "analysis/pattern_support_summary.csv",
                                "analysis/master_patterns.jsonl", "analysis/run_statistics.csv", "analysis/pattern_statistics.md",
                                "analysis/representative_patterns.csv", "analysis/minsup_vs_itemset_count.svg",
                                "analysis/minsup_vs_runtime.svg", "analysis/itemset_length_distribution.svg",
                                "figures/minsup_vs_itemset_count.png", "figures/minsup_vs_runtime.png",
                                "figures/itemset_lengths_by_minsup.png"]},
                     ensure_ascii=False, indent=2))
    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--target", type=int, default=16)
    args = parser.parse_args()
    analyze(pathlib.Path(args.output_dir).resolve(), args.target)


if __name__ == "__main__":
    main()
