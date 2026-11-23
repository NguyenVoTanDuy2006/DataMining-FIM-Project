#!/usr/bin/env python3
"""Durable, resource-bounded supervisor for the six official Fashion-FIM runs."""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
import math
import os
import pathlib
import platform
import random
import re
import shutil
import signal
import subprocess
import sys
import time
import tomllib

MIN_COUNTS = (56_000, 42_000, 28_000, 14_000, 7_000, 3_500)
FRACTIONS = {56_000: 0.80, 42_000: 0.60, 28_000: 0.40, 14_000: 0.20, 7_000: 0.10, 3_500: 0.05}
HISTORICAL_INPUT_SHA256 = "b078e485064bfdacea4b5faa5f027efe7123af32a2db2c27acf415d6b1dd7d70"
VALID_BACKENDS = ("set", "bitvector")
MINING_SCRIPTS = pathlib.Path("src", "applications", "Fashion-Mnist", "mining", "scripts")
RUN_STATUSES = {
    "NOT_RUN", "COMPLETED_FULL", "COMPLETED_ZERO", "TIMEOUT", "MEMORY_LIMIT",
    "OUTPUT_LIMIT", "ITEMSET_CAPPED", "LENGTH_CAPPED", "COMPLETION_UNVERIFIED",
    "INVALID_OUTPUT", "FAILED", "UNKNOWN_INTERRUPTED", "BLOCKED",
}
RUN_COLUMNS = (
    "run_id", "configuration", "backend", "minsup_fraction", "minsup_count", "status", "reason_code",
    "total_frequent_itemsets", "max_itemset_length", "observed_partial_itemsets", "runtime_seconds",
    "peak_rss_mb", "output_size_bytes", "engine_revision", "input_sha256", "used_optional_limits",
    "worker_log_path", "notes",
)


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")


def toml_scalar(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        if not math.isfinite(value):
            raise ValueError("TOML cannot store a non-finite float")
        return repr(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, (list, tuple)):
        return "[" + ", ".join(toml_scalar(item) for item in value) + "]"
    raise TypeError(f"Unsupported TOML value {type(value)!r}")


def toml_text(mapping: dict) -> str:
    root = {key: value for key, value in mapping.items() if not isinstance(value, dict)}
    tables = {key: value for key, value in mapping.items() if isinstance(value, dict)}
    lines = [f"{key} = {toml_scalar(value)}" for key, value in root.items()]
    for table, fields in tables.items():
        if lines:
            lines.append("")
        lines.append(f"[{table}]")
        lines.extend(f"{key} = {toml_scalar(value)}" for key, value in fields.items())
    return "\n".join(lines) + "\n"


def fsync_directory(path: pathlib.Path) -> None:
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def atomic_write(path: pathlib.Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + f".{os.getpid()}.tmp")
    with open(temporary, "w", encoding="utf-8", newline="") as stream:
        stream.write(content)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)
    fsync_directory(path.parent)


def atomic_toml(path: pathlib.Path, mapping: dict) -> None:
    atomic_write(path, toml_text(mapping))


def read_toml(path: pathlib.Path) -> dict:
    with open(path, "rb") as stream:
        return tomllib.load(stream)


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_backend(backend: str) -> str:
    if backend not in VALID_BACKENDS:
        raise ValueError(f"backend must be one of {', '.join(VALID_BACKENDS)}")
    return backend


def worker_backend_arguments(backend: str) -> list[str]:
    return ["--backend", validate_backend(backend)]


def input_preflight(path: pathlib.Path, expected_sha256: str | None = None, expected_n: int = 70_000) -> dict:
    digest = sha256_file(path)
    if expected_sha256 and digest != expected_sha256:
        raise ValueError("Input SHA256 changed since the notebook preflight")
    singleton = {item: 0 for item in range(1, 33)}
    tid_seen = set()
    image_seen = set()
    empty_count = 0
    rows = 0
    pair_6_26 = 0
    min_length = 10**9
    max_length = 0
    with open(path, encoding="utf-8") as stream:
        for line_number, line in enumerate(stream, 1):
            row = json.loads(line)
            if set(row) != {"tid", "image_id", "items"}:
                raise ValueError(f"Unexpected JSONL schema on line {line_number}")
            tid, image_id, items = row["tid"], row["image_id"], row["items"]
            if type(tid) is not int or not isinstance(items, list):
                raise ValueError(f"Invalid JSONL value types on line {line_number}")
            if isinstance(image_id, str):
                matched = re.fullmatch(r"(train):(0|[1-9][0-9]*)|(test):(0|[1-9][0-9]*)", image_id)
                if not matched:
                    raise ValueError(f"Invalid stable image_id on line {line_number}")
                split = matched.group(1) or matched.group(3)
                index = int(matched.group(2) or matched.group(4))
                if index >= (60_000 if split == "train" else 10_000):
                    raise ValueError(f"Stable image_id is out of range on line {line_number}")
            elif type(image_id) is not int or image_id <= 0:
                raise ValueError(f"Invalid image_id on line {line_number}")
            if any(type(item) is not int or item not in singleton for item in items):
                raise ValueError(f"Invalid visual-word ID on line {line_number}")
            if items != sorted(set(items)):
                raise ValueError(f"Items are not unique and ascending on line {line_number}")
            rows += 1
            empty_count += not items
            min_length = min(min_length, len(items))
            max_length = max(max_length, len(items))
            if tid in tid_seen or image_id in image_seen:
                raise ValueError(f"Duplicate tid/image_id on line {line_number}")
            tid_seen.add(tid)
            image_seen.add(image_id)
            for item in items:
                singleton[item] += 1
            pair_6_26 += 6 in items and 26 in items
    if rows != expected_n or len(tid_seen) != rows or len(image_seen) != rows:
        raise ValueError(f"Locked input sanity mismatch: rows={rows}, empty={empty_count}")
    legacy_guardrails = digest == HISTORICAL_INPUT_SHA256
    if legacy_guardrails and (empty_count != 0 or max(singleton.values()) != 48_922 or
            singleton[6] != 43_263 or singleton[26] != 48_922 or pair_6_26 != 32_266):
        raise ValueError("Historical input singleton/pair guardrails do not match the locked source checks")
    return {
        "input_sha256": digest,
        "record_count": rows,
        "empty_count": empty_count,
        "min_items_per_transaction": min_length,
        "max_items_per_transaction": max_length,
        "min_item_id": 1,
        "max_item_id": 32,
        "unique_tid_count": len(tid_seen),
        "unique_image_id_count": len(image_seen),
        "singleton_support": {str(item): count for item, count in singleton.items()},
        "max_singleton_support": max(singleton.values()),
        "support_6": singleton[6],
        "support_26": singleton[26],
        "support_6_26": pair_6_26,
        "legacy_guardrails_applies": legacy_guardrails,
        "legacy_guardrail_status": "PASS" if legacy_guardrails else "NOT_APPLICABLE",
    }


