#!/usr/bin/env python3
"""P1-only smoke checks on toy transactions and simulated recovery states."""

from __future__ import annotations

import csv
import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile
import tomllib
import time

import supervisor
import analysis
import report
import interpretation


def run_worker(root: pathlib.Path, julia: str, source: pathlib.Path, staging: pathlib.Path,
               result_path: pathlib.Path, min_count: int, output_limit: int, expected_n: int) -> subprocess.CompletedProcess:
    return subprocess.run([julia, f"--project={root}", "--startup-file=no", "--history-file=no", "-t", "1",
        str(root / "scripts" / "fashion_fim" / "run_mining_worker.jl"), str(source), str(staging),
        str(result_path), str(min_count), str(output_limit), str(expected_n)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def smoke_worker(root: pathlib.Path, julia: str, temp: pathlib.Path) -> list[str]:
    toy = temp / "toy_transactions.jsonl"
    rows = [
        {"tid": 101, "image_id": 501, "items": [1, 2]},
        {"tid": 102, "image_id": 502, "items": [1, 2, 3]},
        {"tid": 103, "image_id": 503, "items": [1, 3]},
        {"tid": 104, "image_id": 504, "items": [2, 3]},
        {"tid": 105, "image_id": 505, "items": [1, 2]},
        {"tid": 106, "image_id": 506, "items": []},
    ]
    toy.write_text("".join(json.dumps(row, separators=(",", ":")) + "\n" for row in rows), encoding="utf-8")
    loader = subprocess.run([julia, f"--project={root}", "--startup-file=no", "-e",
        f'include(raw"{root / "src/fashion_fim/FashionFIMWorkflow.jl"}"); using .FashionFIMWorkflow; '
        f'x=load_transactions(raw"{toy}"; expected_n=6, unique_mapping=true); '
        '(@assert x.tid[1]==101 && x.image_id[1]==501 && x.empty_count==1 && x.singleton_support[1]==4)'],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if loader.returncode != 0:
        raise AssertionError(f"Julia JSONL loader smoke failed: {loader.stderr}")

    stage = temp / "patterns.jsonl.staging"
    result = temp / "worker_result.toml"
    full = run_worker(root, julia, toy, stage, result, 2, 1024 * 1024, 6)
    if full.returncode != 0:
        raise AssertionError(f"Toy Eclat worker failed: {full.stderr}")
    meta = tomllib.loads(result.read_text(encoding="utf-8"))
    patterns = [json.loads(line) for line in stage.read_text(encoding="utf-8").splitlines()]
    keys = [(entry["length"], tuple(entry["items"])) for entry in patterns]
    if meta["worker_status"] != "COMPLETED_FULL" or len(patterns) != 6 or keys != sorted(keys):
        raise AssertionError("Toy worker count/status/canonical sorting did not match expectations")
    if any(abs(entry["support_fraction"] - entry["support_count"] / 6) > 1e-15 for entry in patterns):
        raise AssertionError("Toy support fraction did not use transaction count")

    zero_stage, zero_result = temp / "zero.jsonl.staging", temp / "zero.toml"
    zero = run_worker(root, julia, toy, zero_stage, zero_result, 7, 1024, 6)
    zero_meta = tomllib.loads(zero_result.read_text(encoding="utf-8"))
    if zero.returncode != 0 or zero_meta["worker_status"] != "COMPLETED_ZERO" or zero_meta["record_count"] != 0 or zero_meta["max_itemset_length"] != 0 or zero_stage.stat().st_size != 0:
        raise AssertionError("Completed-zero smoke contract failed")

    limited_stage, limited_result = temp / "limited.jsonl.staging", temp / "limited.toml"
    limited = run_worker(root, julia, toy, limited_stage, limited_result, 2, 1, 6)
    limited_meta = tomllib.loads(limited_result.read_text(encoding="utf-8"))
    if limited.returncode != 73 or limited_meta["worker_status"] != "OUTPUT_LIMIT" or limited_stage.stat().st_size > 1:
        raise AssertionError("Output byte limit smoke contract failed")

    api_code = (
        "using EclatFIM; t=[[1,2],[1,2],[1,3]]; "
        "p=EclatFIM.mine(t,1); @assert p isa Dict{Tuple{Vararg{Int}},Int}; "
        "capped=EclatFIM.mine(t,1;max_length=1); @assert all(length(k)==1 for k in keys(capped)); "
        "overflow=false; try EclatFIM.mine(t,1;max_itemsets=1) catch e; global overflow=e isa OverflowError && occursin(\"max_itemsets exceeded\",sprint(showerror,e)); end; @assert overflow; "
        "timed=false; try EclatFIM.mine(t,1;deadline=time()-1) catch e; global timed=e isa InterruptException; end; @assert timed; "
        "println(\"public API semantics PASS\")"
    )
    api = subprocess.run([julia, f"--project={root}", "--startup-file=no", "-e", api_code],
                         text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if api.returncode != 0:
        raise AssertionError(f"Eclat public API semantics smoke failed: {api.stderr}")
    return ["Julia loader keeps row/TID/image mapping", "public Eclat API returns expected Dict and optional-limit semantics",
            "toy full JSONL output is sorted and support fractions are transaction-based",
            "COMPLETED_ZERO writes a 0-byte exact staging file", "output_limit_bytes stops before overflow"]


def smoke_systemd_budgets() -> list[str]:
    suffix = str(os_getpid())
    unit = f"fim-smoke-budget-{suffix}"
    run = subprocess.run(["systemd-run", "--user", "--no-block", f"--unit={unit}",
        "--property=MemoryMax=128M", "--property=MemorySwapMax=0", "--property=RuntimeMaxSec=10s",
        "--", "/bin/sleep", "30"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if run.returncode != 0:
        raise AssertionError(f"Bounded systemd probe could not execute: {run.stderr}")
    props = supervisor.systemctl_show(unit + ".service")
    if int(props.get("MemoryMax", "0")) != 128 * 1024**2 or int(props.get("MemorySwapMax", "-1")) != 0:
        raise AssertionError(f"Systemd worker memory cap not effective: {props}")
    subprocess.run(["systemctl", "--user", "stop", unit + ".service"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    timeout_unit = f"fim-smoke-timeout-{suffix}"
    timeout = subprocess.run(["systemd-run", "--user", "--no-block", f"--unit={timeout_unit}",
        "--property=RuntimeMaxSec=2s", "--property=TimeoutStopSec=1s", "--", "/bin/sleep", "30"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if timeout.returncode != 0:
        raise AssertionError(f"Systemd timeout probe could not start: {timeout.stderr}")
    deadline = time.monotonic() + 10
    timeout_props = {}
    while time.monotonic() < deadline:
        timeout_props = supervisor.systemctl_show(timeout_unit + ".service")
        if timeout_props.get("Result") == "timeout":
            break
        time.sleep(0.2)
    if timeout_props.get("Result") != "timeout":
        raise AssertionError(f"Systemd wall watchdog did not record timeout: {timeout_props}; {timeout.stderr}")
    subprocess.run(["systemctl", "--user", "reset-failed", timeout_unit + ".service"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return ["systemd user service enforces MemoryMax and MemorySwapMax=0",
            "systemd RuntimeMaxSec produces an explicit timeout result"]


def os_getpid() -> int:
    import os
    return os.getpid()


def smoke_crash_windows(temp: pathlib.Path) -> list[str]:
    root = temp / "recovery-root"
    output = root / "results/fashion/fim/B0_K32_seed123_S0"
    run_ids = {f"{int(supervisor.FRACTIONS[count] * 100):02d}": f"smoke_{count}" for count in supervisor.MIN_COUNTS}
    config = {"configuration": "B0_K32_seed123_S0", "input_sha256": "a" * 64,
        "engine_revision": "smoke-engine", "engine_source_sha256": "b" * 64,
        "budget_revision": "smoke-b1", "repo_root": str(root), "output_limit_bytes": 1024}
    (output / "mining/runs").mkdir(parents=True, exist_ok=True)
    (output / "mining/itemsets").mkdir(parents=True, exist_ok=True)
    manifest = {"schema_version": 1, "input_sha256": config["input_sha256"],
                "canonical_runs": run_ids}
    (output / "report").mkdir(parents=True, exist_ok=True)
    supervisor.atomic_toml(output / "report" / "experiment_manifest.toml", manifest)
    for count in supervisor.MIN_COUNTS:
        pct = int(supervisor.FRACTIONS[count] * 100)
        run_id = run_ids[f"{pct:02d}"]
        path = supervisor.sidecar_path(output, run_id)
        path.parent.mkdir(parents=True, exist_ok=True)
        supervisor.atomic_toml(path, supervisor.new_sidecar(run_id, count, config, f"mining/runs/{run_id}/worker_stdout.log"))

    # Crash window 1: staging exists but no exact rename or final sidecar.
    run_80 = run_ids["80"]
    side_80 = supervisor.sidecar_path(output, run_80)
    (side_80.parent / "patterns.jsonl.staging").write_text('{"items":[6],"length":1}\n', encoding="utf-8")
    record_80 = supervisor.read_toml(side_80)
    if supervisor.verify_reusable(output, config, record_80):
        raise AssertionError("Crash after staging was incorrectly reused")

    # Crash window 2: exact file renamed, final sidecar not written; quarantine it.
    exact = output / "mining/itemsets/minsup_80.jsonl"
    exact.write_bytes(b"")
    record_80.update({"phase": "COMMITTING", "candidate_output_path": "results/fashion/fim/B0_K32_seed123_S0/mining/itemsets/minsup_80.jsonl"})
    supervisor.atomic_toml(side_80, record_80)
    if supervisor.verify_reusable(output, config, record_80):
        raise AssertionError("Crash after rename was incorrectly reused")
    quarantine = supervisor.quarantine_orphan(exact, output, run_80)
    if exact.exists() or not quarantine.is_file():
        raise AssertionError("Orphan exact-looking output was not quarantined")

    # Crash window 3: final sidecar exists, CSV is missing; verify and rebuild without mining.
    exact.write_bytes(b"")
    record_80.update({"phase": "FINAL", "status": "COMPLETED_ZERO", "final_committed": True,
        "audit_status": "PASS", "output_path": "results/fashion/fim/B0_K32_seed123_S0/mining/itemsets/minsup_80.jsonl",
        "output_sha256": hashlib.sha256(b"").hexdigest(), "output_size_bytes": 0,
        "record_count": 0, "total_frequent_itemsets": 0, "max_itemset_length": 0,
        "engine_revision": config["engine_revision"], "engine_source_sha256": config["engine_source_sha256"],
        "sampled_itemsets_independently_verified": 0, "audit_sample_seed": 42,
        "audit_sample_itemsets": [], "audit_sample_expected_supports": [],
        "audit_sample_observed_supports": [], "audit_sample_mismatch_count": 0,
        "cross_threshold_outputs_checked": 0, "cross_threshold_min_counts_checked": [],
        "cross_threshold_run_ids_checked": [], "cross_threshold_mismatch_count": 0,
        "input_sha256": config["input_sha256"], "budget_revision": config["budget_revision"]})
    supervisor.atomic_toml(side_80, record_80)
    (output / "mining/runs.csv").unlink(missing_ok=True)
    if not supervisor.verify_reusable(output, config, supervisor.read_toml(side_80)):
        raise AssertionError("Final sidecar with matching zero-byte output was not reusable")
    supervisor.rebuild_runs_csv(output)
    with open(output / "mining/runs.csv", newline="", encoding="utf-8") as stream:
        rows = list(csv.DictReader(stream))
    if len(rows) != 6 or rows[0]["status"] != "COMPLETED_ZERO" or rows[0]["total_frequent_itemsets"] != "0":
        raise AssertionError("CSV was not rebuilt from the authoritative final sidecar")
    return ["crash after staging is not reusable", "crash after exact rename quarantines orphan output",
            "crash after final sidecar rebuilds the six-row CSV and reuses the verified output"]


def smoke_worker_launch_intent(temp: pathlib.Path) -> list[str]:
    root = temp / "launch-root"
    output = root / "results/fashion/fim/B0_K32_seed123_S0"
    output.mkdir(parents=True)
    (output / "report").mkdir()
    source = root / "toy.jsonl"
    source.write_text("toy input\n", encoding="utf-8")
    digest = supervisor.sha256_file(source)
    config = {"configuration": "B0_K32_seed123_S0", "repo_root": str(root),
        "input_source_path": "toy.jsonl", "input_sha256": digest, "engine_revision": "smoke-engine",
        "engine_source_sha256": "e" * 64, "budget_revision": "smoke-b1", "julia_executable": "/usr/bin/julia",
        "memory_limit_mb_per_worker": 128, "wall_time_seconds_per_run": 30, "output_limit_bytes": 1024,
        "process_path": "/usr/bin:/bin", "home_path": str(root), "julia_depot_path": str(root / "depot"),
        "julia_load_path": "@:@stdlib"}
    supervisor.atomic_toml(output / "config_snapshot.toml", config)
    run_ids = {f"{int(supervisor.FRACTIONS[count] * 100):02d}": f"launch_{count}" for count in supervisor.MIN_COUNTS}
    supervisor.atomic_toml(output / "report" / "experiment_manifest.toml",
        {"input_sha256": digest, "canonical_runs": run_ids})
    for count in supervisor.MIN_COUNTS:
        pct = int(supervisor.FRACTIONS[count] * 100)
        run_id = run_ids[f"{pct:02d}"]
        sidecar = supervisor.sidecar_path(output, run_id)
        sidecar.parent.mkdir(parents=True, exist_ok=True)
        supervisor.atomic_toml(sidecar, supervisor.new_sidecar(run_id, count, config,
            f"mining/runs/{run_id}/worker_stdout.log"))

    status_file = supervisor.sidecar_path(output, run_ids["80"])
    observed_phases = []
    original_run = supervisor.subprocess.run
    original_monitor = supervisor.monitor_worker
    def fake_run(command, **kwargs):
        observed_phases.append(supervisor.read_toml(status_file).get("phase"))
        return type("Result", (), {"returncode": 0, "stdout": "accepted", "stderr": ""})()
    supervisor.subprocess.run = fake_run
    supervisor.monitor_worker = lambda *args, **kwargs: args[5]
    try:
        started = supervisor.launch_worker(root, output, supervisor.load_config(output), run_ids["80"],
            56_000, supervisor.read_toml(status_file), status_file)
    finally:
        supervisor.subprocess.run = original_run
        supervisor.monitor_worker = original_monitor
    if observed_phases != ["LAUNCHING"] or started.get("phase") != "RUNNING":
        raise AssertionError(f"Worker spawn preceded persisted launch intent: {observed_phases}, {started}")
    return ["worker launch intent is persisted before systemd-run can spawn the Julia worker"]


def smoke_status_precedence() -> list[str]:
    cases = [
        ("FAIL", "PASS", "PASS", "PASS", "FAILED_VALIDATION"),
        ("PASS", "PASS", "NEEDS_REVISION", "PASS", "REVISION_REQUIRED"),
        ("FAIL", "PASS", "PARTIAL_MISSING_ASSET", "PASS", "PARTIAL_MIXED"),
        ("PASS", "PASS", "PARTIAL_MISSING_ASSET", "PASS", "PARTIAL_INTERPRETATION"),
        ("PASS", "UNVERIFIED", "PASS", "PASS", "PARTIAL_EXECUTION_UNVERIFIED"),
    ]
    for mining, execution, interpretation, audit, expected in cases:
        actual = report.overall_status(mining, execution, interpretation, audit)
        if actual != expected:
            raise AssertionError(f"Status precedence mismatch: {mining, execution, interpretation, audit} -> {actual}, expected {expected}")
    return ["overall status precedence follows v1.3 single-issue and mixed-issue rules"]


def smoke_missing_asset_policy(temp: pathlib.Path) -> list[str]:
    source = temp / "missing-asset-source"
    raw = temp / "missing-asset-raw"
    source.mkdir()
    raw.mkdir()
    supervisor.atomic_toml(source / "config_snapshot.toml", {"data_archive_sha256": {}})
    assets = interpretation.verify_raw_assets(source, raw)
    if (assets["pixels"] is not None or assets["labels"] is not None
            or set(assets["missing_image_archives"]) != {"train-images-idx3-ubyte.gz", "t10k-images-idx3-ubyte.gz"}
            or set(assets["missing_label_archives"]) != {"train-labels-idx1-ubyte.gz", "t10k-labels-idx1-ubyte.gz"}):
        raise AssertionError("Missing raw IDX archives were not returned as blockers")
    blockers = interpretation.collect_visual_asset_blockers(False, assets, source / "patch_assignments.csv")
    if ("MISSING_CODEBOOK_OR_CENTROID_EXPORT" not in blockers
            or "MISSING_PATCH_ASSIGNMENTS" not in blockers
            or len([row for row in blockers if row.startswith("MISSING_RAW_IMAGE:")]) != 2):
        raise AssertionError("Missing codebook/image/patch assets did not disable only visual evidence")
    metadata = {1: {"image_id": 1, "original_split": "train", "original_index": 1, "class_label": None}}
    totals, labels_available, provenance = interpretation.attach_verified_labels(metadata, assets)
    if totals or labels_available or "BLOCKED_MISSING_LABELS" not in provenance:
        raise AssertionError("Missing labels were not reported without fabricating class counts")
    if interpretation.load_centroids(source / "missing-centroids.csv") is not None:
        raise AssertionError("Missing centroid export should be an unavailable visual asset")
    return ["missing image, label, codebook and patch assets are explicit blockers; no fake labels or centroids are produced"]


def smoke_selection() -> list[str]:
    same_support = [
        {"pattern_id": "tie-z", "items": [3], "length": 1, "support_count": 10},
        {"pattern_id": "tie-m", "items": [2], "length": 1, "support_count": 10},
        {"pattern_id": "tie-a", "items": [1], "length": 1, "support_count": 10},
    ]
    selected = analysis.deterministic_selection_for_test(same_support, 3, 0.80)
    selected_again = analysis.deterministic_selection_for_test(list(reversed(same_support)), 3, 0.80)
    if ([row["pattern_id"] for row in selected] != ["tie-a", "tie-m", "tie-z"]
            or {row["support_bucket"] for row in selected} != {"low"}
            or [row["pattern_id"] for row in selected] != [row["pattern_id"] for row in selected_again]):
        raise AssertionError("Same-support bucket or deterministic lexical item tie failed")

    cell_candidates = []
    expected_cells = []
    next_item = 100
    for length_bucket, support_bucket in analysis.LENGTH_CELLS:
        length = 1 if length_bucket == "1" else 2 if length_bucket == "2" else 3
        support = {"low": 10, "mid": 20, "high": 30}[support_bucket]
        items = list(range(next_item, next_item + length))
        next_item += length
        cell_candidates.append({"pattern_id": f"{length_bucket}-{support_bucket}", "items": items,
                                "length": length, "support_count": support})
        expected_cells.append(f"{length_bucket}-{support_bucket}")
    grid_selected = analysis.deterministic_selection_for_test(cell_candidates, 9, 0.80)
    if [row["pattern_id"] for row in grid_selected] != expected_cells:
        raise AssertionError("Selection did not visit all nine length/support cells in fixed order")

    near = [
        {"pattern_id": "near-a", "items": list(range(1, 11)), "length": 10, "support_count": 100},
        {"pattern_id": "near-b", "items": list(range(1, 10)) + [11], "length": 10, "support_count": 100},
    ]
    strict = analysis.deterministic_selection_for_test(near, 2, 0.80)
    relaxed = analysis.deterministic_selection_for_test(near, 2, 0.90)
    if len(strict) != 1 or len(relaxed) != 2 or relaxed[1]["diversity_max_jaccard"] > 0.90:
        raise AssertionError("One-time 0.80→0.90 diversity relaxation boundary failed")

    connection = __import__("sqlite3").connect(":memory:")
    connection.execute("CREATE TABLE patterns (pattern_id TEXT, items TEXT, length INTEGER, support INTEGER, "
                        "observed_at_minsup TEXT, source_run_ids TEXT, length_bucket TEXT, support_bucket TEXT, items_key TEXT)")
    for pattern_id, items in (("near-a", tuple(range(1, 11))), ("near-b", tuple(range(1, 10)) + (11,))):
        csv_items = ";".join(map(str, items))
        connection.execute("INSERT INTO patterns VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (pattern_id, csv_items, 10, 100, "0.05", "synthetic", "1", "low", csv_items))
    relaxed_selection, threshold, relaxation_used = analysis.select_with_relaxation(connection, 2)
    fresh_relaxed_pass = analysis.selection_pass(connection, 2, 0.90)
    connection.close()
    if (len(relaxed_selection) != 2 or threshold != 0.90 or not relaxation_used
            or [row["pattern_id"] for row in relaxed_selection] != [row["pattern_id"] for row in fresh_relaxed_pass]
            or relaxed_selection[1]["diversity_max_jaccard"] > 0.90):
        raise AssertionError("Relaxation did not reset and rerun selection at 0.90 exactly once")
    return ["same-support candidates share one tertile and lexical item ties are deterministic",
            "representative selection visits all nine length/support cells in fixed order",
            "Jaccard filter rejects >0.80 and accepts ≤0.90 only on the relaxed pass",
            "one-time relaxation resets selection, and the relaxed pass does not force a quota"]


def smoke_analysis(temp: pathlib.Path) -> list[str]:
    root = temp / "analysis-root"
    output = root / "results/fashion/fim/B0_K32_seed123_S0"
    output.mkdir(parents=True)
    config = {"repo_root": str(root), "output_dir": str(output), "configuration": "B0_K32_seed123_S0",
        "input_sha256": "c" * 64, "engine_revision": "synthetic-engine", "engine_source_sha256": "d" * 64,
        "budget_revision": "synthetic-b1", "output_limit_bytes": 1024}
    supervisor.atomic_toml(output / "config_snapshot.toml", config)
    canonical = {}
    for count in supervisor.MIN_COUNTS:
        pct = int(supervisor.FRACTIONS[count] * 100)
        run_id = f"analysis_{count}"
        canonical[f"{pct:02d}"] = run_id
    (output / "report").mkdir(parents=True, exist_ok=True)
    supervisor.atomic_toml(output / "report" / "experiment_manifest.toml", {"configuration": config["configuration"],
        "input_sha256": config["input_sha256"], "canonical_runs": canonical})

    synthetic = {
        56_000: ("COMPLETED_ZERO", []),
        42_000: ("COMPLETED_FULL", [([6], 43_263), ([26], 48_922)]),
        28_000: ("COMPLETED_FULL", [([6], 43_263), ([26], 48_922), ([6, 26], 32_266)]),
    }
    for count in supervisor.MIN_COUNTS:
        pct = int(supervisor.FRACTIONS[count] * 100)
        run_id = canonical[f"{pct:02d}"]
        sidecar_path = supervisor.sidecar_path(output, run_id)
        sidecar_path.parent.mkdir(parents=True, exist_ok=True)
        status = supervisor.new_sidecar(run_id, count, config, f"mining/runs/{run_id}/worker_stdout.log")
        if count in synthetic:
            run_status, entries = synthetic[count]
            artifact = output / "mining/itemsets" / f"synthetic_{pct:02d}.jsonl"
            artifact.parent.mkdir(parents=True, exist_ok=True)
            lines = []
            for items, support in entries:
                lines.append(json.dumps({"items": items, "length": len(items), "support_count": support,
                    "support_fraction": support / 70_000}, separators=(",", ":")) + "\n")
            artifact.write_text("".join(lines), encoding="utf-8")
            status.update({"status": run_status, "phase": "FINAL", "final_committed": True,
                "audit_status": "PASS", "output_path": supervisor.relative_to(root, artifact),
                "output_sha256": supervisor.sha256_file(artifact), "output_size_bytes": artifact.stat().st_size,
                "record_count": len(entries), "total_frequent_itemsets": len(entries),
                "max_itemset_length": max((len(items) for items, _ in entries), default=0),
                "runtime_seconds": 1.25, "peak_rss_mb": 128.0, "engine_revision": config["engine_revision"],
                "engine_source_sha256": config["engine_source_sha256"], "input_sha256": config["input_sha256"],
                "budget_revision": config["budget_revision"],
                "sampled_itemsets_independently_verified": 0, "audit_sample_seed": 42,
                "audit_sample_itemsets": [], "audit_sample_expected_supports": [],
                "audit_sample_observed_supports": [], "audit_sample_mismatch_count": 0,
                "cross_threshold_outputs_checked": len([higher for higher in (56_000, 42_000, 28_000)
                    if higher > count and higher in synthetic]),
                "cross_threshold_min_counts_checked": [higher for higher in (56_000, 42_000, 28_000)
                    if higher > count and higher in synthetic],
                "cross_threshold_run_ids_checked": [f"analysis_{higher}" for higher in (56_000, 42_000, 28_000)
                    if higher > count and higher in synthetic],
                "cross_threshold_mismatch_count": 0})
        else:
            status.update({"status": "TIMEOUT", "phase": "FINAL", "reason_code": "SMOKE_ONLY",
                "runtime_seconds": 30.0, "engine_revision": config["engine_revision"],
                "engine_source_sha256": config["engine_source_sha256"], "input_sha256": config["input_sha256"],
                "budget_revision": config["budget_revision"]})
        supervisor.atomic_toml(sidecar_path, status)

    result = analysis.analyze(output, 12)
    with open(output / "analysis/run_statistics.csv", newline="", encoding="utf-8") as stream:
        stats_rows = list(csv.DictReader(stream))
    with open(output / "analysis/master_patterns.csv", newline="", encoding="utf-8") as stream:
        catalog = list(csv.DictReader(stream))
    if len(stats_rows) != 6 or stats_rows[-1]["status"] != "TIMEOUT" or len(catalog) != 3:
        raise AssertionError("Synthetic analysis failed six-threshold/missing-status/catalog audit")
    if result["catalog"]["unique_pattern_count"] != 3 or result["representatives"]["target_selected"] != 3:
        raise AssertionError("Synthetic master catalog or representative selection count mismatch")
    if (result["representatives"]["actual_jaccard_threshold"] != 0.90
            or result["representatives"]["relaxation_used"] is not True
            or result["representatives"]["target_requested"] != 12):
        raise AssertionError("Short catalog did not receive exactly one relaxed retry without forced quota")
    required = ["analysis/count_by_length.csv", "analysis/pattern_support_summary.csv", "analysis/master_patterns.jsonl",
        "analysis/pattern_statistics.md", "figures/minsup_vs_itemset_count.png", "figures/minsup_vs_runtime.png",
        "figures/itemset_lengths_by_minsup.png"]
    if not all((output / path).is_file() for path in required):
        raise AssertionError("Required v1.3 analysis tables or PNG figures are missing")
    if list((output / "analysis").glob("fim-selection-*.sqlite")):
        raise AssertionError("Temporary selection SQLite database was not removed")
    return ["analysis distinguishes completed and timeout thresholds", "master catalog deduplicates across runs",
            "required tables and PNG figures build from canonical synthetic outputs", "temporary selection database is cleaned up",
            "insufficient catalog triggers one 0.90 retry and preserves the actual selected count"]


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("Usage: smoke.py REPO_ROOT JULIA_EXECUTABLE")
    root = pathlib.Path(sys.argv[1]).resolve()
    julia = str(pathlib.Path(sys.argv[2]).resolve())
    with tempfile.TemporaryDirectory(prefix="fashion-fim-p1-") as temp_dir:
        temp = pathlib.Path(temp_dir)
        evidence = smoke_worker(root, julia, temp)
        evidence += smoke_systemd_budgets()
        evidence += smoke_crash_windows(temp)
        evidence += smoke_worker_launch_intent(temp)
        evidence += smoke_status_precedence()
        evidence += smoke_missing_asset_policy(temp)
        evidence += smoke_selection()
        evidence += smoke_analysis(temp)
    for item in evidence:
        print(f"PASS {item}")
    print(json.dumps({"p1_smoke": "PASS", "checks": evidence}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
