#!/usr/bin/env python3
"""Verify visual-word witnesses and build real Fashion-MNIST interpretation galleries."""

from __future__ import annotations

import argparse
import base64
import csv
from collections import Counter
import gzip
import hashlib
import html
import json
import math
import pathlib
import random
import re
import struct
import tomllib
import zlib

import analysis
import supervisor

FASHION_CLASSES = ("T-shirt/top", "Trouser", "Pullover", "Dress", "Coat",
                   "Sandal", "Shirt", "Sneaker", "Bag", "Ankle boot")
ANNOTATION_FIELDS = ["pattern_id", "decodable", "witness_valid", "review_status", "visual_coherence",
                     "interpretation", "limitations", "reviewer", "reviewed_at", "evidence_paths"]


def parse_stable_image_id(value: str) -> tuple[str, int]:
    matched = re.fullmatch(r"(train):(0|[1-9][0-9]*)|(test):(0|[1-9][0-9]*)", value)
    if not matched:
        raise ValueError(f"Invalid Fashion-MNIST image ID: {value}")
    split = matched.group(1) or matched.group(3)
    index = int(matched.group(2) or matched.group(4))
    if index >= (60_000 if split == "train" else 10_000):
        raise ValueError(f"Fashion-MNIST image ID is out of range: {value}")
    return split, index


def parse_selected_itemset_row(row: dict) -> dict:
    try:
        order = int(row["selection_order"])
        backend = row["backend"]
        minsup_percent = int(row["minsup_percent"])
        raw_items = json.loads(row["items"])
        support_count = int(row["support_count"])
        pattern_id = row["pattern_id"].strip()
    except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
        raise ValueError(f"Invalid selected-itemset CSV row: {error}") from error
    if order < 1 or backend != "set" or minsup_percent not in {80, 60, 40, 20, 10, 5}:
        raise ValueError("Selection must use a positive order, Set backend, and one release threshold")
    if not isinstance(raw_items, list) or not raw_items or any(type(item) is not int or item not in range(1, 33) for item in raw_items):
        raise ValueError("Selected items must be a non-empty array of visual word IDs 1:32")
    if raw_items != sorted(set(raw_items)):
        raise ValueError("Selected items must be sorted and unique")
    if not int(round(minsup_percent / 100 * 70_000)) <= support_count <= 70_000 or not pattern_id:
        raise ValueError("Selected itemset support or pattern_id is invalid")
    return {**row, "selection_order": order, "backend": backend,
            "minsup_percent": minsup_percent, "items_tuple": tuple(raw_items),
            "items_set": set(raw_items), "support_count": support_count,
            "length": len(raw_items), "pattern_id": pattern_id,
            "observed_at_minsup": f"{minsup_percent}%"}


def validate_retrieval_count(expected_support: int, image_ids) -> None:
    if len(image_ids) != expected_support:
        raise ValueError(f"Retrieved image count {len(image_ids)} differs from support {expected_support}")


def validate_class_count_reconciliation(class_counts: dict, expected_support: int) -> None:
    if sum(class_counts.values()) != expected_support:
        raise ValueError("Class support counts do not sum to retrieved support")


def initial_review_status() -> str:
    return "PENDING_REVIEW"


def csv_rows(path: pathlib.Path):
    with open(path, newline="", encoding="utf-8") as stream:
        yield from csv.DictReader(stream)


