#!/usr/bin/env python3
"""Build reproducible, report-ready Fashion-MNIST visual figures from a release run."""

from __future__ import annotations

import argparse
import csv
import hashlib
import html
import json
import pathlib
import subprocess
import tomllib


CLASS_NAMES = (
    "T-shirt/top", "Trouser", "Pullover", "Dress", "Coat",
    "Sandal", "Shirt", "Sneaker", "Bag", "Ankle boot",
)
FIGURE6_ITEMS = (4, 12, 24)
FIGURE9_STEM = "hinh_F7_heatmap_mau_theo_lop"


def find_repo_root(start: pathlib.Path) -> pathlib.Path:
    current = start.resolve()
    for candidate in (current, *current.parents):
        if (candidate / "Project.toml").is_file() and (candidate / "src" / "EclatFIM.jl").is_file():
            return candidate
    raise FileNotFoundError(f"Cannot find repository root above {start}")


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def declared_path(repo_root: pathlib.Path, manifest: dict, key: str) -> pathlib.Path:
    artifact = manifest["artifacts"][key]
    path = (repo_root / artifact["path"]).resolve()
    if not path.is_file() or sha256_file(path) != artifact["sha256"]:
        raise ValueError(f"Manifest artifact failed path/hash verification: {key}")
    return path