def relative_to(root: pathlib.Path, path: pathlib.Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return str(path.resolve())


def load_config(output_dir: pathlib.Path) -> dict:
    config = read_toml(output_dir / "config_snapshot.toml")
    config["repo_root"] = str(pathlib.Path(config["repo_root"]).resolve())
    config["output_dir"] = str(output_dir.resolve())
    return config


def sidecar_path(output_dir: pathlib.Path, run_id: str) -> pathlib.Path:
    return output_dir / "mining" / "runs" / run_id / "status.toml"


def canonical_manifest(output_dir: pathlib.Path) -> tuple[pathlib.Path, dict]:
    path = output_dir / "report" / "experiment_manifest.toml"
    return path, read_toml(path)


def run_id_for(min_count: int, input_hash: str, engine_hash: str, budget_revision: str,
               attempt: int = 1, backend: str = "set") -> str:
    percent = int(round(FRACTIONS[min_count] * 100))
    return f"{backend}_minsup_{percent:02d}_{input_hash[:8]}_{engine_hash[:8]}_{budget_revision}_a{attempt:02d}"


def new_sidecar(run_id: str, min_count: int, config: dict, log_path: str) -> dict:
    return {
        "schema_version": 1,
        "run_id": run_id,
        "configuration": config["configuration"],
        "backend": config.get("backend", "set"),
        "minsup_fraction": FRACTIONS[min_count],
        "minsup_count": min_count,
        "status": "NOT_RUN",
        "phase": "NOT_RUN",
        "reason_code": "",
        "total_frequent_itemsets": "NA",
        "max_itemset_length": "NA",
        "observed_partial_itemsets": 0,
        "runtime_seconds": "NA",
        "peak_rss_mb": "NA",
        "output_size_bytes": "NA",
        "record_count": "NA",
        "engine_revision": config["engine_revision"],
        "engine_source_sha256": config["engine_source_sha256"],
        "input_sha256": config["input_sha256"],
        "budget_revision": config["budget_revision"],
        "used_optional_limits": False,
        "worker_log_path": log_path,
        "worker_stderr_log_path": log_path.replace("worker_stdout.log", "worker_stderr.log"),
        "notes": "",
        "final_committed": False,
        "audit_status": "NOT_RUN",
        "output_path": "",
        "output_sha256": "",
        "started_at": "",
        "last_heartbeat": "",
        "deadline_at": "",
        "end_at": "",
        "pid": 0,
        "exit_code": -1,
        "exit_signal": "",
        "systemd_result": "",
        "systemd_memory_peak_bytes": 0,
        "worker_unit": "",
    }


def initialize(args) -> None:
    validate_backend(args.backend)
    root = pathlib.Path(args.repo_root).resolve()
    output_dir = pathlib.Path(args.output_dir).resolve()
    input_path = pathlib.Path(args.input_path).resolve()
    source_paths = (root / "src" / "algorithm" / "EclatBaseline.jl",
                    root / "src" / "algorithm" / "EclatOptimized.jl")
    worker_path = root / MINING_SCRIPTS / "run_mining_worker.jl"
    if not input_path.is_file() or not all(path.is_file() for path in source_paths) or not worker_path.is_file():
        raise FileNotFoundError("Locked input, worker, or Eclat source file is missing")
    engine_revision = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    source_digest = hashlib.sha256()
    for source_path in source_paths:
        source_digest.update(source_path.name.encode("utf-8") + b"\0")
        source_digest.update(source_path.read_bytes())
    engine_source_sha256 = source_digest.hexdigest()
    worker_source_sha256 = sha256_file(worker_path)
    preflight = input_preflight(input_path)
    disk = shutil.disk_usage(output_dir.parent if output_dir.parent.exists() else root)
    runtime_env = read_toml(pathlib.Path(args.runtime_env))
    expected_config = {
        "schema_version": 1,
        "configuration": "B0_K32_seed123_S0",
        "backend": args.backend,
        "dataset": "Fashion-MNIST",
        "construction": "T2",
        "codebook_backend": "raw_full_batch_kmeans",
        "K": 32,
        "seed": 123,
        "encoding": "S0_Binary_BoVW",
        "repo_root": str(root),
        "input_source_path": relative_to(root, input_path),
        "input_sha256": preflight["input_sha256"],
        "transaction_count": preflight["record_count"],
        "empty_count": preflight["empty_count"],
        "legacy_guardrails_applies": preflight["legacy_guardrails_applies"],
        "legacy_guardrail_status": preflight["legacy_guardrail_status"],
        "engine_api": "EclatFIM.mine(transactions, min_count; backend)",
        "engine_revision": engine_revision,
        "engine_source_sha256": engine_source_sha256,
        "worker_source_sha256": worker_source_sha256,
        "julia_executable": str(pathlib.Path(runtime_env["julia_executable"]).resolve()),
        "julia_version": runtime_env["julia_version"],
        "julia_threads": int(runtime_env["julia_threads"]),
        "julia_depot_path": runtime_env["julia_depot_path"],
        "julia_load_path": runtime_env.get("julia_load_path", "@:@v#.#:@stdlib"),
        "home_path": runtime_env["home_path"],
        "process_path": runtime_env["process_path"],
        "julia_package_versions": runtime_env.get("julia_package_versions", []),
        "julia_manifest_sha256": sha256_file(root / "Manifest.toml"),
        "cpu_model": runtime_env.get("cpu_model", "NA"),
        "os_platform": sys.platform,
        "python_version": platform.python_version(),
        "cpu_count": os.cpu_count() or 1,
        "memory_available_bytes_at_init": int(runtime_env.get("memory_available_bytes", 0)),
        "disk_free_bytes_at_init": disk.free,
        "minsup_counts": list(MIN_COUNTS),
        "minsup_fractions": [FRACTIONS[count] for count in MIN_COUNTS],
        "wall_time_seconds_per_run": args.wall_time_seconds_per_run,
        "memory_limit_mb_per_worker": args.memory_limit_mb_per_worker,
        "output_limit_bytes": args.output_limit_bytes,
        "budget_revision": args.budget_revision,
        "enforcement_method": "systemd user transient worker service: RuntimeMaxSec + MemoryMax + MemorySwapMax=0; serializer checks each JSONL line before write",
        "worker_memory_scope": "single Julia worker service cgroup (worker only; supervisor and notebook excluded)",
        "output_limit_scope": "one minsup JSONL staging/exact artifact; logs, TOML sidecars, CSV and figures excluded",
        "sampling_seed": 42,
        "representative_patterns_target": 16,
        "output_base_dir": relative_to(root, output_dir),
    }

    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "report").mkdir(parents=True, exist_ok=True)
    existing = output_dir / "config_snapshot.toml"
    if existing.exists():
        old = read_toml(existing)
        identity = ("input_sha256", "engine_revision", "engine_source_sha256", "budget_revision",
                    "wall_time_seconds_per_run", "memory_limit_mb_per_worker", "output_limit_bytes")
        if any(old.get(key) != expected_config.get(key) for key in identity) or (
                "backend" in old and old["backend"] != args.backend):
            raise RuntimeError("Existing run identity differs; use a new budget revision/attempt namespace")
    else:
        atomic_toml(existing, expected_config)

    guard_path = output_dir / "input_manifest.toml"
    if not guard_path.exists():
        preflight.update({"source_path": expected_config["input_source_path"],
                          "configuration": expected_config["configuration"],
                          "read_only": True, "verified_at": utc_now()})
        atomic_toml(guard_path, preflight)

    manifest_path = output_dir / "report" / "experiment_manifest.toml"
    if manifest_path.exists():
        manifest = read_toml(manifest_path)
        if manifest.get("input_sha256") != preflight["input_sha256"]:
            raise RuntimeError("Existing experiment manifest belongs to a different input")
        canonical = manifest.get("canonical_runs", {})
    else:
        canonical = {}
        manifest = {
            "schema_version": 1,
            "configuration": expected_config["configuration"],
            "backend": args.backend,
            "input_sha256": preflight["input_sha256"],
            "engine_revision": engine_revision,
            "engine_source_sha256": engine_source_sha256,
            "budget_revision": args.budget_revision,
            "created_at": utc_now(),
            "output_base_dir": expected_config["output_base_dir"],
        }

    runs_root = output_dir / "mining" / "runs"
    itemsets_dir = output_dir / "mining" / "itemsets"
    (output_dir / "mining" / "partial").mkdir(parents=True, exist_ok=True)
    (output_dir / "mining" / "uncommitted").mkdir(parents=True, exist_ok=True)
    itemsets_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "report").mkdir(parents=True, exist_ok=True)
    for min_count in MIN_COUNTS:
        pct = int(FRACTIONS[min_count] * 100)
        threshold_key = f"{pct:02d}"
        current = canonical.get(threshold_key)
        run_id = current or run_id_for(min_count, preflight["input_sha256"], engine_source_sha256,
            args.budget_revision, backend=args.backend)
        path = sidecar_path(output_dir, run_id)
        if not path.exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            rel_log = relative_to(root, path.parent / "worker_stdout.log")
            atomic_toml(path, new_sidecar(run_id, min_count, expected_config, rel_log))
        canonical[threshold_key] = run_id
    manifest["canonical_runs"] = canonical
    atomic_toml(manifest_path, manifest)
    rebuild_runs_csv(output_dir)
    print(json.dumps({"initialized": True, "output_dir": str(output_dir), "input_sha256": preflight["input_sha256"],
                      "guardrails": {"max_singleton": preflight["max_singleton_support"],
                                     "support_6": preflight["support_6"], "support_26": preflight["support_26"],
                                     "support_6_26": preflight["support_6_26"]},
                      "statuses": six_statuses(output_dir)}, ensure_ascii=False, indent=2))


