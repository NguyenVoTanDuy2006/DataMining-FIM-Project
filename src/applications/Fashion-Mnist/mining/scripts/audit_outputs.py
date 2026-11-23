#!/usr/bin/env python3
"""Independently audit committed Fashion-FIM outputs without rerunning Eclat."""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import pathlib
import random

import supervisor


def compare_itemset_maps(set_patterns: dict[tuple[int, ...], int],
                         bitvector_patterns: dict[tuple[int, ...], int],
                         *, set_complete: bool, bitvector_complete: bool) -> dict:
    if not set_complete or not bitvector_complete:
        return {"status": "NOT_COMPARABLE", "missing_count": 0, "extra_count": 0,
                "support_mismatch_count": 0, "missing_examples": [], "extra_examples": [],
                "support_mismatch_examples": []}
    set_keys, bitvector_keys = set(set_patterns), set(bitvector_patterns)
    missing = sorted(set_keys - bitvector_keys, key=lambda key: (len(key), key))
    extra = sorted(bitvector_keys - set_keys, key=lambda key: (len(key), key))
    mismatches = sorted((key, set_patterns[key], bitvector_patterns[key])
                        for key in set_keys & bitvector_keys
                        if set_patterns[key] != bitvector_patterns[key])
    return {"status": "PASS" if not missing and not extra and not mismatches else "FAIL",
            "missing_count": len(missing), "extra_count": len(extra),
            "support_mismatch_count": len(mismatches),
            "missing_examples": [list(key) for key in missing[:10]],
            "extra_examples": [list(key) for key in extra[:10]],
            "support_mismatch_examples": [
                {"items": list(key), "set_support": left, "bitvector_support": right}
                for key, left, right in mismatches[:10]]}


def vertical_item_masks(path: pathlib.Path, expected_n: int = 70_000) -> tuple[list[int], int]:
    masks = [0] * 33
    rows = 0
    with open(path, encoding="utf-8") as stream:
        for line_number, line in enumerate(stream, 1):
            row = json.loads(line)
            if set(row) != {"tid", "image_id", "items"} or type(row["tid"]) is not int:
                raise ValueError(f"Invalid transaction row for direct support audit at line {line_number}")
            items = row["items"]
            if not isinstance(items, list) or items != sorted(set(items)):
                raise ValueError(f"Invalid transaction items for direct support audit at line {line_number}")
            rows += 1
            bit = 1 << (rows - 1)
            for item in items:
                if type(item) is not int or item not in range(1, 33):
                    raise ValueError(f"Invalid item ID for direct support audit at line {line_number}")
                masks[item] |= bit
    if rows != expected_n:
        raise ValueError(f"Expected {expected_n} transactions for support audit, got {rows}")
    return masks, rows


def direct_support_count(items: tuple[int, ...], masks: list[int]) -> int:
    if not items or tuple(sorted(set(items))) != items:
        raise ValueError(f"Itemset is not canonical: {items}")
    combined = masks[items[0]]
    for item in items[1:]:
        combined &= masks[item]
    return combined.bit_count()


def direct_support_audit(patterns: dict[tuple[int, ...], int], masks: list[int]) -> dict:
    mismatches = []
    for items, observed in patterns.items():
        direct = direct_support_count(items, masks)
        if direct != observed:
            mismatches.append({"items": list(items), "reported_support": observed,
                               "direct_support": direct})
    return {"status": "PASS" if not mismatches else "FAIL",
            "itemset_count": len(patterns), "mismatch_count": len(mismatches),
            "mismatch_examples": mismatches[:10]}


