#!/usr/bin/env python3
"""Check the structure and introductory contract of the release notebooks."""

from __future__ import annotations

import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[4]
RELEASE_DIR = REPO_ROOT / "notebook" / "UD2" / "release"
EXPECTED_NOTEBOOKS = (
    "01_dataset_validation.ipynb",
    "02_transaction_construction.ipynb",
    "03_frequent_itemset_mining.ipynb",
    "04_visual_interpretation.ipynb",
)
INTRO_TERMS = ("mục đích", "điều kiện chạy", "đầu vào", "đầu ra")


def validate_notebook(path: Path) -> list[str]:
    problems: list[str] = []
    try:
        notebook = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return [f"{path.name}: cannot read notebook JSON: {exc}"]

    cells = notebook.get("cells", [])
    if not cells or cells[0].get("cell_type") != "markdown":
        return [f"{path.name}: first cell must be the introductory Markdown cell"]

    intro = "\n".join(cells[0].get("source", [])).casefold()
    for term in INTRO_TERMS:
        if term not in intro:
            problems.append(f"{path.name}: introduction is missing '{term}'")

    for index, cell in enumerate(cells):
        if cell.get("cell_type") != "code":
            continue
        if index == 0 or cells[index - 1].get("cell_type") != "markdown":
            problems.append(
                f"{path.name}: code cell {index} is not immediately preceded by Markdown"
            )
    return problems


def main() -> int:
    actual = {path.name for path in RELEASE_DIR.glob("*.ipynb")}
    expected = set(EXPECTED_NOTEBOOKS)
    problems: list[str] = []
    for missing in sorted(expected - actual):
        problems.append(f"missing release notebook: {missing}")
    for unexpected in sorted(actual - expected):
        problems.append(f"unexpected notebook in release directory: {unexpected}")

    for filename in EXPECTED_NOTEBOOKS:
        path = RELEASE_DIR / filename
        if path.is_file():
            problems.extend(validate_notebook(path))

    if problems:
        print("Release notebook validation FAILED:")
        for problem in problems:
            print(f"- {problem}")
        return 1

    print(f"PASS: {len(EXPECTED_NOTEBOOKS)} release notebooks; introductions and cell notes are valid.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