def row_from_status(status: dict, min_count: int) -> dict:
    return {
        "run_id": status.get("run_id", ""),
        "configuration": status.get("configuration", "B0_K32_seed123_S0"),
        "backend": status.get("backend", "set"),
        "minsup_fraction": status.get("minsup_fraction", FRACTIONS[min_count]),
        "minsup_count": min_count,
        "status": status.get("status", "NOT_RUN"),
        "reason_code": status.get("reason_code", ""),
        "total_frequent_itemsets": status.get("total_frequent_itemsets", "NA"),
        "max_itemset_length": status.get("max_itemset_length", "NA"),
        "observed_partial_itemsets": status.get("observed_partial_itemsets", 0),
        "runtime_seconds": status.get("runtime_seconds", "NA"),
        "peak_rss_mb": status.get("peak_rss_mb", "NA"),
        "output_size_bytes": status.get("output_size_bytes", "NA"),
        "engine_revision": status.get("engine_revision", ""),
        "input_sha256": status.get("input_sha256", ""),
        "used_optional_limits": status.get("used_optional_limits", False),
        "worker_log_path": status.get("worker_log_path", ""),
        "notes": status.get("notes", ""),
    }


def rebuild_runs_csv(output_dir: pathlib.Path) -> None:
    manifest_path, manifest = canonical_manifest(output_dir)
    canonical = manifest.get("canonical_runs", {})
    path = output_dir / "mining" / "runs.csv"
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + f".{os.getpid()}.tmp")
    with open(temporary, "w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=RUN_COLUMNS, lineterminator="\n")
        writer.writeheader()
        for min_count in MIN_COUNTS:
            pct = int(FRACTIONS[min_count] * 100)
            run_id = canonical.get(f"{pct:02d}", "")
            sidecar = sidecar_path(output_dir, run_id) if run_id else None
            status = read_toml(sidecar) if sidecar and sidecar.is_file() else {}
            if status and status.get("status") not in RUN_STATUSES:
                raise ValueError(f"Unknown run status for {run_id}: {status.get('status')}")
            writer.writerow(row_from_status(status, min_count))
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)
    fsync_directory(path.parent)


def read_itemsets(path: pathlib.Path, min_count: int):
    previous = None
    with open(path, encoding="utf-8") as stream:
        for line_number, line in enumerate(stream, 1):
            if not line.endswith("\n"):
                raise ValueError(f"Unterminated JSONL record at line {line_number}")
            row = json.loads(line)
            if set(row) != {"items", "length", "support_count", "support_fraction"}:
                raise ValueError(f"Unexpected itemset schema at line {line_number}")
            items = row["items"]
            if not isinstance(items, list) or any(type(item) is not int or item not in range(1, 33) for item in items):
                raise ValueError(f"Invalid items at line {line_number}")
            if not items or items != sorted(set(items)) or row["length"] != len(items):
                raise ValueError(f"Non-canonical items/length at line {line_number}")
            support = row["support_count"]
            if type(support) is not int or not (min_count <= support <= 70_000):
                raise ValueError(f"Invalid support at line {line_number}")
            fraction = row["support_fraction"]
            if not isinstance(fraction, (int, float)) or not math.isclose(fraction, support / 70_000, rel_tol=0, abs_tol=1e-15):
                raise ValueError(f"Invalid support fraction at line {line_number}")
            key = (len(items), tuple(items))
            if previous is not None and key <= previous:
                raise ValueError(f"Duplicate or unsorted itemset at line {line_number}")
            previous = key
            yield key, support


def validate_itemsets(path: pathlib.Path, min_count: int) -> dict:
    count = 0
    max_length = 0
    for key, _support in read_itemsets(path, min_count):
        count += 1
        max_length = max(max_length, key[0])
    return {"record_count": count, "max_itemset_length": max_length,
            "output_size_bytes": path.stat().st_size, "output_sha256": sha256_file(path)}


def check_cross_threshold(higher_path: pathlib.Path, higher_count: int, lower_path: pathlib.Path, lower_count: int) -> None:
    higher = iter(read_itemsets(higher_path, higher_count))
    lower = iter(read_itemsets(lower_path, lower_count))
    low = next(lower, None)
    for high_key, high_support in higher:
        while low is not None and low[0] < high_key:
            low = next(lower, None)
        if low is None or low[0] != high_key:
            raise ValueError(f"Cross-minsup containment failure: {high_key[1]} missing at {lower_count}")
        if high_support != low[1]:
            raise ValueError(f"Cross-minsup support mismatch for {high_key[1]}")


def independent_support_sample(path: pathlib.Path, itemsets: list[tuple[int, ...]], expected: dict) -> dict:
    if not itemsets:
        return {}
    found = {items: 0 for items in itemsets}
    with open(path, encoding="utf-8") as stream:
        for line in stream:
            transaction = set(json.loads(line)["items"])
            for items in itemsets:
                if set(items).issubset(transaction):
                    found[items] += 1
    for items in itemsets:
        if found[items] != expected[items]:
            raise ValueError(f"Independent support mismatch for {items}: {found[items]} != {expected[items]}")
    return found


