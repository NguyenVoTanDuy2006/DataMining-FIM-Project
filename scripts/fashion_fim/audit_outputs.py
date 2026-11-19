#!/usr/bin/env python3
"""Independently audit committed Fashion-FIM outputs without rerunning Eclat."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import random

import supervisor


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
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()
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