def read_csv(path: pathlib.Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as stream:
        return list(csv.DictReader(stream))


def svg_heatmap(rows: list[dict], path: pathlib.Path) -> None:
    width, height = 1600, 730
    left, top, cell_width, cell_height = 440, 130, 82, 44
    chart_width, chart_height = cell_width * 10, cell_height * 10
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#ffffff"/>',
        '<text x="800" y="42" text-anchor="middle" font-family="sans-serif" font-size="28" font-weight="700">Tỷ lệ ảnh trong từng lớp chứa mẫu (P(X|c))</text>',
        '<text x="800" y="76" text-anchor="middle" font-family="sans-serif" font-size="17" fill="#43556b">Mỗi hàng là mẫu có enrichment cao nhất trong lớp được ghi bên cạnh</text>',
        f'<text x="28" y="{top + chart_height/2}" transform="rotate(-90 28 {top + chart_height/2})" text-anchor="middle" font-family="sans-serif" font-size="17">Mẫu (lớp được chọn)</text>',
    ]
    for column, class_name in enumerate(CLASS_NAMES):
        x = left + column * cell_width + cell_width / 2
        y = top + chart_height + 18
        parts.append(f'<text x="{x:.1f}" y="{y}" transform="rotate(-38 {x:.1f} {y})" text-anchor="end" font-family="sans-serif" font-size="15" fill="#26384a">{html.escape(class_name)}</text>')

    def color_for(percent: float) -> str:
        ratio = max(0.0, min(1.0, percent / 40.0))
        start = (247, 251, 255)
        end = (8, 48, 107)
        rgb = tuple(round(a + ratio * (b - a)) for a, b in zip(start, end))
        return "#" + "".join(f"{component:02x}" for component in rgb)

    for row_index, row in enumerate(rows):
        y = top + row_index * cell_height
        items = "{" + ", ".join(str(item) for item in row["items"]) + "}"
        label = f"{items} ({row['selected_class_name']})"
        parts.append(f'<text x="{left-18}" y="{y+27}" text-anchor="end" font-family="sans-serif" font-size="17" fill="#202b36">{html.escape(label)}</text>')
        for column in range(10):
            percent = row["class_percentages"][column]
            x = left + column * cell_width
            fill = color_for(percent)
            text_color = "#ffffff" if percent >= 20 else "#18334d"
            parts.append(f'<rect x="{x}" y="{y}" width="{cell_width-2}" height="{cell_height-2}" fill="{fill}" stroke="#ffffff" stroke-width="1"/>')
            parts.append(f'<text x="{x+cell_width/2-1}" y="{y+27}" text-anchor="middle" font-family="sans-serif" font-size="16" fill="{text_color}">{percent:.1f}</text>')

    color_x, color_y, color_width = left + chart_width + 58, top, 24
    parts.append(f'<defs><linearGradient id="supportScale" x1="0" y1="1" x2="0" y2="0"><stop offset="0%" stop-color="{color_for(0)}"/><stop offset="100%" stop-color="{color_for(40)}"/></linearGradient></defs>')
    parts.append(f'<rect x="{color_x}" y="{color_y}" width="{color_width}" height="{chart_height}" fill="url(#supportScale)" stroke="#52606d"/>')
    for value in (0, 10, 20, 30, 40):
        y = color_y + chart_height * (1 - value / 40)
        parts.append(f'<line x1="{color_x+color_width}" y1="{y:.1f}" x2="{color_x+color_width+7}" y2="{y:.1f}" stroke="#52606d"/>')
        parts.append(f'<text x="{color_x+color_width+12}" y="{y+5:.1f}" font-family="sans-serif" font-size="14" fill="#26384a">{value}</text>')
    parts.append(f'<text x="{color_x+72}" y="{color_y+chart_height/2}" transform="rotate(-90 {color_x+72} {color_y+chart_height/2})" text-anchor="middle" font-family="sans-serif" font-size="16">Ảnh trong lớp (%)</text>')
    parts.append(f'<text x="{left+chart_width/2}" y="{height-14}" text-anchor="middle" font-family="sans-serif" font-size="17">Lớp Fashion-MNIST</text>')
    parts.append("</svg>")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(parts), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-root", type=pathlib.Path, required=True)
    parser.add_argument("--report-dir", type=pathlib.Path, required=True)
    args = parser.parse_args()

    repo_root = find_repo_root(args.run_root)
    run_root = args.run_root.resolve()
    report_dir = args.report_dir.resolve()
    tc7_path = run_root / "transactions" / "tc7_manifest.toml"
    mining_path = run_root / "mining" / "mining_manifest.toml"
    with tc7_path.open("rb") as stream:
        tc7 = tomllib.load(stream)
    with mining_path.open("rb") as stream:
        mining = tomllib.load(stream)
    if tc7.get("status") != "PASS" or mining.get("status") != "PASS":
        raise ValueError("Report figures require passing TC7 and mining manifests")
    if mining.get("tc7_manifest_sha256") != sha256_file(tc7_path):
        raise ValueError("Mining manifest does not identify the current TC7 manifest")
    if mining.get("transaction_sha256") != tc7.get("transaction_sha256"):
        raise ValueError("TC7 and mining manifests refer to different transaction data")

    transactions_path = declared_path(repo_root, tc7, "transactions")
    mapping_path = declared_path(repo_root, tc7, "tid_image_mapping")
    metadata_path = declared_path(repo_root, tc7, "image_metadata")
    catalog_path = (repo_root / mining["candidate_catalog_path"]).resolve()
    if sha256_file(catalog_path) != mining["candidate_catalog_sha256"]:
        raise ValueError("Candidate catalog failed the mining-manifest hash check")

    metadata = {}
    class_totals = [0] * 10
    for row in read_csv(metadata_path):
        image_id = row["image_id"]
        label = int(row["class_label"])
        if image_id in metadata or label not in range(10):
            raise ValueError(f"Invalid or duplicate image metadata row: {image_id}")
        metadata[image_id] = label
        class_totals[label] += 1
    if class_totals != [7000] * 10:
        raise ValueError(f"Expected 7,000 verified labels per class, found {class_totals}")

    mapping_by_tid = {}
    mapped_image_ids = set()
    for row in read_csv(mapping_path):
        tid, image_id = int(row["tid"]), row["image_id"]
        if tid in mapping_by_tid or image_id in mapped_image_ids:
            raise ValueError("Transaction/image mapping is not one-to-one")
        mapping_by_tid[tid] = image_id
        mapped_image_ids.add(image_id)

    class_masks = [0] * 10
    item_masks: dict[int, int] = {}
    image_ids = set()
    transaction_count = 0
    with transactions_path.open(encoding="utf-8") as stream:
        for expected_tid, line in enumerate(stream, start=1):
            record = json.loads(line)
            tid = int(record["tid"])
            image_id = record["image_id"]
            if tid != expected_tid or mapping_by_tid.get(tid) != image_id or image_id in image_ids:
                raise ValueError(f"Transaction mapping mismatch at tid={expected_tid}")
            label = metadata.get(image_id)
            if label is None:
                raise ValueError(f"No verified class label for {image_id}")
            bit = 1 << (tid - 1)
            class_masks[label] |= bit
            for item in record["items"]:
                item_masks[int(item)] = item_masks.get(int(item), 0) | bit
            image_ids.add(image_id)
            transaction_count += 1
    denominator = int(tc7["support_denominator"])
    if transaction_count != denominator or len(image_ids) != denominator or len(mapping_by_tid) != denominator:
        raise ValueError("Transaction, mapping, and support denominators do not reconcile")

    best_by_class = [None] * 10
    candidate_rows = read_csv(catalog_path)
    seen_patterns = set()
    for candidate in candidate_rows:
        items = tuple(json.loads(candidate["items"]))
        support = int(candidate["support_count"])
        if items in seen_patterns:
            raise ValueError(f"Duplicate itemset in candidate catalog: {items}")
        seen_patterns.add(items)
        if len(items) < 2:
            continue
        pattern_mask = item_masks.get(int(items[0]), 0)
        for item in items[1:]:
            pattern_mask &= item_masks.get(int(item), 0)
        if pattern_mask.bit_count() != support:
            raise ValueError(f"Candidate support differs from transactions for {items}")
        class_supports = [(pattern_mask & mask).bit_count() for mask in class_masks]
        if sum(class_supports) != support:
            raise ValueError(f"Class supports do not sum to global support for {items}")
        for label, class_support in enumerate(class_supports):
            if class_support / class_totals[label] < 0.10:
                continue
            enrichment = class_support * denominator / (class_totals[label] * support)
            candidate_result = {
                "items": items,
                "support_count": support,
                "selected_class": label,
                "selected_class_name": CLASS_NAMES[label],
                "enrichment": enrichment,
                "class_supports": class_supports,
                "class_percentages": [count / class_totals[index] * 100 for index, count in enumerate(class_supports)],
            }
            previous = best_by_class[label]
            if previous is None or (-enrichment, items) < (-previous["enrichment"], previous["items"]):
                best_by_class[label] = candidate_result
    if any(row is None for row in best_by_class):
        raise ValueError("At least one class has no itemset meeting the 10% support criterion")
    selected = best_by_class

    interpretation_dir = run_root / "interpretation"
    interpretation_dir.mkdir(parents=True, exist_ok=True)
    csv_path = interpretation_dir / "report_heatmap_data.csv"
    csv_fields = ["selected_class", "selected_class_name", "items", "support_count", "enrichment"]
    csv_fields += [f"class_{label}_support" for label in range(10)]
    csv_fields += [f"class_{label}_percent" for label in range(10)]
    with csv_path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=csv_fields)
        writer.writeheader()
        for row in selected:
            output_row = {
                "selected_class": row["selected_class"],
                "selected_class_name": row["selected_class_name"],
                "items": json.dumps(row["items"]),
                "support_count": row["support_count"],
                "enrichment": f"{row['enrichment']:.8f}",
            }
            output_row.update({f"class_{label}_support": row["class_supports"][label] for label in range(10)})
            output_row.update({f"class_{label}_percent": f"{row['class_percentages'][label]:.8f}" for label in range(10)})
            writer.writerow(output_row)

    report_figures = report_dir / "figures"
    report_figures.mkdir(parents=True, exist_ok=True)
    selected_path = run_root / "mining" / "selected_itemsets.csv"
    selected_items = [4, 12, 24]
    selection = next((row for row in read_csv(selected_path)
                      if json.loads(row["items"]) == selected_items), None)
    if selection is None:
        raise ValueError("Report Figure 6 pattern {4, 12, 24} is absent from the saved selection")
    card_path = interpretation_dir / "pattern_gallery" / f"{int(selection['selection_order']):02d}_{selection['pattern_id']}.svg"
    if not card_path.is_file():
        raise FileNotFoundError(f"Notebook 04 did not create the expected gallery card: {card_path}")
    subprocess.run(["rsvg-convert", "--format=png", "--width=2400", "--output",
                    str(report_figures / "pattern_4_12_24.png"), str(card_path)], check=True)

    svg_path = report_figures / f"{FIGURE9_STEM}.svg"
    pdf_path = report_figures / f"{FIGURE9_STEM}.pdf"
    svg_heatmap(selected, svg_path)
    subprocess.run(["rsvg-convert", "--format=pdf", "--output", str(pdf_path), str(svg_path)], check=True)
    chosen = "; ".join(f"{row['selected_class_name']} {row['items']} E={row['enrichment']:.2f}"
                        for row in selected)
    print(f"Verified {transaction_count:,} transactions, {len(candidate_rows):,} candidate itemsets and 10 class labels.")
    print(f"Figure 6: {report_figures / 'pattern_4_12_24.png'}")
    print(f"Figure 9: {pdf_path}")
    print(f"Figure 9 values: {csv_path}")
    print(f"Selected rows: {chosen}")


if __name__ == "__main__":
    main()