def audit_guardrails(path: pathlib.Path, min_count: int, config: dict, record_count: int) -> None:
    if not config.get("legacy_guardrails_applies", False):
        return
    if min_count == 56_000:
        if record_count != 0 or path.stat().st_size != 0:
            raise ValueError("80% guardrail failed: expected exact completed-zero output")
    if min_count == 42_000:
        observed = {tuple(key[1]): support for key, support in read_itemsets(path, min_count)}
        wanted = {(6,): config["source_guardrails"]["support_6"],
                  (26,): config["source_guardrails"]["support_26"]}
        if observed != wanted or config["source_guardrails"]["support_6_26"] >= min_count:
            raise ValueError(f"60% guardrail failed: expected exactly {wanted}, observed {observed}")


def systemctl_show(unit: str) -> dict:
    properties = ("ActiveState", "SubState", "Result", "MainPID", "ExecMainCode", "ExecMainStatus",
                  "ExecMainStartTimestampMonotonic", "ExecMainExitTimestampMonotonic", "MemoryPeak",
                  "MemoryCurrent", "MemoryMax", "MemorySwapMax", "ControlGroup")
    result = subprocess.run(["systemctl", "--user", "show", unit, "--no-pager", *[f"--property={key}" for key in properties]],
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode != 0:
        return {}
    return dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)


def worker_unit(run_id: str) -> str:
    suffix = hashlib.sha256(run_id.encode()).hexdigest()[:10]
    return f"fim-worker-{suffix}.service"


def process_vm_hwm_mb(pid: int) -> float | None:
    try:
        with open(f"/proc/{pid}/status", encoding="ascii") as stream:
            for line in stream:
                if line.startswith("VmHWM:"):
                    return int(line.split()[1]) / 1024
    except (OSError, ValueError):
        return None
    return None


def fsync_file(path: pathlib.Path) -> None:
    with open(path, "rb") as stream:
        os.fsync(stream.fileno())


def count_complete_jsonl_records(path: pathlib.Path) -> int:
    if not path.is_file():
        return 0
    count = 0
    with open(path, "rb") as stream:
        for line in stream:
            if line.endswith(b"\n"):
                count += 1
    return count


def active_unit(unit: str) -> bool:
    props = systemctl_show(unit)
    return props.get("ActiveState") in {"activating", "active", "reloading"}


def update_status(path: pathlib.Path, record: dict, **changes) -> dict:
    record.update(changes)
    atomic_toml(path, record)
    return record


def active_higher_outputs(output_dir: pathlib.Path, manifest: dict, current_min_count: int,
                          repo_root: pathlib.Path | None = None) -> list[tuple[int, pathlib.Path, str]]:
    paths = []
    root = pathlib.Path(repo_root or load_config(output_dir)["repo_root"])
    canonical = manifest.get("canonical_runs", {})
    for count in MIN_COUNTS:
        if count <= current_min_count:
            continue
        pct = int(FRACTIONS[count] * 100)
        run_id = canonical.get(f"{pct:02d}")
        if not run_id:
            continue
        path = sidecar_path(output_dir, run_id)
        if not path.is_file():
            continue
        record = read_toml(path)
        if record.get("status") not in {"COMPLETED_FULL", "COMPLETED_ZERO"} or not record.get("final_committed"):
            continue
        # Sidecar output_path values are repository-relative, like manifest paths.
        # Joining them to output_dir duplicated `results/fashion/fim/<config>` and
        # silently skipped every prior completed output during the original P2 runs.
        exact_path = root / record["output_path"]
        if exact_path.is_file() and sha256_file(exact_path) == record.get("output_sha256"):
            paths.append((count, exact_path, run_id))
    return paths


def validate_staging(output_dir: pathlib.Path, config: dict, min_count: int, staging: pathlib.Path,
                     worker_result: dict, manifest: dict) -> dict:
    if worker_result.get("worker_status") not in {"COMPLETED_ZERO", "COMPLETED_FULL"}:
        raise ValueError("Worker did not report a full result")
    if worker_result.get("input_sha256") != config["input_sha256"]:
        raise ValueError("Worker input SHA256 differs from run identity")
    if worker_result.get("backend", "set") != config.get("backend", "set"):
        raise ValueError("Worker backend differs from run identity")
    if worker_result.get("min_count") != min_count:
        raise ValueError("Worker min_count differs from run identity")
    info = validate_itemsets(staging, min_count)
    if info["record_count"] != worker_result.get("record_count"):
        raise ValueError("Staging line count differs from worker Dict count")
    if info["output_size_bytes"] != worker_result.get("output_size_bytes"):
        raise ValueError("Staging byte count differs from worker output metric")
    if worker_result.get("max_itemset_length") != info["max_itemset_length"]:
        raise ValueError("Staging max itemset length differs from worker metric")
    if not info["record_count"] and worker_result.get("worker_status") != "COMPLETED_ZERO":
        raise ValueError("Empty Dict must be explicitly COMPLETED_ZERO")
    if info["record_count"] and worker_result.get("worker_status") != "COMPLETED_FULL":
        raise ValueError("Non-empty Dict must be COMPLETED_FULL")
    audit_guardrails(staging, min_count, config, info["record_count"])
    chooser = random.Random(42)
    sample = []
    for index, (key, _support) in enumerate(read_itemsets(staging, min_count)):
        items = key[1]
        if index < 20:
            sample.append(items)
        else:
            replacement = chooser.randrange(index + 1)
            if replacement < 20:
                sample[replacement] = items
    sample_set = set(sample)
    support_map = {key[1]: support for key, support in read_itemsets(staging, min_count) if key[1] in sample_set}
    observed_supports = independent_support_sample(
        pathlib.Path(config["repo_root"]) / config["input_source_path"], sample, support_map)
    higher_paths = active_higher_outputs(output_dir, manifest, min_count)
    for higher_count, higher_path, _higher_run_id in higher_paths:
        check_cross_threshold(higher_path, higher_count, staging, min_count)
    info["audit_status"] = "PASS"
    info["sampled_itemsets_independently_verified"] = len(sample)
    info["cross_threshold_outputs_checked"] = len(higher_paths)
    info["audit_sample_seed"] = 42
    info["audit_sample_itemsets"] = [list(items) for items in sample]
    info["audit_sample_expected_supports"] = [support_map[items] for items in sample]
    info["audit_sample_observed_supports"] = [observed_supports[items] for items in sample]
    info["audit_sample_mismatch_count"] = 0
    info["cross_threshold_min_counts_checked"] = [count for count, _path, _run_id in higher_paths]
    info["cross_threshold_run_ids_checked"] = [run_id for _count, _path, run_id in higher_paths]
    info["cross_threshold_mismatch_count"] = 0
    return info