def _completed_backend_run(output_dir: pathlib.Path, min_count: int) -> dict:
    config = supervisor.load_config(output_dir)
    _manifest_path, manifest = supervisor.canonical_manifest(output_dir)
    pct = int(supervisor.FRACTIONS[min_count] * 100)
    run_id = manifest.get("canonical_runs", {}).get(f"{pct:02d}")
    if not run_id:
        return {"complete": False, "status": "NOT_RUN", "patterns": {}, "config": config,
                "sidecar": {}, "output_path": None}
    status_path = supervisor.sidecar_path(output_dir, run_id)
    if not status_path.is_file():
        return {"complete": False, "status": "NOT_RUN", "patterns": {}, "config": config,
                "sidecar": {}, "output_path": None}
    sidecar = supervisor.read_toml(status_path)
    status = sidecar.get("status", "UNKNOWN")
    complete = status in {"COMPLETED_FULL", "COMPLETED_ZERO"} and sidecar.get("final_committed") is True
    if not complete:
        return {"complete": False, "status": status, "patterns": {}, "config": config,
                "sidecar": sidecar, "output_path": None}
    output_path = pathlib.Path(config["repo_root"]) / sidecar["output_path"]
    if not output_path.is_file() or supervisor.sha256_file(output_path) != sidecar.get("output_sha256"):
        return {"complete": False, "status": "INVALID_OUTPUT", "patterns": {}, "config": config,
                "sidecar": sidecar, "output_path": output_path}
    patterns = {tuple(key[1]): support for key, support in supervisor.read_itemsets(output_path, min_count)}
    if len(patterns) != sidecar.get("total_frequent_itemsets"):
        return {"complete": False, "status": "INVALID_OUTPUT", "patterns": {}, "config": config,
                "sidecar": sidecar, "output_path": output_path}
    return {"complete": True, "status": status, "patterns": patterns, "config": config,
            "sidecar": sidecar, "output_path": output_path}