def write_csv_atomic(path: pathlib.Path, fields: list[str], rows) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    with open(temporary, "w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow({field: row.get(field, "") for field in fields})
        stream.flush()
        import os
        os.fsync(stream.fileno())
    import os
    os.replace(temporary, path)
    supervisor.fsync_directory(path.parent)


def load_selected(output_dir: pathlib.Path) -> list[dict]:
    path = output_dir / "mining" / "selected_itemsets.csv"
    if not path.is_file():
        raise FileNotFoundError("Select Set itemsets in Notebook 03 first; mining/selected_itemsets.csv is missing")
    patterns = []
    for row in csv_rows(path):
        patterns.append(parse_selected_itemset_row(row))
    if not patterns:
        raise RuntimeError("No Set itemsets were selected for interpretation")
    if len(patterns) not in {3, 4}:
        raise ValueError("Automatic representative selection must contain exactly 3 or 4 itemsets")
    if len({row["pattern_id"] for row in patterns}) != len(patterns):
        raise ValueError("Selected itemset CSV contains duplicate pattern IDs")
    if sorted(row["selection_order"] for row in patterns) != list(range(1, len(patterns) + 1)):
        raise ValueError("Selected itemset orders must be contiguous starting from 1")
    return patterns


def _parse_image_key(value: str):
    return parse_stable_image_id(value) and value if ":" in value else int(value)


def load_metadata(source_dir: pathlib.Path) -> tuple[dict, dict, dict[int, int], bool]:
    metadata_path = source_dir / "image_metadata.csv"
    mapping_path = source_dir / "tid_image_mapping.csv"
    metadata = {}
    labels_complete = True
    for row in csv_rows(metadata_path):
        image_id = _parse_image_key(row["image_id"])
        if image_id in metadata:
            raise ValueError(f"Duplicate image_id in image_metadata.csv: {image_id}")
        raw_label = row.get("class_label", "").strip()
        try:
            label = int(raw_label) if raw_label else None
        except ValueError:
            label = None
        if label is not None and not 0 <= label < len(FASHION_CLASSES):
            label = None
        labels_complete = labels_complete and label is not None
        release_schema = "source_index" in row and "split" in row
        split = row["split"] if release_schema else row["original_split"]
        source_index = int(row["source_index"]) if release_schema else int(row["original_index"]) - 1
        if isinstance(image_id, str):
            parsed_split, parsed_index = parse_stable_image_id(image_id)
            if (parsed_split, parsed_index) != (split, source_index):
                raise ValueError(f"Stable image ID does not match metadata split/index: {image_id}")
        if source_index < 0:
            raise ValueError(f"Invalid source index for image {image_id}")
        metadata[image_id] = {"image_id": image_id, "original_split": split,
                              "original_index": source_index + 1, "class_label": label}
    tid_mapping = {}
    for row in csv_rows(mapping_path):
        tid = int(row["tid"])
        if tid in tid_mapping:
            raise ValueError(f"Duplicate TID in tid_image_mapping.csv: {tid}")
        image_id = _parse_image_key(row["image_id"])
        release_schema = "source_index" in row and "split" in row
        split = row["split"] if release_schema else row["original_split"]
        source_index = int(row["source_index"]) if release_schema else int(row["original_index"]) - 1
        if isinstance(image_id, str):
            parsed_split, parsed_index = parse_stable_image_id(image_id)
            if (parsed_split, parsed_index) != (split, source_index):
                raise ValueError(f"Stable image ID does not match TID mapping split/index: {image_id}")
        tid_mapping[tid] = {"tid": tid, "image_id": image_id,
                            "original_split": split, "original_index": source_index + 1}
    class_totals = {label: 0 for label in range(len(FASHION_CLASSES))}
    if len(metadata) != 70_000 or len(tid_mapping) != 70_000:
        raise ValueError(f"Expected 70,000 metadata/mapping rows; got {len(metadata)}/{len(tid_mapping)}")
    for image_id, row in metadata.items():
        if row["class_label"] is not None:
            class_totals[row["class_label"]] += 1
    labels_complete = labels_complete and sum(class_totals.values()) == 70_000
    for tid, row in tid_mapping.items():
        image = metadata.get(row["image_id"])
        if image is None or image["original_split"] != row["original_split"] or image["original_index"] != row["original_index"]:
            raise ValueError(f"TID/image metadata join mismatch at TID {tid}")
    return metadata, tid_mapping, class_totals if labels_complete else {}, labels_complete


def load_idx_images(path: pathlib.Path) -> tuple[int, int, int, bytes]:
    with gzip.open(path, "rb") as stream:
        header = stream.read(16)
        if len(header) != 16:
            raise ValueError(f"Truncated IDX image header: {path}")
        magic, count, rows, columns = struct.unpack(">IIII", header)
        payload = stream.read()
    if magic != 2051 or (rows, columns) != (28, 28) or len(payload) != count * rows * columns:
        raise ValueError(f"Invalid IDX image archive: {path}")
    return count, rows, columns, payload


def load_idx_labels(path: pathlib.Path) -> bytes:
    with gzip.open(path, "rb") as stream:
        header = stream.read(8)
        if len(header) != 8:
            raise ValueError(f"Truncated IDX label header: {path}")
        magic, count = struct.unpack(">II", header)
        payload = stream.read()
    if magic != 2049 or len(payload) != count:
        raise ValueError(f"Invalid IDX label archive: {path}")
    return payload


def verify_raw_assets(source_dir: pathlib.Path, raw_dir: pathlib.Path) -> dict:
    with open(source_dir / "config_snapshot.toml", "rb") as stream:
        construction_config = tomllib.load(stream)
    expected = construction_config["data_archive_sha256"]
    assets = {}
    missing_label_archives = []
    missing_image_archives = []
    for filename, digest in expected.items():
        path = raw_dir / filename
        if not path.is_file() and filename in {"train-labels-idx1-ubyte.gz", "t10k-labels-idx1-ubyte.gz"}:
            missing_label_archives.append(filename)
            continue
        if not path.is_file() and filename in {"train-images-idx3-ubyte.gz", "t10k-images-idx3-ubyte.gz"}:
            missing_image_archives.append(filename)
            continue
        if not path.is_file():
            missing_image_archives.append(filename)
            continue
        actual = supervisor.sha256_file(path)
        if actual != digest:
            raise ValueError(f"Fashion-MNIST raw archive checksum mismatch: {filename}")
        assets[filename] = actual
    for filename in ("train-labels-idx1-ubyte.gz", "t10k-labels-idx1-ubyte.gz"):
        if not (raw_dir / filename).is_file() and filename not in missing_label_archives:
            missing_label_archives.append(filename)
    for filename in ("train-images-idx3-ubyte.gz", "t10k-images-idx3-ubyte.gz"):
        if not (raw_dir / filename).is_file() and filename not in missing_image_archives:
            missing_image_archives.append(filename)
    image_paths = (raw_dir / "train-images-idx3-ubyte.gz", raw_dir / "t10k-images-idx3-ubyte.gz")
    if all(path.is_file() for path in image_paths):
        train_count, rows, columns, train_pixels = load_idx_images(image_paths[0])
        test_count, _, _, test_pixels = load_idx_images(image_paths[1])
        pixels = {"train": train_pixels, "test": test_pixels}
    else:
        train_count, test_count, rows, columns = None, None, 28, 28
        pixels = None
    label_paths = (raw_dir / "train-labels-idx1-ubyte.gz", raw_dir / "t10k-labels-idx1-ubyte.gz")
    raw_labels = None
    if all(path.is_file() for path in label_paths):
        train_labels = load_idx_labels(label_paths[0])
        test_labels = load_idx_labels(label_paths[1])
        raw_labels = {"train": train_labels, "test": test_labels}
    if train_count is not None and (train_count != 60_000 or test_count != 10_000):
        raise ValueError(f"IDX split counts differ from Fashion-MNIST: {train_count}/{test_count}")
    if raw_labels is not None and (len(raw_labels["train"]) != 60_000 or len(raw_labels["test"]) != 10_000):
        raise ValueError("Raw Fashion-MNIST label counts do not match IDX image counts")
    return {"assets": assets, "train_count": train_count, "test_count": test_count,
            "rows": rows, "columns": columns, "pixels": pixels,
            "labels": raw_labels, "missing_label_archives": missing_label_archives,
            "missing_image_archives": missing_image_archives}


def find_repo_root(start: pathlib.Path) -> pathlib.Path:
    current = start.resolve()
    while current != current.parent:
        if (current / "Project.toml").is_file() and (current / "src" / "EclatFIM.jl").is_file():
            return current
        current = current.parent
    raise FileNotFoundError(f"Could not find repository root from {start}")


def verified_artifact_path(repo_root: pathlib.Path, manifest: dict, artifact_name: str) -> pathlib.Path:
    try:
        artifact = manifest["artifacts"][artifact_name]
        path = repo_root / artifact["path"]
        expected_hash = artifact["sha256"]
    except (KeyError, TypeError) as error:
        raise ValueError(f"TC7 manifest is missing artifact {artifact_name}") from error
    if not path.is_file() or supervisor.sha256_file(path) != expected_hash:
        raise ValueError(f"TC7 artifact failed its path/hash check: {artifact_name}")
    return path


def attach_verified_labels(metadata: dict, assets: dict) -> tuple[dict[int, int], bool, str]:
    raw_labels = assets["labels"]
    if raw_labels is not None:
        for image in metadata.values():
            split = image["original_split"]
            index = image["original_index"]
            label_bytes = raw_labels.get(split)
            if label_bytes is None or not 1 <= index <= len(label_bytes):
                raise ValueError(f"Image metadata points outside raw Fashion-MNIST split: {split}/{index}")
            raw_label = label_bytes[index - 1]
            if not 0 <= raw_label < len(FASHION_CLASSES):
                raise ValueError(f"Invalid raw Fashion-MNIST label {raw_label} at {split}/{index}")
            if image["class_label"] is not None and image["class_label"] != raw_label:
                raise ValueError(f"Raw IDX label mismatch for image_id={image['image_id']}")
            image["class_label"] = raw_label

    totals = {label: 0 for label in range(len(FASHION_CLASSES))}
    labels_complete = all(image["class_label"] is not None for image in metadata.values())
    if labels_complete:
        for image in metadata.values():
            totals[image["class_label"]] += 1
        labels_complete = sum(totals.values()) == 70_000
    if labels_complete:
        provenance = "image_metadata.csv verified against raw IDX label archives" if raw_labels is not None else "image_metadata.csv"
        return totals, True, provenance
    return {}, False, "BLOCKED_MISSING_LABELS: no complete image_metadata.csv labels or raw IDX label archives"


def image_offset(meta: dict) -> int:
    index = meta["original_index"]
    if index < 1:
        raise ValueError("original_index must use the source's 1-based indexing")
    return (index - 1) * 28 * 28


def patch_pixels(pixels: bytes, meta: dict, patch_row: int, patch_col: int) -> tuple[bytes, tuple[int, ...]]:
    if not 1 <= patch_row <= 7 or not 1 <= patch_col <= 7:
        raise ValueError(f"Invalid 4x4 patch coordinate ({patch_row},{patch_col})")
    start_y, start_x = (patch_row - 1) * 4, (patch_col - 1) * 4
    base = image_offset(meta)
    row_major = []
    for y in range(start_y, start_y + 4):
        row_major.extend(pixels[base + y * 28 + start_x:base + y * 28 + start_x + 4])
    column_major = []
    for x in range(start_x, start_x + 4):
        for y in range(start_y, start_y + 4):
            column_major.append(pixels[base + y * 28 + x])
    return bytes(row_major), tuple(column_major)


def load_centroids(path: pathlib.Path) -> dict[int, tuple[float, ...]] | None:
    if not path.is_file():
        return None
    centroids = {word: [None] * 16 for word in range(1, 33)}
    for row in csv_rows(path):
        word = int(row["word_id"])
        pixel = int(row["pixel_index"])
        if word not in centroids or not 1 <= pixel <= 16:
            raise ValueError("Invalid word/pixel index in codebook centroid export")
        centroids[word][pixel - 1] = float(row["centroid_value"])
    if any(any(value is None for value in values) for values in centroids.values()):
        raise ValueError("Expected all 32 codebook centroids with 16 pixels each")
    return {word: tuple(values) for word, values in centroids.items()}


def collect_visual_asset_blockers(centroids_available: bool, assets: dict, patch_assignments: pathlib.Path) -> list[str]:
    blockers = []
    if not centroids_available:
        blockers.append("MISSING_CODEBOOK_OR_CENTROID_EXPORT")
    if assets["pixels"] is None:
        blockers.extend(f"MISSING_RAW_IMAGE:{name}" for name in assets["missing_image_archives"])
    if not patch_assignments.is_file():
        blockers.append("MISSING_PATCH_ASSIGNMENTS")
    return blockers


def collect_pattern_evidence(input_path: pathlib.Path, patterns: list[dict], metadata: dict,
                             tid_mapping: dict[int, dict]) -> dict:
    supporters = {row["pattern_id"]: [] for row in patterns}
    labels_available = all(row["class_label"] is not None for row in metadata.values())
    class_counts = ({row["pattern_id"]: {label: 0 for label in range(10)} for row in patterns}
                    if labels_available else None)
    support_counts = {row["pattern_id"]: 0 for row in patterns}
    contrasts = {row["pattern_id"]: None for row in patterns}
    contrast_items = {row["pattern_id"]: () for row in patterns}
    contrast_by_class = {row["pattern_id"]: {} for row in patterns}
    class_totals = Counter(image["class_label"] for image in metadata.values()
                           if image["class_label"] is not None)
    id_to_pattern = {row["pattern_id"]: row for row in patterns}
    rows = 0
    with open(input_path, encoding="utf-8") as stream:
        for line_number, line in enumerate(stream, 1):
            transaction = json.loads(line)
            tid = int(transaction["tid"])
            image_id = transaction["image_id"]
            if isinstance(image_id, str):
                parse_stable_image_id(image_id)
            else:
                image_id = int(image_id)
            mapping = tid_mapping.get(tid)
            if mapping is None or mapping["image_id"] != image_id:
                raise ValueError(f"JSONL row to TID/image mapping mismatch on row {line_number}")
            image = metadata.get(image_id)
            if image is None:
                raise ValueError(f"Metadata missing image_id={image_id}")
            items = set(transaction["items"])
            rows += 1
            for pattern_id, pattern in id_to_pattern.items():
                query = pattern["items_set"]
                if query.issubset(items):
                    supporters[pattern_id].append(image_id)
                    if class_counts is not None:
                        class_counts[pattern_id][image["class_label"]] += 1
                    support_counts[pattern_id] += 1
                else:
                    overlap = len(query & items)
                    candidate = (overlap, str(image_id), image_id)
                    if contrasts[pattern_id] is None or candidate > contrasts[pattern_id]:
                        contrasts[pattern_id] = candidate
                        contrast_items[pattern_id] = tuple(sorted(query & items))
                    label = image["class_label"] if image["class_label"] is not None else 0
                    current = contrast_by_class[pattern_id].get(label)
                    if current is None or candidate > current[0]:
                        contrast_by_class[pattern_id][label] = (
                            candidate, tuple(sorted(query & items)))
    if rows != 70_000:
        raise ValueError(f"Expected 70,000 transaction lines during retrieval scan, read {rows}")
    for pattern in patterns:
        pattern_id = pattern["pattern_id"]
        validate_retrieval_count(pattern["support_count"], supporters[pattern_id])
        if class_counts is not None:
            validate_class_count_reconciliation(class_counts[pattern_id], support_counts[pattern_id])
    selected_contrasts = {}
    selected_contrast_items = {}
    for pattern in patterns:
        pattern_id = pattern["pattern_id"]
        best = contrasts[pattern_id]
        best_items = contrast_items[pattern_id]
        if class_counts is not None:
            target_label = max(class_counts[pattern_id], key=lambda label: (
                class_counts[pattern_id][label] / class_totals[label],
                class_counts[pattern_id][label], -label))
            same_class = contrast_by_class[pattern_id].get(target_label)
            if same_class is not None:
                best, best_items = same_class
        selected_contrasts[pattern_id] = best[2] if best else None
        selected_contrast_items[pattern_id] = best_items
    return {"supporters": supporters, "class_counts": class_counts,
            "labels_available": labels_available,
            "support_counts": support_counts,
            "contrasts": selected_contrasts,
            "contrast_items": selected_contrast_items}


def sample_supporters(patterns: list[dict], evidence: dict, metadata: dict, seed: int = 42,
                      maximum: int = 6) -> tuple[dict, dict]:
    samples = {}
    contrast_ids = {}
    class_totals = Counter(meta["class_label"] for meta in metadata.values()
                           if meta["class_label"] is not None)
    for pattern in patterns:
        pattern_id = pattern["pattern_id"]
        groups = {}
        for image_id in evidence["supporters"][pattern_id]:
            label = metadata[image_id]["class_label"]
            groups.setdefault(label if label is not None else 0, []).append(image_id)
        rng = random.Random(seed + pattern["selection_order"])
        for ids in groups.values():
            rng.shuffle(ids)
        target_label = max(groups, key=lambda label: (
            len(groups[label]) / class_totals[label] if class_totals.get(label) else 0,
            len(groups[label]), -label))
        label_order = [target_label] + [label for label in sorted(groups) if label != target_label]
        chosen = []
        while len(chosen) < maximum:
            added = False
            for label in label_order:
                if groups[label]:
                    chosen.append(groups[label].pop())
                    added = True
                    if len(chosen) == maximum:
                        break
            if not added:
                break
        samples[pattern_id] = chosen
        contrast_ids[pattern_id] = evidence["contrasts"][pattern_id]
    return samples, contrast_ids, evidence["contrast_items"]


def selected_patch_witnesses(path: pathlib.Path, patterns: list[dict], sample_ids: dict,
                             contrast_ids: dict, contrast_items: dict) -> dict:
    pattern_by_id = {row["pattern_id"]: row for row in patterns}
    image_pattern_words = {}
    for pattern_id, image_ids in sample_ids.items():
        for image_id in image_ids:
            image_pattern_words.setdefault(image_id, {}).setdefault(pattern_id, set()).update(pattern_by_id[pattern_id]["items_tuple"])
    for pattern_id, image_id in contrast_ids.items():
        if image_id is not None:
            image_pattern_words.setdefault(image_id, {}).setdefault(pattern_id, set()).update(contrast_items[pattern_id])
    witnesses = {image_id: {pattern_id: {} for pattern_id in patterns_for_image}
                 for image_id, patterns_for_image in image_pattern_words.items()}
    wanted_words = {word for patterns_for_image in image_pattern_words.values()
                    for words in patterns_for_image.values() for word in words}
    with open(path, newline="", encoding="utf-8") as stream:
        for row in csv.DictReader(stream):
            image_id, word = _parse_image_key(row["image_id"]), int(row["word_id"])
            if image_id not in image_pattern_words or word not in wanted_words:
                continue
            for pattern_id, words in image_pattern_words[image_id].items():
                if word in words:
                    witnesses[image_id][pattern_id].setdefault(word, []).append(
                        (int(row["patch_row"]), int(row["patch_col"])))
    for image_id, pattern_map in witnesses.items():
        for pattern_id, by_word in pattern_map.items():
            required_words = image_pattern_words[image_id][pattern_id]
            for word in image_pattern_words[image_id][pattern_id]:
                if not by_word.get(word):
                    raise ValueError(f"Missing actual patch witness for {pattern_id}, image {image_id}, word {word}")
    return witnesses


def png_gray(width: int, height: int, pixels: bytes) -> bytes:
    if len(pixels) != width * height:
        raise ValueError("PNG pixel buffer dimensions do not match")
    def chunk(kind: bytes, body: bytes) -> bytes:
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xffffffff)
    scanlines = b"".join(b"\x00" + pixels[row * width:(row + 1) * width] for row in range(height))
    header = struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(scanlines, 9)) + chunk(b"IEND", b"")