def choose_exact_output(output_dir: pathlib.Path, run_id: str, min_count: int) -> pathlib.Path:
    percent = int(FRACTIONS[min_count] * 100)
    canonical_path = output_dir / "mining" / "itemsets" / f"minsup_{percent:02d}.jsonl"
    if not canonical_path.exists():
        return canonical_path
    attempt_path = output_dir / "mining" / "itemsets" / "attempts" / run_id / f"minsup_{percent:02d}.jsonl"
    attempt_path.parent.mkdir(parents=True, exist_ok=True)
    return attempt_path


def append_supervisor_log(output_dir: pathlib.Path, event: dict) -> None:
    log_path = output_dir / "report" / "supervisor_events.jsonl"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with open(log_path, "a", encoding="utf-8") as stream:
        stream.write(json.dumps({"time": utc_now(), **event}, ensure_ascii=False, sort_keys=True) + "\n")
        stream.flush()
        os.fsync(stream.fileno())


def quarantine_orphan(path: pathlib.Path, output_dir: pathlib.Path, run_id: str) -> pathlib.Path:
    destination = output_dir / "mining" / "uncommitted" / f"{run_id}_{time.time_ns()}_{path.name}.orphan"
    destination.parent.mkdir(parents=True, exist_ok=True)
    os.replace(path, destination)
    fsync_directory(destination.parent)
    append_supervisor_log(output_dir, {"event": "QUARANTINED_ORPHAN", "source": str(path), "destination": str(destination)})
    return destination


def launch_worker(root: pathlib.Path, output_dir: pathlib.Path, config: dict, run_id: str,
                  min_count: int, sidecar: dict, sidecar_file: pathlib.Path) -> dict:
    unit = worker_unit(run_id)
    worker_dir = sidecar_file.parent
    staging = worker_dir / "patterns.jsonl.staging"
    result_path = worker_dir / "worker_result.toml"
    log_path = worker_dir / "worker_stdout.log"
    stderr_log_path = worker_dir / "worker_stderr.log"
    source = root / config["input_source_path"]
    for stale in (staging, result_path):
        if stale.exists():
            stale.rename(stale.with_name(stale.name + f".{time.time_ns()}.stale"))
    exact = choose_exact_output(output_dir, run_id, min_count)
    if exact.exists():
        prior_final = False
        manifest = canonical_manifest(output_dir)[1]
        for prior_dir in (output_dir / "mining" / "runs").glob("*/status.toml"):
            try:
                prior = read_toml(prior_dir)
            except Exception:
                continue
            if prior.get("output_path") == relative_to(root, exact) and prior.get("final_committed"):
                prior_final = sha256_file(exact) == prior.get("output_sha256")
                if prior_final:
                    break
        if prior_final:
            exact = choose_exact_output(output_dir, run_id, min_count)
        else:
            quarantine_orphan(exact, output_dir, run_id)
    source_hash_before = sha256_file(source)
    if source_hash_before != config["input_sha256"]:
        raise RuntimeError("Read-only mining input changed before worker start")

    julia = config["julia_executable"]
    worker_script = root / MINING_SCRIPTS / "run_mining_worker.jl"
    memory_mb = int(config["memory_limit_mb_per_worker"])
    wall_seconds = int(config["wall_time_seconds_per_run"])
    launched = time.monotonic()
    state = update_status(sidecar_file, sidecar,
        phase="LAUNCHING", status="NOT_RUN", worker_unit=unit, started_at=utc_now(),
        last_heartbeat=utc_now(), deadline_at=(dt.datetime.now(dt.timezone.utc) + dt.timedelta(seconds=wall_seconds)).isoformat(timespec="seconds"),
        reason_code="", final_committed=False, audit_status="PENDING", output_path="", output_sha256="",
        notes="Launch intent persisted before systemd worker spawn")
    rebuild_runs_csv(output_dir)
    command = [
        "systemd-run", "--user", "--no-block", f"--unit={unit.removesuffix('.service')}",
        f"--working-directory={root}",
        f"--property=MemoryMax={memory_mb}M", "--property=MemorySwapMax=0", "--property=MemoryAccounting=yes",
        f"--property=RuntimeMaxSec={wall_seconds}s", "--property=TimeoutStopSec=1s",
        "--property=KillMode=control-group", "--property=OOMPolicy=kill",
        f"--property=StandardOutput=append:{log_path}", f"--property=StandardError=append:{stderr_log_path}",
        f"--setenv=PATH={config['process_path']}", f"--setenv=HOME={config['home_path']}",
        f"--setenv=JULIA_DEPOT_PATH={config['julia_depot_path']}",
        f"--setenv=JULIA_LOAD_PATH={config['julia_load_path']}", "--setenv=JULIA_NUM_THREADS=1",
        "--", julia, f"--project={root}", "--startup-file=no", "--history-file=no", "-t", "1",
        str(worker_script), str(source), str(staging), str(result_path), str(min_count),
        str(config["output_limit_bytes"]), *worker_backend_arguments(config.get("backend", "set")),
    ]
    proc = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"systemd worker launch failed: {proc.stderr.strip() or proc.stdout.strip()}")
    state = update_status(sidecar_file, state, phase="RUNNING",
        notes=f"Worker launched under systemd MemoryMax={memory_mb}M and RuntimeMaxSec={wall_seconds}s")
    append_supervisor_log(output_dir, {"event": "WORKER_SPAWNED", "run_id": run_id, "minsup_count": min_count,
                                       "worker_unit": unit, "launch_ack": proc.stdout.strip(), "launched_monotonic": launched})
    rebuild_runs_csv(output_dir)
    return monitor_worker(root, output_dir, config, run_id, min_count, state, sidecar_file,
                          staging, result_path, log_path, exact, launched)


def attach_worker(root: pathlib.Path, output_dir: pathlib.Path, config: dict, run_id: str,
                  min_count: int, sidecar: dict, sidecar_file: pathlib.Path) -> dict:
    worker_dir = sidecar_file.parent
    return monitor_worker(root, output_dir, config, run_id, min_count, sidecar, sidecar_file,
                          worker_dir / "patterns.jsonl.staging", worker_dir / "worker_result.toml",
                          worker_dir / "worker_stdout.log", pathlib.Path(sidecar.get("candidate_output_path", "")), time.monotonic())