def audit_release(release_root: pathlib.Path, set_output_dir: pathlib.Path,
                  bitvector_output_dir: pathlib.Path, input_path: pathlib.Path) -> dict:
    input_path = input_path.resolve()
    input_hash = supervisor.sha256_file(input_path)
    set_config = supervisor.load_config(set_output_dir)
    bitvector_config = supervisor.load_config(bitvector_output_dir)
    if set_config.get("backend", "set") != "set" or bitvector_config.get("backend") != "bitvector":
        raise ValueError("Release backend directories have incorrect backend identity")
    for config in (set_config, bitvector_config):
        if config["input_sha256"] != input_hash:
            raise ValueError("Backend config does not identify the current TC7 transaction hash")
    masks, transaction_count = vertical_item_masks(input_path)
    comparison_rows = []
    threshold_audits = []
    all_passed = True
    for min_count in supervisor.MIN_COUNTS:
        set_run = _completed_backend_run(set_output_dir, min_count)
        bitvector_run = _completed_backend_run(bitvector_output_dir, min_count)
        parity = compare_itemset_maps(set_run["patterns"], bitvector_run["patterns"],
            set_complete=set_run["complete"], bitvector_complete=bitvector_run["complete"])
        set_direct = direct_support_audit(set_run["patterns"], masks) if set_run["complete"] else {
            "status": "NOT_RUN", "itemset_count": 0, "mismatch_count": 0, "mismatch_examples": []}
        bitvector_direct = direct_support_audit(bitvector_run["patterns"], masks) if bitvector_run["complete"] else {
            "status": "NOT_RUN", "itemset_count": 0, "mismatch_count": 0, "mismatch_examples": []}
        percentage = int(supervisor.FRACTIONS[min_count] * 100)
        threshold_audits.append({"min_count": min_count, "minsup_percent": percentage,
            "set_status": set_run["status"], "bitvector_status": bitvector_run["status"],
            "parity": parity, "set_direct_support": set_direct, "bitvector_direct_support": bitvector_direct})
        for backend, run, direct in (("set", set_run, set_direct), ("bitvector", bitvector_run, bitvector_direct)):
            sidecar = run["sidecar"]
            comparison_rows.append({
                "backend": backend, "minsup_percent": percentage, "min_count": min_count,
                "status": run["status"],
                "itemset_count": len(run["patterns"]) if run["complete"] else "NA",
                "runtime_seconds": sidecar.get("runtime_seconds", "NA"),
                "peak_rss_mib": sidecar.get("peak_rss_mb", "NA"),
                "input_sha256": input_hash,
                "source_sha256": run["config"].get("engine_source_sha256", ""),
                "direct_support_status": direct["status"], "parity_status": parity["status"],
            })
        all_passed &= parity["status"] == "PASS" and set_direct["status"] == "PASS" and bitvector_direct["status"] == "PASS"

    historical_status = "NOT_APPLICABLE"
    if input_hash == supervisor.HISTORICAL_INPUT_SHA256:
        counts = []
        for output_dir in (set_output_dir, bitvector_output_dir):
            run = _completed_backend_run(output_dir, 3_500)
            counts.append(len(run["patterns"]) if run["complete"] else None)
        historical_status = "PASS" if counts == [7_228, 7_228] else "FAIL"
        all_passed &= historical_status == "PASS"

    result = {"schema_version": 1, "audit_type": "exact_set_bitvector_release_parity",
        "status": "PASS" if all_passed else "FAIL", "input_sha256": input_hash,
        "transaction_count": transaction_count,
        "historical_7228_reference": historical_status,
        "direct_support_method": "Vertical transaction bit masks; support is the population count of item-mask intersections",
        "thresholds": threshold_audits, "comparison_rows": comparison_rows}
    mining_dir = release_root / "mining"
    mining_dir.mkdir(parents=True, exist_ok=True)
    (mining_dir / "parity_audit.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    fields = ["backend", "minsup_percent", "min_count", "status", "itemset_count", "runtime_seconds",
              "peak_rss_mib", "input_sha256", "source_sha256", "direct_support_status", "parity_status"]
    with open(mining_dir / "comparison.csv", "w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(comparison_rows)
    root = pathlib.Path(set_config["repo_root"])
    tc7_manifest_path = release_root / "transactions" / "tc7_manifest.toml"
    supervisor.atomic_toml(mining_dir / "mining_manifest.toml", {
        "schema_version": 1,
        "run_id": release_root.name,
        "configuration": "B0_K32_seed123_S0",
        "repo_root": str(root),
        "tc7_manifest_path": supervisor.relative_to(root, tc7_manifest_path),
        "tc7_manifest_sha256": supervisor.sha256_file(tc7_manifest_path) if tc7_manifest_path.is_file() else "",
        "transaction_path": supervisor.relative_to(root, input_path),
        "transaction_sha256": input_hash,
        "transaction_count": transaction_count,
        "backends": ["set", "bitvector"],
        "min_count_thresholds": list(supervisor.MIN_COUNTS),
        "source_sha256_by_backend": {
            "set": set_config.get("engine_source_sha256", ""),
            "bitvector": bitvector_config.get("engine_source_sha256", ""),
        },
        "worker_source_sha256_by_backend": {
            "set": set_config.get("worker_source_sha256", ""),
            "bitvector": bitvector_config.get("worker_source_sha256", ""),
        },
        "resource_limits": {
            "julia_threads": int(set_config.get("julia_threads", 1)),
            "memory_limit_mb_per_worker": int(set_config.get("memory_limit_mb_per_worker", 3072)),
            "wall_time_seconds_per_run": int(set_config.get("wall_time_seconds_per_run", 3600)),
            "output_limit_bytes": int(set_config.get("output_limit_bytes", 8 * 1024**3)),
            "memory_swap_max_bytes": 0,
            "execution_order": "set then bitvector; six thresholds ascending support",
        },
        "parity_audit_path": supervisor.relative_to(root, mining_dir / "parity_audit.json"),
        "comparison_csv_path": supervisor.relative_to(root, mining_dir / "comparison.csv"),
        "selected_itemsets_path": "",
        "selected_itemsets_sha256": "",
        "selected_itemset_count": 0,
        "status": result["status"],
    })
    return result


def deterministic_sample(path: pathlib.Path, min_count: int, target: int = 20) -> list[tuple[int, ...]]:
    """Reproduce the supervisor's seed-42 reservoir sample over canonical output order."""
    chooser = random.Random(42)
    sample: list[tuple[int, ...]] = []
    for index, (key, _support) in enumerate(supervisor.read_itemsets(path, min_count)):
        items = key[1]
        if index < target:
            sample.append(items)
        else:
            replacement = chooser.randrange(index + 1)
            if replacement < target:
                sample[replacement] = items
    return sample


def direct_supports(source: pathlib.Path, itemsets: set[tuple[int, ...]]) -> tuple[int, int, dict[tuple[int, ...], int], dict[str, int]]:
    wanted = {items: set(items) for items in itemsets}
    counts = {items: 0 for items in itemsets}
    transaction_count = 0
    empty_count = 0
    singleton = {item: 0 for item in range(1, 33)}
    pair_count = 0
    with source.open(encoding="utf-8") as stream:
        for line_number, line in enumerate(stream, 1):
            if not line.endswith("\n"):
                raise ValueError(f"Source JSONL is unterminated at line {line_number}")
            row = json.loads(line)
            transaction = set(row["items"])
            transaction_count += 1
            empty_count += not transaction
            for item in singleton:
                singleton[item] += item in transaction
            pair_count += {6, 26}.issubset(transaction)
            for items, item_set in wanted.items():
                counts[items] += item_set.issubset(transaction)
    guards = {
        "support_6": singleton[6],
        "support_26": singleton[26],
        "support_6_26": pair_count,
        "max_singleton_support": max(singleton.values()),
    }
    return transaction_count, empty_count, counts, guards


def audit(output_dir: pathlib.Path) -> dict:
    config = supervisor.load_config(output_dir)
    root = pathlib.Path(config["repo_root"])
    source = root / config["input_source_path"]
    observed_input_sha = supervisor.sha256_file(source)
    if observed_input_sha != config["input_sha256"]:
        raise ValueError("Locked input SHA-256 differs from config_snapshot.toml")

    manifest = supervisor.canonical_manifest(output_dir)[1]
    completed: list[dict] = []
    samples: dict[str, list[tuple[int, ...]]] = {}
    expected_supports: dict[tuple[int, ...], int] = {}
    for min_count in supervisor.MIN_COUNTS:
        percent = int(supervisor.FRACTIONS[min_count] * 100)
        run_id = manifest.get("canonical_runs", {}).get(f"{percent:02d}")
        if not run_id:
            raise ValueError(f"Missing canonical run ID for {percent}%")
        sidecar = supervisor.read_toml(supervisor.sidecar_path(output_dir, run_id))
        if sidecar.get("status") not in {"COMPLETED_FULL", "COMPLETED_ZERO"} or not sidecar.get("final_committed"):
            raise ValueError(f"Run {run_id} is not final committed")
        if not supervisor.verify_reusable(output_dir, config, sidecar):
            raise ValueError(f"Final output identity/checksum/read-back verification failed: {run_id}")
        exact_path = root / sidecar["output_path"]
        itemsets = {key[1]: support for key, support in supervisor.read_itemsets(exact_path, min_count)}
        if len(itemsets) != sidecar.get("record_count"):
            raise ValueError(f"Record count does not match sidecar: {run_id}")
        sample = deterministic_sample(exact_path, min_count)
        samples[run_id] = sample
        expected_supports.update({items: itemsets[items] for items in sample})
        completed.append({
            "minsup_count": min_count,
            "minsup_fraction": supervisor.FRACTIONS[min_count],
            "run_id": run_id,
            "sidecar_path": supervisor.relative_to(root, supervisor.sidecar_path(output_dir, run_id)),
            "output_path": sidecar["output_path"],
            "output_sha256": sidecar["output_sha256"],
            "output_size_bytes": sidecar["output_size_bytes"],
            "record_count": sidecar["record_count"],
            "status": sidecar["status"],
            "historical_production_cross_threshold_outputs_checked": sidecar.get(
                "production_commit_cross_threshold_outputs_checked",
                sidecar.get("cross_threshold_outputs_checked", "NA"),
            ),
            "historical_production_sampled_itemsets_independently_verified": sidecar.get(
                "production_commit_sampled_itemsets_independently_verified",
                sidecar.get("sampled_itemsets_independently_verified", "NA"),
            ),
            "sample_itemsets": sample,
            "sample_expected_supports": [itemsets[items] for items in sample],
        })

    guard_items = {(6,), (26,), (6, 26)}
    source_items = set(expected_supports) | guard_items
    transaction_count, empty_count, observed_supports, guards = direct_supports(source, source_items)
    sample_mismatches = 0
    for run in completed:
        sample_results = []
        for items, expected in zip(run["sample_itemsets"], run["sample_expected_supports"], strict=True):
            observed = observed_supports[tuple(items)]
            matches = observed == expected
            sample_mismatches += not matches
            sample_results.append({"items": items, "expected_support": expected,
                                   "observed_support": observed, "matches": matches})
        run["sample_results"] = sample_results
        run["sample_mismatch_count"] = sum(not row["matches"] for row in sample_results)

    cross_threshold_pairs = []
    cross_threshold_mismatches = 0
    for higher_index, higher in enumerate(completed):
        higher_count = higher["minsup_count"]
        higher_path = root / higher["output_path"]
        higher_items = {key[1]: support for key, support in supervisor.read_itemsets(higher_path, higher_count)}
        for lower in completed[higher_index + 1:]:
            lower_count = lower["minsup_count"]
            lower_path = root / lower["output_path"]
            lower_items = {key[1]: support for key, support in supervisor.read_itemsets(lower_path, lower_count)}
            missing = [list(items) for items in higher_items if items not in lower_items]
            support_mismatches = [list(items) for items in higher_items
                                  if items in lower_items and higher_items[items] != lower_items[items]]
            mismatch_count = len(missing) + len(support_mismatches)
            cross_threshold_mismatches += mismatch_count
            cross_threshold_pairs.append({
                "higher_minsup_count": higher_count,
                "lower_minsup_count": lower_count,
                "higher_pattern_count": len(higher_items),
                "lower_pattern_count": len(lower_items),
                "missing_from_lower_count": len(missing),
                "support_mismatch_count": len(support_mismatches),
                "mismatch_count": mismatch_count,
                "missing_from_lower": missing,
                "support_mismatches": support_mismatches,
                "status": "PASS" if mismatch_count == 0 else "FAIL",
            })

    expected_guards = {"support_6": 43_263, "support_26": 48_922,
                       "support_6_26": 32_266, "max_singleton_support": 48_922}
    guard_status = "PASS" if guards == expected_guards and transaction_count == 70_000 and empty_count == 0 else "FAIL"
    all_completed = len(completed) == len(supervisor.MIN_COUNTS)
    status = "PASS" if (all_completed and sample_mismatches == 0 and cross_threshold_mismatches == 0
                        and guard_status == "PASS") else "FAIL"
    return {
        "schema_version": 1,
        "audit_type": "independent_post_run_output_audit",
        "status": status,
        "created_at": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "configuration": config["configuration"],
        "source_path": config["input_source_path"],
        "source_sha256": observed_input_sha,
        "transaction_count": transaction_count,
        "empty_transaction_count": empty_count,
        "sampling_method": "Seed-42 reservoir sample of up to 20 itemsets per run, traversed in canonical JSONL order; selection reproduced from supervisor.validate_staging",
        "sampling_seed": 42,
        "independent_support_scan": {
            "method": "Direct subset scan of every locked source transaction for each selected itemset",
            "sampled_itemset_count": sum(len(run["sample_itemsets"]) for run in completed),
            "mismatch_count": sample_mismatches,
            "status": "PASS" if sample_mismatches == 0 else "FAIL",
        },
        "source_guardrails": {"expected": expected_guards, "observed": guards, "status": guard_status},
        "cross_threshold_audit": {
            "method": "Pairwise containment and support-equality comparisons over all final committed outputs, performed after the production runs",
            "pair_count": len(cross_threshold_pairs),
            "mismatch_count": cross_threshold_mismatches,
            "status": "PASS" if cross_threshold_mismatches == 0 else "FAIL",
            "pairs": cross_threshold_pairs,
        },
        "runs": completed,
        "provenance_note": (
            "Production sidecars record zero cross-threshold outputs checked. The post-run audit below independently checks all output pairs and confirms their contents, "
            "but cannot claim this check occurred before each historical commit. The original sidecars were preserved."
        ),
    }


def reconcile_sidecars(output_dir: pathlib.Path, result: dict, audit_path: pathlib.Path) -> None:
    """Atomically attach post-run audit evidence to each authoritative sidecar."""
    config = supervisor.load_config(output_dir)
    root = pathlib.Path(config["repo_root"])
    audit_sha256 = supervisor.sha256_file(audit_path)
    runs_by_min_count = {run["minsup_count"]: run for run in result["runs"]}
    pairs = result["cross_threshold_audit"]["pairs"]

    for run in result["runs"]:
        min_count = run["minsup_count"]
        sidecar_path = supervisor.sidecar_path(output_dir, run["run_id"])
        sidecar = supervisor.read_toml(sidecar_path)
        higher_pairs = [pair for pair in pairs if pair["lower_minsup_count"] == min_count]
        higher_minsup_counts = [pair["higher_minsup_count"] for pair in higher_pairs]
        higher_run_ids = [runs_by_min_count[count]["run_id"] for count in higher_minsup_counts]
        previous_cross_count = sidecar.get(
            "production_commit_cross_threshold_outputs_checked",
            sidecar.get("cross_threshold_outputs_checked", 0),
        )
        previous_sample_count = sidecar.get(
            "production_commit_sampled_itemsets_independently_verified",
            sidecar.get("sampled_itemsets_independently_verified", 0),
        )
        sidecar.update({
            "production_commit_cross_threshold_outputs_checked": previous_cross_count,
            "production_commit_sampled_itemsets_independently_verified": previous_sample_count,
            "post_run_audit_status": result["status"],
            "post_run_audit_path": supervisor.relative_to(root, audit_path),
            "post_run_audit_sha256": audit_sha256,
            "post_run_audit_completed_at": result["created_at"],
            "post_run_audit_method": "independent_post_run_output_audit; no Eclat rerun",
            "audit_status": result["status"],
            "sampled_itemsets_independently_verified": len(run["sample_itemsets"]),
            "audit_sample_seed": result["sampling_seed"],
            "audit_sample_itemsets": run["sample_itemsets"],
            "audit_sample_expected_supports": run["sample_expected_supports"],
            "audit_sample_observed_supports": [row["observed_support"] for row in run["sample_results"]],
            "audit_sample_mismatch_count": run["sample_mismatch_count"],
            "cross_threshold_outputs_checked": len(higher_pairs),
            "cross_threshold_min_counts_checked": higher_minsup_counts,
            "cross_threshold_run_ids_checked": higher_run_ids,
            "cross_threshold_mismatch_count": sum(pair["mismatch_count"] for pair in higher_pairs),
            "notes": (
                "Final JSONL was independently revalidated after production: exact identity/checksum/schema, "
                "seed-42 source-support sample, and all available cross-threshold pairs passed. "
                f"The original production commit had {previous_cross_count} cross-threshold checks; "
                "see post_run_audit_path for the timing and remediation record."
            ),
        })
        supervisor.atomic_toml(sidecar_path, sidecar)

    supervisor.rebuild_runs_csv(output_dir)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir")
    parser.add_argument("--release-root")
    parser.add_argument("--set-output-dir")
    parser.add_argument("--bitvector-output-dir")
    parser.add_argument("--input-path")
    args = parser.parse_args()
    if args.release_root:
        required = (args.set_output_dir, args.bitvector_output_dir, args.input_path)
        if not all(required):
            parser.error("--release-root requires --set-output-dir, --bitvector-output-dir, and --input-path")
        result = audit_release(pathlib.Path(args.release_root).resolve(),
            pathlib.Path(args.set_output_dir).resolve(), pathlib.Path(args.bitvector_output_dir).resolve(),
            pathlib.Path(args.input_path).resolve())
        print(json.dumps({"status": result["status"], "transaction_count": result["transaction_count"],
                          "thresholds": len(result["thresholds"]),
                          "historical_7228_reference": result["historical_7228_reference"],
                          "artifact": str(pathlib.Path(args.release_root).resolve() / "mining" / "parity_audit.json")},
                         ensure_ascii=False, indent=2))
        if result["status"] != "PASS":
            raise SystemExit(1)
        return
    if not args.output_dir:
        parser.error("provide --output-dir for the legacy audit or --release-root for exact backend comparison")
    output_dir = pathlib.Path(args.output_dir).resolve()
    result = audit(output_dir)
    audit_path = output_dir / "analysis" / "independent_output_audit.json"
    supervisor.atomic_write(audit_path, json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    if result["status"] == "PASS":
        reconcile_sidecars(output_dir, result, audit_path)
    print(json.dumps({"status": result["status"],
                      "sampled_itemsets": result["independent_support_scan"]["sampled_itemset_count"],
                      "sample_mismatch_count": result["independent_support_scan"]["mismatch_count"],
                      "cross_threshold_pairs": result["cross_threshold_audit"]["pair_count"],
                      "cross_threshold_mismatch_count": result["cross_threshold_audit"]["mismatch_count"],
                      "sidecars_reconciled": result["status"] == "PASS",
                      "artifact": str(audit_path)}, ensure_ascii=False, indent=2))
    if result["status"] != "PASS":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