def b64_png(width: int, height: int, pixels: bytes) -> str:
    return "data:image/png;base64," + base64.b64encode(png_gray(width, height, pixels)).decode("ascii")


def centroid_image(values: tuple[float, ...]) -> bytes:
    pixels = bytearray(16)
    for row in range(4):
        for column in range(4):
            value = values[row + 4 * column]
            pixels[row * 4 + column] = max(0, min(255, round(value * 255)))
    return bytes(pixels)


def idx_patch_from_assignment(pixels: bytes, meta: dict, row: dict) -> tuple[bytes, tuple[int, ...]]:
    return patch_pixels(pixels, meta, row["patch_row"], row["patch_col"])


def find_nearest_exemplars(assignments_path: pathlib.Path, patterns: list[dict], metadata: dict,
                           images: dict, centroids: dict[int, tuple[float, ...]], maximum: int = 3) -> dict:
    needed_words = sorted({word for pattern in patterns for word in pattern["items_tuple"]})
    best = {word: [] for word in needed_words}
    with open(assignments_path, newline="", encoding="utf-8") as stream:
        for row in csv.DictReader(stream):
            word = int(row["word_id"])
            if word not in best:
                continue
            image_id = _parse_image_key(row["image_id"])
            meta = metadata.get(image_id)
            if meta is None:
                raise ValueError(f"Patch assignment references unknown image {image_id}")
            pixels = images[meta["original_split"]]
            patch_row = int(row["patch_row"])
            patch_col = int(row["patch_col"])
            row_major, column_major = patch_pixels(pixels, meta, patch_row, patch_col)
            centroid = centroids[word]
            distance = sum((value / 255 - centroid[index]) ** 2 for index, value in enumerate(column_major))
            record = {"image_id": image_id, "patch_row": patch_row, "patch_col": patch_col,
                      "distance": distance, "pixels": row_major}
            candidates = best[word]
            if len(candidates) < maximum or distance < candidates[-1]["distance"]:
                candidates.append(record)
                candidates.sort(key=lambda item: (item["distance"], item["image_id"], item["patch_row"], item["patch_col"]))
                del candidates[maximum:]
    missing = [word for word, records in best.items() if not records]
    if missing:
        raise ValueError(f"No retained real patches found for visual words {missing}")
    return best