def monitor_worker(root: pathlib.Path, output_dir: pathlib.Path, config: dict, run_id: str,
                   min_count: int, status: dict, status_file: pathlib.Path, staging: pathlib.Path,
                   result_path: pathlib.Path, log_path: pathlib.Path, exact: pathlib.Path,
                   launched_monotonic: float) -> dict:
    unit = status.get("worker_unit") or worker_unit(run_id)
    peak_rss = 0.0
    last_heartbeat = 0.0
    start_time = time.monotonic()
    last_props = {}
    while True:
        props = systemctl_show(unit)
        if not props:
            status = update_status(status_file, status, phase="FINAL", status="UNKNOWN_INTERRUPTED",
                reason_code="WORKER_UNIT_MISSING", final_committed=False, audit_status="NA", end_at=utc_now(),
                runtime_seconds="NA", peak_rss_mb="NA", total_frequent_itemsets="NA", max_itemset_length="NA",
                output_size_bytes="NA", record_count="NA", notes="Worker unit disappeared without a terminal sidecar")
            rebuild_runs_csv(output_dir)
            return status
        last_props = props
        state = props.get("ActiveState", "")
        pid = int(props.get("MainPID") or 0)
        observed = process_vm_hwm_mb(pid) if pid > 0 else None
        if observed is not None:
            peak_rss = max(peak_rss, observed)
        now = time.monotonic()
        if now - last_heartbeat >= 5 or not status.get("pid"):
            status = update_status(status_file, status, pid=pid, last_heartbeat=utc_now(),
                                   sampled_peak_rss_mb=peak_rss if peak_rss else "NA")
            last_heartbeat = now
            rebuild_runs_csv(output_dir)
        if state in {"inactive", "failed"}:
            break
        if state not in {"activating", "active", "reloading"} and now - start_time > 60:
            break
        time.sleep(1)

    result = read_toml(result_path) if result_path.is_file() else {}
    unit_result = last_props.get("Result", "")
    exit_code = int(last_props.get("ExecMainStatus") or -1)
    exit_kind = last_props.get("ExecMainCode", "")
    start_us = int(last_props.get("ExecMainStartTimestampMonotonic") or 0)
    exit_us = int(last_props.get("ExecMainExitTimestampMonotonic") or 0)
    runtime = (exit_us - start_us) / 1_000_000 if start_us and exit_us >= start_us else max(0.0, time.monotonic() - launched_monotonic)
    group_peak = int(last_props.get("MemoryPeak") or 0) if (last_props.get("MemoryPeak") or "").isdigit() else 0
    signal_name = ""
    if exit_kind == "killed" and exit_code >= 0:
        try:
            signal_name = signal.Signals(exit_code).name
        except ValueError:
            signal_name = f"SIG{exit_code}"

    common = {"phase": "FINAL", "end_at": utc_now(), "runtime_seconds": runtime,
              "pid": int(status.get("pid") or 0), "exit_code": exit_code,
              "exit_signal": signal_name, "systemd_result": unit_result,
              "systemd_memory_peak_bytes": group_peak,
              "sampled_peak_rss_mb": peak_rss if peak_rss else "NA"}
    if unit_result in {"timeout", "timed-out"}:
        status = update_status(status_file, status, **common, status="TIMEOUT", reason_code="SYSTEMD_RUNTIME_MAX",
            total_frequent_itemsets="NA", max_itemset_length="NA", observed_partial_itemsets=count_complete_jsonl_records(staging),
            peak_rss_mb=peak_rss if peak_rss else "NA", output_size_bytes="NA", record_count="NA", audit_status="NA",
            final_committed=False, notes="RuntimeMaxSec watchdog stopped the worker; staging is not an exact output")
        if staging.exists():
            partial = output_dir / "mining" / "partial" / f"{run_id}_timeout.partial.jsonl"
            os.replace(staging, partial)
            status = update_status(status_file, status, partial_output_path=relative_to(root, partial))
    elif unit_result in {"oom-kill", "oom"}:
        status = update_status(status_file, status, **common, status="MEMORY_LIMIT", reason_code="SYSTEMD_CGROUP_OOM_KILL",
            total_frequent_itemsets="NA", max_itemset_length="NA", observed_partial_itemsets=count_complete_jsonl_records(staging),
            peak_rss_mb=peak_rss if peak_rss else "NA", output_size_bytes="NA", record_count="NA", audit_status="NA",
            final_committed=False, notes="Worker cgroup reported an OOM kill at its enforced MemoryMax")
        if staging.exists():
            partial = output_dir / "mining" / "partial" / f"{run_id}_memory.partial.jsonl"
            os.replace(staging, partial)
            status = update_status(status_file, status, partial_output_path=relative_to(root, partial))
    elif exit_code == 73 or result.get("worker_status") == "OUTPUT_LIMIT":
        if staging.exists():
            partial = output_dir / "mining" / "partial" / f"{run_id}_output_limit.partial.jsonl"
            os.replace(staging, partial)
            partial_path = relative_to(root, partial)
        else:
            partial_path = ""
        status = update_status(status_file, status, **common, status="OUTPUT_LIMIT", reason_code="JSONL_BYTE_CAP",
            total_frequent_itemsets="NA", max_itemset_length="NA",
            observed_partial_itemsets=int(result.get("observed_partial_itemsets", result.get("record_count", 0))),
            peak_rss_mb=result.get("peak_rss_mb", "NA"), output_size_bytes="NA", record_count="NA",
            audit_status="NA", final_committed=False, partial_output_path=partial_path,
            notes=f"Serializer stopped before a line would exceed output_limit_bytes={config['output_limit_bytes']}")
    elif result.get("error_type") == "OverflowError" and "max_itemsets exceeded" in result.get("error_message", ""):
        status = update_status(status_file, status, **common, phase="FINAL", status="ITEMSET_CAPPED",
            reason_code="CORE_MAX_ITEMSETS_EXCEPTION", total_frequent_itemsets="NA", max_itemset_length="NA",
            observed_partial_itemsets=int(result.get("record_count", 0)), peak_rss_mb=result.get("peak_rss_mb", "NA"),
            output_size_bytes="NA", record_count="NA", audit_status="NA", final_committed=False,
            notes="Core max_itemsets exception observed in a bounded smoke/recovery path")
    elif unit_result == "success" and exit_code == 0 and result.get("worker_status") in {"COMPLETED_ZERO", "COMPLETED_FULL"}:
        try:
            if not staging.is_file():
                raise ValueError("Worker returned successfully without staging JSONL")
            fsync_file(staging)
            manifest = canonical_manifest(output_dir)[1]
            audited = validate_staging(output_dir, config, min_count, staging, result, manifest)
            if exact.exists():
                quarantine_orphan(exact, output_dir, run_id)
            exact.parent.mkdir(parents=True, exist_ok=True)
            atomic_toml(status_file, {**status, **common, "phase": "COMMITTING", "status": "NOT_RUN",
                "audit_status": "PASS", "candidate_output_path": relative_to(root, exact),
                "sampled_itemsets_independently_verified": audited["sampled_itemsets_independently_verified"],
                "cross_threshold_outputs_checked": audited["cross_threshold_outputs_checked"]})
            os.replace(staging, exact)
            fsync_directory(exact.parent)
            exact_info = validate_itemsets(exact, min_count)
            if exact_info["output_sha256"] != audited["output_sha256"]:
                raise ValueError("Exact artifact checksum differs after atomic rename")
            final_status = "COMPLETED_ZERO" if exact_info["record_count"] == 0 else "COMPLETED_FULL"
            status = {**status, **common,
                "phase": "FINAL", "status": final_status, "reason_code": "",
                "total_frequent_itemsets": exact_info["record_count"],
                "max_itemset_length": exact_info["max_itemset_length"],
                "observed_partial_itemsets": 0,
                "runtime_seconds": runtime,
                "peak_rss_mb": result.get("peak_rss_mb", "NA"),
                "output_size_bytes": exact_info["output_size_bytes"],
                "record_count": exact_info["record_count"],
                "output_path": relative_to(root, exact),
                "output_sha256": exact_info["output_sha256"],
                "audit_status": "PASS", "final_committed": True,
                "sampled_itemsets_independently_verified": audited["sampled_itemsets_independently_verified"],
                "cross_threshold_outputs_checked": audited["cross_threshold_outputs_checked"],
                "notes": "Exact JSONL audited, atomically renamed and read back before final sidecar commit"}
            atomic_toml(status_file, status)
        except Exception as error:
            invalid = output_dir / "mining" / "partial" / f"{run_id}_invalid.staging.jsonl"
            if staging.exists():
                os.replace(staging, invalid)
            status = update_status(status_file, status, **common, phase="FINAL", status="INVALID_OUTPUT",
                reason_code="APPLICATION_AUDIT_FAILED", total_frequent_itemsets="NA", max_itemset_length="NA",
                observed_partial_itemsets=int(result.get("record_count", 0)), peak_rss_mb=result.get("peak_rss_mb", "NA"),
                output_size_bytes="NA", record_count="NA", audit_status="FAIL", final_committed=False,
                partial_output_path=relative_to(root, invalid) if invalid.exists() else "",
                notes=f"{type(error).__name__}: {error}")
    else:
        status = update_status(status_file, status, **common, phase="FINAL", status="FAILED",
            reason_code="WORKER_EXIT_NONZERO", total_frequent_itemsets="NA", max_itemset_length="NA",
            observed_partial_itemsets=int(result.get("record_count", 0)),
            peak_rss_mb=result.get("peak_rss_mb", "NA"), output_size_bytes="NA", record_count="NA",
            audit_status="NA", final_committed=False,
            notes=f"systemd Result={unit_result}, exit={exit_code}/{signal_name}; {result.get('error_type', '')}: {result.get('error_message', '')}")
        if staging.exists():
            partial = output_dir / "mining" / "partial" / f"{run_id}_failed.partial.jsonl"
            os.replace(staging, partial)
            status = update_status(status_file, status, partial_output_path=relative_to(root, partial))

    rebuild_runs_csv(output_dir)
    append_supervisor_log(output_dir, {"event": "WORKER_FINAL", "run_id": run_id, "minsup_count": min_count,
                                       "status": status["status"], "reason_code": status.get("reason_code", ""),
                                       "runtime_seconds": status.get("runtime_seconds"), "exit_code": exit_code})
    return status


