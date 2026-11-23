#!/usr/bin/env python3
"""Choose a small, deterministic, diverse set of Set-backend patterns."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import pathlib

import supervisor

TARGET_COUNT = 4
MINIMUM_COUNT = 3
STRICT_JACCARD_LIMIT = 0.80
RELAXED_JACCARD_LIMIT = 0.90
RULE_VERSION = "v1.3-small-sample-length-coverage-1"
LENGTH_CELLS = (("1", "low"), ("1", "mid"), ("1", "high"),
                ("2", "low"), ("2", "mid"), ("2", "high"),
                (">=3", "low"), (">=3", "mid"), (">=3", "high"))
LENGTH_COVERAGE_CELLS = (("1", "high"), ("2", "mid"), (">=3", "low"))


def itemset_id(items: tuple[int, ...]) -> str:
    return "P-" + hashlib.sha256(",".join(map(str, items)).encode("ascii")).hexdigest()


def write_csv(path: pathlib.Path, fields: list[str], rows) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    with open(temporary, "w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
        stream.flush()
    temporary.replace(path)


def jaccard(left: tuple[int, ...], right: tuple[int, ...]) -> float:
    a, b = set(left), set(right)
    return len(a & b) / len(a | b)


def support_tertiles(candidates: list[dict]) -> dict[int, str]:
    """Split distinct support counts into thirds; equal counts stay together."""
    supports = sorted({row["support_count"] for row in candidates})
    q1, q2 = math.ceil(len(supports) / 3), math.ceil(2 * len(supports) / 3)
    return {support: "low" if rank <= q1 else "mid" if rank <= q2 else "high"
            for rank, support in enumerate(supports, 1)}


def candidate_buckets(candidates: list[dict]) -> dict[str, tuple[str, str]]:
    support_buckets = support_tertiles(candidates)
    result = {}
    for candidate in candidates:
        length = candidate["length"]
        length_bucket = "1" if length == 1 else "2" if length == 2 else ">=3"
        result[candidate["pattern_id"]] = (length_bucket, support_buckets[candidate["support_count"]])
    return result


def validate_catalog(candidates: list[dict]) -> list[dict]:
    """Validate canonical rows and collapse repeated threshold observations."""
    catalog: dict[tuple[int, ...], dict] = {}
    for candidate in candidates:
        items = tuple(candidate["items"])
        support = candidate["support_count"]
        minsup = candidate["minsup_percent"]
        if not items or items != tuple(sorted(set(items))) or any(type(item) is not int or item not in range(1, 33) for item in items):
            raise ValueError(f"Invalid or non-canonical itemset: {items}")
        if type(support) is not int or not 0 <= support <= 70_000:
            raise ValueError(f"Invalid support count for {items}: {support}")
        if minsup not in {80, 60, 40, 20, 10, 5}:
            raise ValueError(f"Invalid support threshold for {items}: {minsup}")
        identifier = itemset_id(items)
        if candidate.get("pattern_id", identifier) != identifier:
            raise ValueError(f"Pattern ID mismatch for {items}")
        previous = catalog.get(items)
        if previous and previous["support_count"] != support:
            raise ValueError(f"Support differs across thresholds for {items}")
        if previous:
            previous["observed_minsups"].add(minsup)
        else:
            catalog[items] = {"items": items, "length": len(items), "support_count": support,
                              "pattern_id": identifier, "observed_minsups": {minsup}}
    if not catalog:
        raise ValueError("The completed Set runs produced no frequent itemsets")
    return [{**row, "minsup_percent": max(row["observed_minsups"]),
             "support_fraction": row["support_count"] / 70_000}
            for row in sorted(catalog.values(), key=lambda row: (row["length"], row["items"]))]


def selection_pass(candidates: list[dict], target: int, threshold: float) -> list[dict]:
    buckets = candidate_buckets(candidates)
    cells = {cell: [] for cell in LENGTH_CELLS}
    for candidate in candidates:
        length_bucket, support_bucket = buckets[candidate["pattern_id"]]
        cells[(length_bucket, support_bucket)].append(candidate)
    for pool in cells.values():
        pool.sort(key=lambda row: (-row["support_count"], row["length"], row["items"]))

    selected, considered = [], set()

    def take_from_cell(cell: tuple[str, str]) -> bool:
        for candidate in cells[cell]:
            identifier = candidate["pattern_id"]
            if identifier in considered:
                continue
            considered.add(identifier)
            diversity = max((jaccard(candidate["items"], row["items"]) for row in selected), default=0.0)
            if diversity <= threshold:
                selected.append({**candidate, "length_bucket": cell[0],
                                 "support_bucket": cell[1],
                                 "diversity_max_jaccard": diversity})
                return True
        return False

    # A four-pattern sample must cover short, pair, and longer itemsets when available.
    for cell in LENGTH_COVERAGE_CELLS:
        take_from_cell(cell)
        if len(selected) >= target:
            return selected

    # Fill remaining slots with the original fixed nine-cell length-major grid.
    while len(selected) < target:
        progress = False
        for cell in LENGTH_CELLS:
            progress = take_from_cell(cell) or progress
            if len(selected) >= target:
                break
        if not progress:
            break
    return selected


def select_representatives(candidates: list[dict], target: int = TARGET_COUNT,
                           minimum: int = MINIMUM_COUNT) -> tuple[list[dict], float, bool]:
    if target != TARGET_COUNT or minimum != MINIMUM_COUNT:
        raise ValueError(f"Release selection is fixed to {MINIMUM_COUNT}–{TARGET_COUNT} patterns")
    catalog = validate_catalog(candidates)
    selected = selection_pass(catalog, target, STRICT_JACCARD_LIMIT)
    threshold, relaxed = STRICT_JACCARD_LIMIT, False
    if len(selected) < target:
        selected = selection_pass(catalog, target, RELAXED_JACCARD_LIMIT)
        threshold, relaxed = RELAXED_JACCARD_LIMIT, True
    if len(selected) < minimum:
        raise ValueError(f"Only {len(selected)} patterns meet the selection rules; at least {minimum} are required")
    return selected, threshold, relaxed


def completed_set_catalog(set_output_dir: pathlib.Path) -> tuple[list[dict], dict]:
    config = supervisor.load_config(set_output_dir)
    _manifest_path, manifest = supervisor.canonical_manifest(set_output_dir)
    if config.get("backend", "set") != "set":
        raise ValueError("Representative pattern selection requires Set backend results")
    source_root = pathlib.Path(config["repo_root"])
    observations = []
    output_hashes = {}
    for min_count in supervisor.MIN_COUNTS:
        minsup_percent = int(round(supervisor.FRACTIONS[min_count] * 100))
        run_id = manifest.get("canonical_runs", {}).get(f"{minsup_percent:02d}")
        if not run_id:
            raise ValueError(f"Set backend has no canonical run at {minsup_percent}% support")
        sidecar_path = supervisor.sidecar_path(set_output_dir, run_id)
        sidecar = supervisor.read_toml(sidecar_path)
        if sidecar.get("status") not in {"COMPLETED_FULL", "COMPLETED_ZERO"} or not sidecar.get("final_committed"):
            raise ValueError(f"Set backend run is incomplete at {minsup_percent}% support")
        output_path = source_root / sidecar["output_path"]
        if supervisor.sha256_file(output_path) != sidecar.get("output_sha256"):
            raise ValueError(f"Set output checksum mismatch at {minsup_percent}% support")
        output_hashes[str(minsup_percent)] = sidecar["output_sha256"]
        for key, support in supervisor.read_itemsets(output_path, min_count):
            observations.append({"items": key[1], "support_count": support,
                                 "minsup_percent": minsup_percent})
    return validate_catalog(observations), output_hashes


def auto_select(set_output_dir: pathlib.Path, release_root: pathlib.Path) -> dict:
    candidates, source_hashes = completed_set_catalog(set_output_dir)
    selected, threshold, relaxed = select_representatives(candidates)
    candidate_group_by_id = candidate_buckets(candidates)
    mining_dir = release_root / "mining"
    catalog_rows = []
    selected_by_id = {row["pattern_id"]: (order, row)
                      for order, row in enumerate(selected, 1)}
    for order, candidate in enumerate(candidates, 1):
        chosen = selected_by_id.get(candidate["pattern_id"])
        selected_row = chosen[1] if chosen else None
        catalog_rows.append({
            "candidate_order": order,
            "selected": "true" if chosen else "false",
            "selection_order": chosen[0] if chosen else "",
            "pattern_id": candidate["pattern_id"],
            "backend": "set",
            "minsup_percent": candidate["minsup_percent"],
            "items": json.dumps(list(candidate["items"]), separators=(",", ":")),
            "length": candidate["length"],
            "support_count": candidate["support_count"],
            "support_fraction": candidate["support_fraction"],
            "length_bucket": candidate_group_by_id[candidate["pattern_id"]][0],
            "support_bucket": candidate_group_by_id[candidate["pattern_id"]][1],
            "diversity_max_jaccard": selected_row["diversity_max_jaccard"] if selected_row else "",
        })
    catalog_path = mining_dir / "itemset_selection_candidates.csv"
    catalog_fields = ["candidate_order", "selected", "selection_order", "pattern_id", "backend",
                      "minsup_percent", "items", "length", "support_count", "support_fraction",
                      "length_bucket", "support_bucket", "diversity_max_jaccard"]
    write_csv(catalog_path, catalog_fields, catalog_rows)

    selected_path = mining_dir / "selected_itemsets.csv"
    selected_fields = ["selection_order", "backend", "minsup_percent", "items", "support_count", "pattern_id"]
    write_csv(selected_path, selected_fields, [
        {"selection_order": index, "backend": "set", "minsup_percent": row["minsup_percent"],
         "items": json.dumps(list(row["items"]), separators=(",", ":")),
         "support_count": row["support_count"], "pattern_id": row["pattern_id"]}
        for index, row in enumerate(selected, 1)])

    representative_path = mining_dir / "representative_patterns.csv"
    representative_fields = ["pattern_id", "items", "length", "support_count", "support_fraction",
        "reference_minsup", "selection_order", "support_bucket", "length_bucket",
        "diversity_max_jaccard", "rule_version", "selection_notes"]
    notes = ("Selected after length-coverage cells (1/high), (2/mid), and (>=3/low), then the fixed 9-cell grid; "
             f"Jaccard <= {threshold:.2f}; support ties remain in the same tertile.")
    write_csv(representative_path, representative_fields, [
        {"pattern_id": row["pattern_id"], "items": ";".join(map(str, row["items"])),
         "length": row["length"], "support_count": row["support_count"],
         "support_fraction": row["support_fraction"], "reference_minsup": f"{row['minsup_percent']}%",
         "selection_order": index, "support_bucket": row["support_bucket"],
         "length_bucket": row["length_bucket"],
         "diversity_max_jaccard": f"{row['diversity_max_jaccard']:.6f}",
         "rule_version": RULE_VERSION, "selection_notes": notes}
        for index, row in enumerate(selected, 1)])

    mining_manifest_path = mining_dir / "mining_manifest.toml"
    manifest = supervisor.read_toml(mining_manifest_path)
    repo_root = pathlib.Path(manifest["repo_root"]).resolve()
    manifest.update({
        "selected_itemsets_path": supervisor.relative_to(repo_root, selected_path),
        "selected_itemsets_sha256": supervisor.sha256_file(selected_path),
        "selected_itemset_count": len(selected),
        "representative_patterns_path": supervisor.relative_to(repo_root, representative_path),
        "representative_patterns_sha256": supervisor.sha256_file(representative_path),
        "candidate_catalog_path": supervisor.relative_to(repo_root, catalog_path),
        "candidate_catalog_sha256": supervisor.sha256_file(catalog_path),
    })
    supervisor.atomic_toml(mining_manifest_path, manifest)

    selection_manifest = {
        "rule_version": RULE_VERSION,
        "target_requested": TARGET_COUNT,
        "minimum_required": MINIMUM_COUNT,
        "target_selected": len(selected),
        "unique_pattern_count": len(candidates),
        "strict_jaccard_limit": STRICT_JACCARD_LIMIT,
        "relaxed_jaccard_limit": RELAXED_JACCARD_LIMIT,
        "length_coverage_cells": ["1/high", "2/mid", ">=3/low"],
        "fill_order": "fixed length-major 9-cell round-robin",
        "actual_jaccard_threshold": threshold,
        "relaxation_used": relaxed,
        "catalog_sha256": supervisor.sha256_file(catalog_path),
        "source_output_hashes": source_hashes,
        "selection_order": [row["pattern_id"] for row in selected],
        "selection_notes": ("Selected four patterns." if len(selected) == TARGET_COUNT else
                            "Selected three patterns; no fourth pattern passed the diversity rule."),
    }
    supervisor.atomic_toml(mining_dir / "selection_manifest.toml", selection_manifest)
    return {"candidate_count": len(candidates), "selected_count": len(selected),
            "catalog_path": catalog_path, "selected_path": selected_path,
            "representative_path": representative_path,
            "selection_manifest_path": mining_dir / "selection_manifest.toml",
            "jaccard_threshold": threshold, "relaxation_used": relaxed}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release-root", required=True)
    parser.add_argument("--set-output-dir", required=True)
    args = parser.parse_args()
    result = auto_select(pathlib.Path(args.set_output_dir).resolve(), pathlib.Path(args.release_root).resolve())
    print(json.dumps({key: str(value) if isinstance(value, pathlib.Path) else value
                      for key, value in result.items()}, sort_keys=True))


if __name__ == "__main__":
    main()