def image_png_data(meta: dict, images: dict) -> str:
    pixels = images[meta["original_split"]]
    start = image_offset(meta)
    return b64_png(28, 28, pixels[start:start + 28 * 28])


def add_svg_image(parts: list[str], href: str, x: float, y: float, width: float, height: float,
                  label: str = "") -> None:
    parts.append(f'<image href="{href}" x="{x:.1f}" y="{y:.1f}" width="{width:.1f}" height="{height:.1f}" image-rendering="pixelated"/>')
    parts.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{width:.1f}" height="{height:.1f}" fill="none" stroke="#536273" stroke-width="1"/>')
    if label:
        parts.append(f'<text x="{x+width/2:.1f}" y="{y+height+16:.1f}" text-anchor="middle" font-family="sans-serif" font-size="11">{html.escape(label)}</text>')


def create_pattern_card(path: pathlib.Path, pattern: dict, metadata: dict, images: dict,
                        centroids: dict[int, tuple[float, ...]], exemplars: dict,
                        sample_ids: list[int], contrast_id: int | None, witnesses: dict,
                        class_counts: dict | None) -> dict:
    width = 1450
    support_palette = ("#e45756", "#4c78a8", "#59a14f", "#f2a541", "#b279a2", "#ff9da7")
    color_by_word = {word: support_palette[index] for index, word in enumerate(pattern["items_tuple"])}
    contrast_color = "#a678b3"
    itemset_text = ", ".join(map(str, pattern["items_tuple"]))
    support_percent = f"{pattern['support_count'] / 70_000:.2%}".replace(".", ",")
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="100" viewBox="0 0 {width} 100">',
        '<rect width="100%" height="100%" fill="#ffffff"/>',
        f'<text x="28" y="36" font-family="sans-serif" font-size="22" font-weight="700">Mẫu thị giác {{{html.escape(itemset_text)}}}</text>',
        f'<text x="28" y="64" font-family="sans-serif" font-size="14">Độ hỗ trợ: {pattern["support_count"]:,}/70.000 ảnh ({support_percent}) · độ dài {pattern["length"]} · minsup {html.escape(pattern["observed_at_minsup"])}</text>',
        '<text x="28" y="96" font-family="sans-serif" font-size="12" fill="#43556b">Viền màu trên ảnh hỗ trợ:</text>']
    for index, word in enumerate(pattern["items_tuple"]):
        x = 190 + index * 112
        parts.append(f'<line x1="{x}" y1="91" x2="{x+18}" y2="91" stroke="{color_by_word[word]}" stroke-width="4"/>')
        parts.append(f'<text x="{x+24}" y="96" font-family="sans-serif" font-size="12" fill="#273444">mã {word}</text>')
    parts.extend([
        f'<line x1="920" y1="91" x2="938" y2="91" stroke="{contrast_color}" stroke-width="4"/>',
        '<text x="944" y="96" font-family="sans-serif" font-size="12" fill="#273444">vùng quan sát trên ảnh đối chứng</text>',
        '<text x="28" y="130" font-family="sans-serif" font-size="13" fill="#43556b">Tâm cụm (trung bình các patch 4×4 pixel)</text>'])
    thumb_columns = 8
    thumb_rows = math.ceil(len(pattern["items_tuple"]) / thumb_columns)
    centroid_top = 144
    for index, word in enumerate(pattern["items_tuple"]):
        x = 30 + (index % thumb_columns) * 145
        y = centroid_top + (index // thumb_columns) * 88
        add_svg_image(parts, b64_png(4, 4, centroid_image(centroids[word])), x, y, 64, 64, f"mã {word}")
    centroid_bottom = centroid_top + thumb_rows * 88
    exemplar_label_y = centroid_bottom + 18
    parts.append(f'<text x="28" y="{exemplar_label_y}" font-family="sans-serif" font-size="13" fill="#43556b">Patch thật gần mỗi tâm cụm nhất (mã ảnh và khoảng cách bình phương)</text>')
    exemplar_top = exemplar_label_y + 14
    for index, word in enumerate(pattern["items_tuple"]):
        x = 30 + (index % thumb_columns) * 145
        y = exemplar_top + (index // thumb_columns) * 88
        exemplar = exemplars[word][0]
        exemplar_meta = metadata[exemplar["image_id"]]
        source_id = f"{exemplar_meta['original_split']}:{exemplar_meta['original_index']}"
        add_svg_image(parts, b64_png(4, 4, exemplar["pixels"]), x, y, 64, 64)
        parts.append(f'<text x="{x+32}" y="{y+78}" text-anchor="middle" font-family="sans-serif" font-size="10">{html.escape(source_id)} · d²={exemplar["distance"]:.3f}</text>')
    exemplar_bottom = exemplar_top + thumb_rows * 88
    image_header_y = exemplar_bottom + 20
    parts.append(f'<text x="28" y="{image_header_y}" font-family="sans-serif" font-size="13" fill="#43556b">Ảnh chứa mẫu; khung màu đánh dấu patch được gán cho từng mã</text>')
    support_top = image_header_y + 14
    image_w, scale = 168, 6
    sample_rows = []
    for index, image_id in enumerate(sample_ids):
        x = 28 + index * 202
        meta = metadata[image_id]
        label = meta["class_label"]
        image_label = FASHION_CLASSES[label] if label is not None else "ảnh"
        add_svg_image(parts, image_png_data(meta, images), x, support_top, image_w, image_w,
                      f"{image_label} · {image_id}")
        by_word = witnesses[image_id][pattern["pattern_id"]]
        for word, coords in by_word.items():
            for patch_row, patch_col in coords:
                parts.append(f'<rect x="{x+(patch_col-1)*4*scale:.1f}" y="{support_top+(patch_row-1)*4*scale:.1f}" width="{4*scale}" height="{4*scale}" fill="none" stroke="{color_by_word[word]}" stroke-width="2.4"/>')
        sample_rows.append({"image_id": image_id, "class_label": label if label is not None else "",
                            "class_name": image_label if label is not None else "",
                            "witness_valid": True, "kind": "support"})
    if contrast_id is not None:
        x = 28 + len(sample_ids) * 202
        meta = metadata[contrast_id]
        add_svg_image(parts, image_png_data(meta, images), x, support_top, image_w, image_w,
                      f"đối chứng · {contrast_id}")
        for word, coords in witnesses[contrast_id][pattern["pattern_id"]].items():
            for patch_row, patch_col in coords:
                parts.append(f'<rect x="{x+(patch_col-1)*4*scale:.1f}" y="{support_top+(patch_row-1)*4*scale:.1f}" width="{4*scale}" height="{4*scale}" fill="none" stroke="{contrast_color}" stroke-width="2.4"/>')
        observed_words = set(witnesses[contrast_id][pattern["pattern_id"]])
        missing_words = sorted(set(pattern["items_tuple"]) - observed_words)
        contrast_note = "Thiếu mã " + ", ".join(map(str, missing_words))
        parts.append(f'<text x="{x+image_w/2}" y="{support_top+image_w+32}" text-anchor="middle" font-family="sans-serif" font-size="10" fill="#654276">{html.escape(contrast_note)}</text>')
        label = meta["class_label"]
        sample_rows.append({"image_id": contrast_id, "class_label": label if label is not None else "",
                            "class_name": FASHION_CLASSES[label] if label is not None else "", "witness_valid": True,
                            "kind": "contrast"})
    footer_y = support_top + image_w + 70
    class_note = (f"Số ảnh hỗ trợ theo lớp: {sorted(class_counts.items(), key=lambda item: (-item[1], item[0]))}"
                  if class_counts is not None else "Không có nhãn lớp; ảnh hỗ trợ được chọn theo mã ảnh.")
    parts.append(f'<text x="28" y="{footer_y}" font-family="sans-serif" font-size="13">{html.escape(class_note)}</text>')
    height = footer_y + 24
    parts[0] = f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">'
    parts[1] = f'<rect width="{width}" height="{height}" fill="#ffffff"/>'
    parts.append('</svg>')
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(parts), encoding="utf-8")
    return {"evidence_path": path.as_posix(), "sample_rows": sample_rows}


def write_heatmap(path: pathlib.Path, patterns: list[dict], class_counts: dict, class_totals: dict) -> None:
    width, height = 1160, max(340, 85 + len(patterns) * 34)
    left, top, cell_w, cell_h = 180, 70, 82, 28
    max_fraction = max((class_counts[row["pattern_id"]][label] / class_totals[label] for row in patterns for label in range(10)), default=1.0)
    max_fraction = max(max_fraction, 1e-12)
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#ffffff"/>',
        '<text x="580" y="32" text-anchor="middle" font-family="sans-serif" font-size="21" font-weight="700">P(X | class): representative patterns</text>',
        '<text x="580" y="52" text-anchor="middle" font-family="sans-serif" font-size="12">Conditional support fraction within each Fashion-MNIST class (verified label join)</text>']
    for label in range(10):
        parts.append(f'<text x="{left+label*cell_w+cell_w/2}" y="{top-10}" text-anchor="middle" font-family="sans-serif" font-size="10">{html.escape(FASHION_CLASSES[label])}</text>')
    for row_idx, pattern in enumerate(patterns):
        y = top + row_idx * cell_h
        items_text = ",".join(map(str, pattern["items_tuple"]))
        parts.append(f'<text x="{left-10}" y="{y+18}" text-anchor="end" font-family="sans-serif" font-size="11">{html.escape(pattern["pattern_id"])} {{{items_text}}}</text>')
        for label in range(10):
            value = class_counts[pattern["pattern_id"]][label] / class_totals[label]
            intensity = value / max_fraction
            r = round(245 - 150 * intensity)
            g = round(249 - 95 * intensity)
            b = round(250 - 50 * intensity)
            color = f"#{r:02x}{g:02x}{b:02x}"
            x = left + label * cell_w
            parts.append(f'<rect x="{x}" y="{y}" width="{cell_w-2}" height="{cell_h-2}" fill="{color}" stroke="#ffffff"/>')
            parts.append(f'<text x="{x+cell_w/2}" y="{y+17}" text-anchor="middle" font-family="sans-serif" font-size="10">{value:.1%}</text>')
    parts.append('</svg>')
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(parts), encoding="utf-8")