def verify_reusable(output_dir: pathlib.Path, config: dict, status: dict) -> bool:
    if status.get("status") not in {"COMPLETED_FULL", "COMPLETED_ZERO"} or not status.get("final_committed"):
        return False
    if status.get("audit_status") != "PASS" or status.get("input_sha256") != config["input_sha256"]:
        return False
    if status.get("engine_revision") != config["engine_revision"] or status.get("engine_source_sha256") != config["engine_source_sha256"]:
        return False
    if status.get("budget_revision") != config["budget_revision"]:
        return False
    if status.get("configuration") != config["configuration"] or status.get("minsup_count") not in MIN_COUNTS:
        return False
    sample = status.get("audit_sample_itemsets")
    expected_supports = status.get("audit_sample_expected_supports")
    observed_supports = status.get("audit_sample_observed_supports")
    if (status.get("audit_sample_seed") != 42 or not isinstance(sample, list)
            or not isinstance(expected_supports, list) or not isinstance(observed_supports, list)
            or len(sample) != status.get("sampled_itemsets_independently_verified")
            or len(expected_supports) != len(sample) or len(observed_supports) != len(sample)
            or expected_supports != observed_supports or status.get("audit_sample_mismatch_count") != 0):
        return False
    checked_counts = status.get("cross_threshold_min_counts_checked")
    checked_run_ids = status.get("cross_threshold_run_ids_checked")
    if (not isinstance(checked_counts, list) or not isinstance(checked_run_ids, list)
            or len(checked_counts) != status.get("cross_threshold_outputs_checked")
            or len(checked_run_ids) != len(checked_counts)
            or status.get("cross_threshold_mismatch_count") != 0):
        return False
    try:
        manifest = canonical_manifest(output_dir)[1]
        expected_higher = active_higher_outputs(
            output_dir, manifest, status["minsup_count"], pathlib.Path(config["repo_root"]))
    except (OSError, KeyError, ValueError, TypeError):
        return False
    if ([count for count, _path, _run_id in expected_higher] != checked_counts
            or [run_id for _count, _path, run_id in expected_higher] != checked_run_ids):
        return False
    output = pathlib.Path(config["repo_root"]) / status.get("output_path", "")
    if not output.is_file() or sha256_file(output) != status.get("output_sha256"):
        return False
    if output.stat().st_size != status.get("output_size_bytes") or output.stat().st_size > config["output_limit_bytes"]:
        return False
    try:
        info = validate_itemsets(output, status["minsup_count"])
    except Exception:
        return False
    if info["record_count"] != status.get("record_count") or info["record_count"] != status.get("total_frequent_itemsets"):
        return False
    if status.get("status") == "COMPLETED_ZERO" and (info["record_count"] != 0 or status.get("max_itemset_length") != 0):
        return False
    return status.get("status") != "COMPLETED_FULL" or info["record_count"] > 0


def run_supervisor(output_dir: pathlib.Path) -> None:
    config = load_config(output_dir)
    root = pathlib.Path(config["repo_root"])
    manifest_path, manifest = canonical_manifest(output_dir)
    source = root / config["input_source_path"]
    preflight = input_preflight(source, config["input_sha256"])
    config["legacy_guardrails_applies"] = preflight["legacy_guardrails_applies"]
    config["legacy_guardrail_status"] = preflight["legacy_guardrail_status"]
    config["source_guardrails"] = {"support_6": preflight["support_6"], "support_26": preflight["support_26"],
                                   "support_6_26": preflight["support_6_26"], "max_singleton_support": preflight["max_singleton_support"]}
    if not manifest.get("canonical_runs"):
        raise RuntimeError("Canonical run IDs are missing from experiment manifest")

    for min_count in MIN_COUNTS:
        pct = int(FRACTIONS[min_count] * 100)
        run_id = manifest["canonical_runs"][f"{pct:02d}"]
        status_file = sidecar_path(output_dir, run_id)
        if not status_file.is_file():
            raise FileNotFoundError(f"Missing authoritative sidecar: {status_file}")
        status = read_toml(status_file)
        if verify_reusable(output_dir, config, status):
            append_supervisor_log(output_dir, {"event": "REUSED_VERIFIED_FINAL", "run_id": run_id, "minsup_count": min_count})
            print(f"REUSE {pct}% {status['status']} run_id={run_id}", flush=True)
            continue
        if status.get("final_committed"):
            status = update_status(status_file, status, phase="FINAL", status="INVALID_OUTPUT",
                reason_code="COMMIT_MISMATCH", audit_status="FAIL", final_committed=False,
                total_frequent_itemsets="NA", max_itemset_length="NA", output_size_bytes="NA", record_count="NA",
                notes="A committed output no longer matches its final sidecar; preserved the original artifact and evidence")
            rebuild_runs_csv(output_dir)
            print(f"INVALID_OUTPUT {pct}% COMMIT_MISMATCH; preserved evidence, no implicit reuse", flush=True)
            continue
        if status.get("phase") in {"LAUNCHING", "RUNNING"}:
            unit = status.get("worker_unit") or worker_unit(run_id)
            props = systemctl_show(unit)
            if props:
                print(f"RECONCILE {pct}% unit={unit} active={props.get('ActiveState')}", flush=True)
                staging = status_file.parent / "patterns.jsonl.staging"
                result_path = status_file.parent / "worker_result.toml"
                exact = choose_exact_output(output_dir, run_id, min_count)
                status = monitor_worker(root, output_dir, config, run_id, min_count, status, status_file,
                    staging, result_path, status_file.parent / "worker_stdout.log", exact, time.monotonic())
                continue
            status = update_status(status_file, status, phase="FINAL", status="UNKNOWN_INTERRUPTED",
                reason_code="WORKER_MISSING_WITHOUT_FINAL", final_committed=False, audit_status="NA", end_at=utc_now(),
                total_frequent_itemsets="NA", max_itemset_length="NA", runtime_seconds="NA", peak_rss_mb="NA",
                output_size_bytes="NA", record_count="NA", notes="No worker unit or final commit was found after a persisted launch intent; no automatic retry was started")
            rebuild_runs_csv(output_dir)
            print(f"UNKNOWN_INTERRUPTED {pct}% worker missing; preserved staging", flush=True)
            continue
        if status.get("phase") == "COMMITTING":
            candidate = status.get("candidate_output_path", "")
            exact = root / candidate if candidate else choose_exact_output(output_dir, run_id, min_count)
            if exact.is_file():
                quarantine_orphan(exact, output_dir, run_id)
            status = update_status(status_file, status, phase="FINAL", status="UNKNOWN_INTERRUPTED",
                reason_code="CRASH_AFTER_EXACT_RENAME_BEFORE_FINAL_SIDECAR", final_committed=False,
                audit_status="NA", end_at=utc_now(), total_frequent_itemsets="NA", max_itemset_length="NA",
                runtime_seconds=status.get("runtime_seconds", "NA"), peak_rss_mb="NA", output_size_bytes="NA",
                record_count="NA", notes="Uncommitted exact-looking output was quarantined; it was not reused")
            rebuild_runs_csv(output_dir)
            print(f"UNKNOWN_INTERRUPTED {pct}% orphan quarantined after COMMITTING crash", flush=True)
            continue
        if status.get("status") != "NOT_RUN":
            print(f"SKIP {pct}% status={status.get('status')} reason={status.get('reason_code', '')}", flush=True)
            continue

        try:
            status = launch_worker(root, output_dir, config, run_id, min_count, status, status_file)
        except Exception as error:
            unit = status.get("worker_unit") or worker_unit(run_id)
            props = systemctl_show(unit) if status.get("phase") in {"LAUNCHING", "RUNNING"} else {}
            if props:
                status = monitor_worker(root, output_dir, config, run_id, min_count, status, status_file,
                    status_file.parent / "patterns.jsonl.staging", status_file.parent / "worker_result.toml",
                    status_file.parent / "worker_stdout.log", choose_exact_output(output_dir, run_id, min_count), time.monotonic())
            else:
                status = update_status(status_file, status, phase="FINAL", status="FAILED",
                    reason_code="SUPERVISOR_LAUNCH_OR_AUDIT_ERROR", final_committed=False, audit_status="FAIL",
                    end_at=utc_now(), total_frequent_itemsets="NA", max_itemset_length="NA",
                    output_size_bytes="NA", record_count="NA", notes=f"{type(error).__name__}: {error}")
            rebuild_runs_csv(output_dir)
            append_supervisor_log(output_dir, {"event": "SUPERVISOR_ERROR", "run_id": run_id, "minsup_count": min_count,
                                               "error_type": type(error).__name__, "error": str(error)})
            print(f"FAILED {pct}% {type(error).__name__}: {error}", flush=True)
        else:
            print(f"{status['status']} {pct}% count={status.get('total_frequent_itemsets')} runtime={status.get('runtime_seconds')}", flush=True)

    rebuild_runs_csv(output_dir)
    print(json.dumps(six_statuses(output_dir), ensure_ascii=False, indent=2), flush=True)


def six_statuses(output_dir: pathlib.Path) -> list[dict]:
    path = output_dir / "mining" / "runs.csv"
    if not path.is_file():
        return []
    with open(path, newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def launch_supervisor(output_dir: pathlib.Path) -> None:
    config = load_config(output_dir)
    root = pathlib.Path(config["repo_root"])
    suffix = config["input_sha256"][:8]
    unit = f"fim-supervisor-{config.get('backend', 'set')}-{config['budget_revision']}-{suffix}.service"
    if active_unit(unit):
        print(json.dumps({"launched": False, "reason": "SUPERVISOR_ALREADY_ACTIVE", "unit": unit}))
        return
    log_path = output_dir / "report" / "supervisor.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    command = ["systemd-run", "--user", "--no-block", f"--unit={unit.removesuffix('.service')}",
        f"--working-directory={root}", "--property=RuntimeMaxSec=28800s", "--property=KillMode=control-group",
        f"--property=StandardOutput=append:{log_path}", f"--property=StandardError=append:{log_path}",
        "--", "/usr/bin/python3", str(root / MINING_SCRIPTS / "supervisor.py"),
        "--run", "--output-dir", str(output_dir)]
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode != 0:
        raise RuntimeError(f"Could not launch external supervisor: {result.stderr.strip()}")
    append_supervisor_log(output_dir, {"event": "SUPERVISOR_SERVICE_LAUNCHED", "unit": unit, "launch_ack": result.stdout.strip()})
    print(json.dumps({"launched": True, "unit": unit, "log_path": relative_to(root, log_path),
                      "acknowledgement": result.stdout.strip()}, ensure_ascii=False))


def status_command(output_dir: pathlib.Path) -> None:
    config = load_config(output_dir)
    suffix = config["input_sha256"][:8]
    unit = f"fim-supervisor-{config.get('backend', 'set')}-{config['budget_revision']}-{suffix}.service"
    print(json.dumps({"supervisor_unit": unit, "supervisor": systemctl_show(unit),
                      "runs": six_statuses(output_dir)}, ensure_ascii=False, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--init", action="store_true")
    mode.add_argument("--launch", action="store_true")
    mode.add_argument("--run", action="store_true")
    mode.add_argument("--status", action="store_true")
    parser.add_argument("--repo-root")
    parser.add_argument("--input-path")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--runtime-env")
    parser.add_argument("--wall-time-seconds-per-run", type=int, default=3600)
    parser.add_argument("--memory-limit-mb-per-worker", type=int, default=3072)
    parser.add_argument("--output-limit-bytes", type=int, default=8 * 1024**3)
    parser.add_argument("--budget-revision", default="b1")
    parser.add_argument("--backend", choices=("set", "bitvector"), default="set")
    args = parser.parse_args()
    output_dir = pathlib.Path(args.output_dir).resolve()
    if args.init:
        required = (args.repo_root, args.input_path, args.runtime_env)
        if not all(required):
            parser.error("--init requires --repo-root, --input-path, and --runtime-env")
        initialize(args)
    elif args.launch:
        launch_supervisor(output_dir)
    elif args.run:
        run_supervisor(output_dir)
    else:
        status_command(output_dir)


if __name__ == "__main__":
    main()