def preserve_annotations(path: pathlib.Path, patterns: list[dict], annotation_details: dict) -> None:
    existing = {}
    if path.is_file():
        for row in csv_rows(path):
            existing[row["pattern_id"]] = row
    rows = []
    current_ids = set()
    for pattern in patterns:
        pattern_id = pattern["pattern_id"]
        current_ids.add(pattern_id)
        prior = existing.get(pattern_id, {})
        details = annotation_details[pattern_id]
        rows.append({"pattern_id": pattern_id, "decodable": str(details["decodable"]).lower(),
            "witness_valid": str(details["witness_valid"]).lower(),
            "review_status": prior.get("review_status") or "PENDING_REVIEW",
            "visual_coherence": prior.get("visual_coherence") or "NA",
            "interpretation": prior.get("interpretation", ""),
            "limitations": prior.get("limitations") or "S0 records co-occurrence, not spatial geometry; machine-generated gallery requires human interpretation",
            "reviewer": prior.get("reviewer", ""), "reviewed_at": prior.get("reviewed_at", ""),
            "evidence_paths": details["evidence_paths"]})
    for pattern_id, row in existing.items():
        if pattern_id not in current_ids:
            rows.append(row)
    write_csv_atomic(path, ANNOTATION_FIELDS, rows)


def run_interpretation(output_dir: pathlib.Path, raw_dir: pathlib.Path) -> dict:
    root = find_repo_root(output_dir)
    tc7_path = output_dir / "transactions" / "tc7_manifest.toml"
    mining_manifest_path = output_dir / "mining" / "mining_manifest.toml"
    if not tc7_path.is_file() or not mining_manifest_path.is_file():
        raise FileNotFoundError("Interpretation requires both the TC7 and mining manifests")
    with open(tc7_path, "rb") as stream:
        tc7 = tomllib.load(stream)
    with open(mining_manifest_path, "rb") as stream:
        mining_manifest = tomllib.load(stream)
    if tc7.get("status") != "PASS" or tc7.get("configuration", {}).get("transaction_variant") != "S0":
        raise ValueError("TC7 manifest is not a passing B0/K32/seed123/S0 release")
    input_path = verified_artifact_path(root, tc7, "transactions")
    source_codebook = verified_artifact_path(root, tc7, "codebook")
    source_dir = source_codebook.parent
    source_digest = supervisor.sha256_file(input_path)
    if source_digest != tc7.get("transaction_sha256") or source_digest != mining_manifest.get("transaction_sha256"):
        raise ValueError("TC7 and mining manifests do not identify the same transaction JSONL")
    if mining_manifest.get("tc7_manifest_sha256") != supervisor.sha256_file(tc7_path):
        raise ValueError("Mining manifest does not identify the current TC7 manifest")
    config = {"configuration": "B0_K32_seed123_S0", "input_sha256": source_digest,
              "repo_root": str(root), "input_source_path": input_path.relative_to(root).as_posix()}
    patterns = load_selected(output_dir)
    selected_path = output_dir / "mining" / "selected_itemsets.csv"
    selected_hash = supervisor.sha256_file(selected_path)
    if mining_manifest.get("selected_itemsets_sha256") != selected_hash:
        raise ValueError("Mining manifest does not identify the current selected-itemset CSV")
    metadata_path = verified_artifact_path(root, tc7, "image_metadata")
    mapping_path = verified_artifact_path(root, tc7, "tid_image_mapping")
    patch_assignments = verified_artifact_path(root, tc7, "patch_assignments")
    for required_path in (metadata_path, mapping_path, patch_assignments):
        if required_path.parent != source_dir:
            raise ValueError("TC7 release artifacts must share one transactions directory")
    metadata, tid_mapping, _, _ = load_metadata(source_dir)
    centroids_path = verified_artifact_path(root, tc7, "centroids")
    centroids = load_centroids(centroids_path)
    assets = verify_raw_assets(source_dir, raw_dir)
    class_totals, labels_available, label_provenance = attach_verified_labels(metadata, assets)
    if labels_available:
        validate_class_count_reconciliation(class_totals, 70_000)
    evidence = collect_pattern_evidence(input_path, patterns, metadata, tid_mapping)
    sample_ids, contrast_ids, contrast_items = sample_supporters(patterns, evidence, metadata, seed=42, maximum=6)
    visual_asset_blockers = collect_visual_asset_blockers(centroids is not None, assets, patch_assignments)
    visual_assets_ready = not visual_asset_blockers
    images = assets["pixels"]
    if visual_assets_ready:
        witness_positions = selected_patch_witnesses(patch_assignments, patterns, sample_ids,
                                                       contrast_ids, contrast_items)
        exemplars = find_nearest_exemplars(patch_assignments, patterns, metadata, images, centroids)
    else:
        witness_positions, exemplars = {}, {}

    interpretation_dir = output_dir / "interpretation"
    gallery_dir = interpretation_dir / "pattern_gallery"
    gallery_dir.mkdir(parents=True, exist_ok=True)
    if not visual_assets_ready:
        for stale in gallery_dir.glob("*.svg"):
            stale.unlink()
    supporting_rows = []
    contrast_rows = []
    annotations = {}
    mapping_by_image = {row["image_id"]: row for row in tid_mapping.values()}
    for pattern in patterns:
        pattern_id = pattern["pattern_id"]
        class_counts = evidence["class_counts"][pattern_id] if labels_available else None
        if visual_assets_ready:
            card_path = gallery_dir / f"{pattern['selection_order']:02d}_{pattern_id}.svg"
            card = create_pattern_card(card_path, pattern, metadata, images, centroids, exemplars,
                                       sample_ids[pattern_id], contrast_ids[pattern_id], witness_positions,
                                       class_counts)
            for row in card["sample_rows"]:
                id_to_meta = metadata[row["image_id"]]
                item = {"pattern_id": pattern_id, "tid": mapping_by_image[row["image_id"]]["tid"], "image_id": row["image_id"],
                        "original_split": id_to_meta["original_split"], "original_index": id_to_meta["original_index"],
                        "class_label": row["class_label"], "class_name": row["class_name"],
                        "kind": row["kind"], "witness_valid": row["witness_valid"],
                        "evidence_path": supervisor.relative_to(root, card_path)}
                if row["kind"] == "support":
                    supporting_rows.append(item)
                else:
                    contrast_rows.append(item)
            annotations[pattern_id] = {"decodable": True, "witness_valid": True,
                                       "evidence_paths": supervisor.relative_to(root, card_path)}
        else:
            annotations[pattern_id] = {"decodable": False, "witness_valid": False,
                                       "evidence_paths": ""}

    supporting_fields = ["pattern_id", "tid", "image_id", "original_split", "original_index", "class_label",
                         "class_name", "kind", "witness_valid", "evidence_path"]
    write_csv_atomic(interpretation_dir / "supporting_images.csv", supporting_fields, supporting_rows)
    write_csv_atomic(interpretation_dir / "contrast_images.csv", supporting_fields, contrast_rows)

    class_rows = []
    class_heatmap = None
    if labels_available:
        for pattern in patterns:
            pattern_id = pattern["pattern_id"]
            global_probability = pattern["support_count"] / 70_000
            for label in range(10):
                support = evidence["class_counts"][pattern_id][label]
                conditional = support / class_totals[label]
                class_rows.append({"pattern_id": pattern_id, "class_label": label,
                    "class_name": FASHION_CLASSES[label], "class_total": class_totals[label],
                    "pattern_class_support": support, "support_fraction_global": global_probability,
                    "support_fraction_within_class": conditional,
                    "enrichment": conditional / global_probability if global_probability else "NA"})
        write_csv_atomic(interpretation_dir / "class_pattern_stats.csv",
            ["pattern_id", "class_label", "class_name", "class_total", "pattern_class_support",
             "support_fraction_global", "support_fraction_within_class", "enrichment"], class_rows)
        write_csv_atomic(interpretation_dir / "pattern_class_support.csv",
            ["pattern_id", "class_id", "N_c", "n_X_c", "p_X_given_c", "p_X", "enrichment"],
            [{"pattern_id": row["pattern_id"], "class_id": row["class_label"], "N_c": row["class_total"],
              "n_X_c": row["pattern_class_support"], "p_X_given_c": row["support_fraction_within_class"],
              "p_X": row["support_fraction_global"], "enrichment": row["enrichment"]} for row in class_rows])
        heatmap_svg = interpretation_dir / "class_conditional_support_heatmap.svg"
        write_heatmap(heatmap_svg, patterns, evidence["class_counts"], class_totals)
        class_heatmap = output_dir / "figures" / "pattern_class_heatmap.png"
        analysis.render_png(heatmap_svg, class_heatmap)
    else:
        for stale in (interpretation_dir / "class_pattern_stats.csv",
                      interpretation_dir / "pattern_class_support.csv",
                      interpretation_dir / "class_conditional_support_heatmap.svg",
                      output_dir / "figures" / "pattern_class_heatmap.png"):
            stale.unlink(missing_ok=True)

    class_perspectives = {}
    if labels_available and patterns and class_rows:
        def pattern_class_coverage(pattern_id: str) -> int:
            return sum(row["pattern_id"] == pattern_id and int(row["pattern_class_support"]) > 0
                       for row in class_rows)

        common = max(patterns, key=lambda row: (row["support_count"], -row["length"], row["items_tuple"]))
        cross_class_candidates = [row for row in patterns if row["length"] >= 2]
        cross_class = max(cross_class_candidates or patterns,
                          key=lambda row: (pattern_class_coverage(row["pattern_id"]), row["support_count"],
                                           -row["length"], row["items_tuple"]))
        enriched = max(class_rows, key=lambda row: (float(row["enrichment"]), -row["pattern_class_support"],
                                                     row["pattern_id"], row["class_label"]))
        class_perspectives = {
            "common": {"pattern_id": common["pattern_id"], "items": list(common["items_tuple"]),
                       "support_count": common["support_count"],
                       "class_coverage": pattern_class_coverage(common["pattern_id"])},
            "class_enriched": {"pattern_id": enriched["pattern_id"],
                "items": list(next(row["items_tuple"] for row in patterns if row["pattern_id"] == enriched["pattern_id"])),
                "class_name": enriched["class_name"], "pattern_class_support": enriched["pattern_class_support"],
                "class_total": enriched["class_total"],
                "support_fraction_within_class": enriched["support_fraction_within_class"],
                "support_fraction_global": enriched["support_fraction_global"],
                "enrichment": enriched["enrichment"]},
            "cross_class": {"pattern_id": cross_class["pattern_id"], "items": list(cross_class["items_tuple"]),
                "support_count": cross_class["support_count"],
                "class_coverage": pattern_class_coverage(cross_class["pattern_id"])}}

    retrieval = next((pattern for pattern in patterns if pattern["length"] >= 2), patterns[0])
    retrieval_id = retrieval["pattern_id"]
    retrieved_ids = sorted(evidence["supporters"][retrieval_id])
    if len(retrieved_ids) != retrieval["support_count"]:
        raise ValueError(f"Retrieval count differs from exact support for {retrieval_id}")
    retrieval_rows = []
    for image_id in retrieved_ids:
        image = metadata[image_id]
        map_row = mapping_by_image[image_id]
        retrieval_rows.append({"pattern_id": retrieval_id, "tid": map_row["tid"], "image_id": image_id,
            "original_split": image["original_split"], "original_index": image["original_index"],
            "class_label": image["class_label"] if image["class_label"] is not None else "",
            "class_name": FASHION_CLASSES[image["class_label"]] if image["class_label"] is not None else ""})
    write_csv_atomic(interpretation_dir / "image_retrieval.csv",
        ["pattern_id", "tid", "image_id", "original_split", "original_index", "class_label", "class_name"], retrieval_rows)
    retrieval_summary = {"pattern_id": retrieval_id, "items": list(retrieval["items_tuple"]),
        "support_count": retrieval["support_count"], "retrieved_count": len(retrieved_ids),
        "support_fraction": retrieval["support_count"] / 70_000,
        "retrieval_matches_support": len(retrieved_ids) == retrieval["support_count"],
        "sample_image_ids": sample_ids[retrieval_id], "contrast_image_id": contrast_ids[retrieval_id],
        "class_counts": ({str(label): count for label, count in evidence["class_counts"][retrieval_id].items()}
                         if labels_available else {}),
        "csv_path": "interpretation/image_retrieval.csv"}
    supervisor.atomic_toml(interpretation_dir / "retrieval_summary.toml", retrieval_summary)
    write_csv_atomic(interpretation_dir / "retrieval_examples.csv",
        ["pattern_id", "retrieved_count", "example_image_ids", "contrast_image_ids", "notes"],
        [{"pattern_id": retrieval_id, "retrieved_count": len(retrieved_ids),
          "example_image_ids": ";".join(map(str, sample_ids[retrieval_id])),
          "contrast_image_ids": str(contrast_ids[retrieval_id]) if contrast_ids[retrieval_id] is not None else "",
          "notes": (f"Exact retrieval count equals support {retrieval['support_count']}; labels used only post-hoc"
                    if labels_available else
                    f"Exact retrieval count equals support {retrieval['support_count']}; {label_provenance}")}])

    exemplar_rows = []
    for word, rows in sorted(exemplars.items()):
        for rank, row in enumerate(rows, 1):
            meta = metadata[row["image_id"]]
            exemplar_rows.append({"word_id": word, "rank": rank, "image_id": row["image_id"],
                "original_split": meta["original_split"], "original_index": meta["original_index"],
                "patch_row": row["patch_row"], "patch_col": row["patch_col"],
                "squared_distance_to_centroid": row["distance"]})
    write_csv_atomic(interpretation_dir / "visual_word_exemplars.csv",
        ["word_id", "rank", "image_id", "original_split", "original_index", "patch_row", "patch_col",
         "squared_distance_to_centroid"], exemplar_rows)

    html_path = gallery_dir / "index.html"
    html_path.parent.mkdir(parents=True, exist_ok=True)
    cards = ([f'<li><a href="{html.escape(path.name)}">Pattern {html.escape(pattern["pattern_id"])} '
              f'{{{",".join(map(str, pattern["items_tuple"]))}}} — support {pattern["support_count"]:,}</a></li>'
              for pattern in patterns for path in [gallery_dir / f"{pattern['selection_order']:02d}_{pattern['pattern_id']}.svg"]]
             if visual_assets_ready else [])
    gallery_status = ("Machine-generated evidence; human review pending."
                      if visual_assets_ready else
                      "Pattern cards are blocked because visual assets are missing: "
                      + ", ".join(visual_asset_blockers) + ". Retrieval and available class analysis remain usable.")
    html_path.write_text("<!doctype html><meta charset=\"utf-8\"><title>Fashion FIM gallery</title>"
        "<h1>Fashion-MNIST frequent visual itemsets</h1><p>" + html.escape(gallery_status) + "</p>"
        "<ul>" + "\n".join(cards) + "</ul>" +
        ("<p><a href=\"../class_conditional_support_heatmap.svg\">Class heatmap</a></p>" if labels_available else
         "<p>Class-conditioned analysis unavailable: BLOCKED_MISSING_LABELS.</p>"), encoding="utf-8")

    annotations_path = interpretation_dir / "pattern_annotations.csv"
    preserve_annotations(annotations_path, patterns, annotations)
    evidence_paths = [interpretation_dir / "supporting_images.csv", interpretation_dir / "contrast_images.csv",
                      interpretation_dir / "image_retrieval.csv", interpretation_dir / "retrieval_summary.toml",
                      interpretation_dir / "pattern_annotations.csv", interpretation_dir / "visual_interpretation.md"]
    evidence_artifacts = {path.name: {"path": path.relative_to(root).as_posix(),
                                      "sha256": supervisor.sha256_file(path)}
                          for path in evidence_paths if path.is_file()}
    manifest = {"schema_version": 1, "configuration": config["configuration"],
        "transaction_sha256": config["input_sha256"],
        "tc7_manifest_sha256": supervisor.sha256_file(tc7_path),
        "mining_manifest_sha256": supervisor.sha256_file(mining_manifest_path),
        "selected_itemsets_sha256": selected_hash,
        "codebook_path": tc7["artifacts"]["codebook"]["path"],
        "codebook_sha256": supervisor.sha256_file(source_codebook),
        "image_metadata_sha256": supervisor.sha256_file(metadata_path),
        "tid_image_mapping_sha256": supervisor.sha256_file(mapping_path),
        "patch_assignments_sha256": supervisor.sha256_file(patch_assignments),
        "codebook_centroid_layout": "16xK_descriptors_as_columns; 4x4 reshape column-major" if centroids is not None else "NA",
        "input_mapping_join": "PASS", "label_join": "PASS" if labels_available else "BLOCKED_MISSING_LABELS",
        "label_provenance": label_provenance,
        "visual_assets_status": "PASS" if visual_assets_ready else "BLOCKED_MISSING_ASSET",
        "visual_asset_blockers": visual_asset_blockers,
        "labelled_images": 70_000 if labels_available else 0,
        "class_count_per_label": [class_totals[label] for label in range(10)] if labels_available else [],
        "raw_asset_sha256": ";".join(f"{key}:{value}" for key, value in assets["assets"].items()),
        "representative_count": len(patterns),
        "witness_validation": "PASS" if visual_assets_ready else "BLOCKED_MISSING_ASSET",
        "retrieval_audit_status": "PASS" if retrieval_summary["retrieval_matches_support"] else "FAIL",
        "retrieval_count_matches_support": retrieval_summary["retrieval_matches_support"],
        "evidence_artifact_names": sorted(evidence_artifacts),
        "evidence_artifact_paths": [evidence_artifacts[name]["path"] for name in sorted(evidence_artifacts)],
        "evidence_artifact_sha256": [evidence_artifacts[name]["sha256"] for name in sorted(evidence_artifacts)],
        "sampling_seed": 42, "review_status": initial_review_status(),
        "visual_coherence": "NA", "updated_at": supervisor.utc_now()}
    supervisor.atomic_toml(interpretation_dir / "interpretation_manifest.toml", manifest)
    visual_report = ["# Visual interpretation and retrieval", "",
        (f"- Generated {len(patterns)} representative pattern cards. All cards have actual support and assignment-coordinate witnesses."
         if visual_assets_ready else
         f"- Pattern gallery is BLOCKED_MISSING_ASSET ({', '.join(visual_asset_blockers)}); mining, exact retrieval, and available class analysis remain available."),
        f"- Retrieval query `{retrieval_id}` = `{retrieval['items_tuple']}` returns {len(retrieved_ids):,} images; exact support is {retrieval['support_count']:,}.",
        "- S0 records image-level co-occurrence only. It does not preserve within-image location, word order, multiplicity, or fixed geometry.",
        ("- Machine-generated gallery evidence is pending human review; no coherence score has been assigned."
         if visual_assets_ready else "- Visual coherence is not rated because a verified gallery could not be rendered."), ""]
    if labels_available:
        visual_report.insert(2, "- Verified labels joined to 70,000 images; class totals: " + ", ".join(
            f"{FASHION_CLASSES[label]}={class_totals[label]}" for label in range(10)) + ".")
        if class_perspectives:
            visual_report.insert(5, "- Class enrichment is descriptive post-hoc evidence; frequent patterns are not assumed to be discriminative.")
            common = class_perspectives["common"]
            enriched = class_perspectives["class_enriched"]
            cross_class = class_perspectives["cross_class"]
            visual_report.insert(6, f"- Common across the dataset: `{common['items']}` occurs in {common['support_count']:,}/70,000 images "
                f"({common['support_count'] / 70_000:.2%}) and is present in {common['class_coverage']}/10 classes.")
            visual_report.insert(7, f"- Class-enriched example: `{enriched['items']}` in {enriched['class_name']} has "
                f"P(X|class)={enriched['support_fraction_within_class']:.2%}, P(X)={enriched['support_fraction_global']:.2%}, "
                f"enrichment={enriched['enrichment']:.2f}×.")
            visual_report.insert(8, f"- Cross-class example: `{cross_class['items']}` occurs in {cross_class['class_coverage']}/10 classes "
                f"(global support {cross_class['support_count']:,}/70,000). These are descriptive views of selected patterns.")
            if visual_assets_ready:
                visual_report.insert(9, "- Supporting-image examples use deterministic seed 42: one image from the class with highest within-class support, then a round-robin sample from other classes (up to six). A contrast is chosen from that same class when available, preferring the image that contains the most query words.")
    else:
        visual_report.insert(2, f"- Class analysis is {label_provenance}; image-level mining witnesses and retrieval are still available.")
    visual_report_path = interpretation_dir / "visual_interpretation.md"
    visual_report_path.write_text("\n".join(visual_report), encoding="utf-8")
    manifest["evidence_artifact_sha256"] = [
        supervisor.sha256_file(root / path) for path in manifest["evidence_artifact_paths"]]
    supervisor.atomic_toml(interpretation_dir / "interpretation_manifest.toml", manifest)
    interpretation_complete = visual_assets_ready and labels_available
    summary = {"status": "PASS" if interpretation_complete else "PARTIAL_MISSING_ASSET",
        "representative_count": len(patterns),
        "label_join": "PASS" if labels_available else "BLOCKED_MISSING_LABELS",
        "label_provenance": label_provenance, "class_totals": class_totals if labels_available else {},
        "class_perspectives": class_perspectives,
        "visual_assets_status": "PASS" if visual_assets_ready else "BLOCKED_MISSING_ASSET",
        "visual_asset_blockers": visual_asset_blockers,
        "witness_validation": "PASS" if visual_assets_ready else "BLOCKED_MISSING_ASSET",
        "retrieval": retrieval_summary, "annotations": str(annotations_path),
        "review_status": "PENDING_REVIEW", "visual_coherence": "NA",
        "gallery_paths": ([supervisor.relative_to(root, gallery_dir / f"{row['selection_order']:02d}_{row['pattern_id']}.svg") for row in patterns]
                          if visual_assets_ready else [])}
    if class_heatmap is not None:
        summary["class_heatmap_path"] = "figures/pattern_class_heatmap.png"
    (interpretation_dir / "interpretation_summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--raw-dir", required=True)
    args = parser.parse_args()
    run_interpretation(pathlib.Path(args.output_dir).resolve(), pathlib.Path(args.raw_dir).resolve())


if __name__ == "__main__":
    main()
