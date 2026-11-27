#!/usr/bin/env python3
"""Check release and experiment notebook structure and execution contracts."""

from __future__ import annotations

import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[4]
RELEASE_DIR = REPO_ROOT / "notebook" / "UD2" / "release"
EXPERIMENT_DIR = REPO_ROOT / "notebook" / "UD2" / "experiments"
EXPECTED_NOTEBOOKS = (
    "01_dataset_validation.ipynb",
    "02_transaction_construction.ipynb",
    "03_frequent_itemset_mining.ipynb",
    "04_visual_interpretation.ipynb",
)
INTRO_TERMS = ("mục đích", "điều kiện chạy", "đầu vào", "đầu ra")
EXPECTED_EXPERIMENT_NOTEBOOKS = (
    "EDA2_FashionMNIST_Transaction_Evaluation.ipynb",
)
EXPERIMENT_INTRO_TERMS = ("độc lập", "julia", "cpu", ".tar.gz", "/content")
PYTHON_ORCHESTRATION_MARKERS = (
    "from google.colab",
    "import google.colab",
    "google.colab.files",
    "pycall",
    "pyexec",
    "pythoncall",
    "%%python",
    "%%bash",
    "!pip ",
    "!python ",
    "subprocess.run(",
)


def validate_notebook(path: Path, *, experiment: bool = False) -> list[str]:
    problems: list[str] = []
    try:
        notebook = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return [f"{path.name}: cannot read notebook JSON: {exc}"]

    cells = notebook.get("cells", [])
    if not cells or cells[0].get("cell_type") != "markdown":
        return [f"{path.name}: first cell must be the introductory Markdown cell"]

    intro = "\n".join(cells[0].get("source", [])).casefold()
    terms = EXPERIMENT_INTRO_TERMS if experiment else INTRO_TERMS
    for term in terms:
        if term not in intro:
            problems.append(f"{path.name}: introduction is missing '{term}'")

    if experiment:
        kernelspec = notebook.get("metadata", {}).get("kernelspec", {})
        language = str(kernelspec.get("language", "")).casefold()
        if language != "julia":
            problems.append(f"{path.name}: kernel must be Julia")

        code_sources = [
            "".join(cell.get("source", []))
            for cell in cells
            if cell.get("cell_type") == "code"
        ]
        combined_code = "\n".join(code_sources)
        if path.name == "EDA2_FashionMNIST_Transaction_Evaluation.ipynb":
            required_markers = (
                "FashionMNIST_T2_S0_B0_K$(k)_seed$(seed)",
                "[16, 32, 64, 128, 256]",
                "[42, 123, 2026]",
                "TC.run_tc4!(TC_STATE; after_fit! = save_fit_checkpoint!)",
                "restore_fit_checkpoint_bundle!",
                "TC6.run_variant!(TC6_CONTEXT, \"S1\")",
                "TC6.run_variant!(TC6_CONTEXT, \"S3\")",
                "TC6.run_variant!(TC6_CONTEXT, \"S6-B\")",
                "TC6.run_unit_checks!()",
                "FULL_S0_S1_S3_S6B",
                "s6b_neighbor_edge_summary.csv",
                "eligible_boundary_neighbor_pairs_processed",
                "wraparound_only_pairs_excluded_per_image",
                "EDA2.write_configuration_recommendations!(ctx)",
                "write_eda2_stage_bundle",
                "write_full_experiment_bundle",
                "fashion_full_experiment",
            )
            for marker in required_markers:
                if marker not in combined_code:
                    problems.append(f"{path.name}: unified experiment is missing '{marker}'")
            generation_markers = (
                'TC6.run_variant!(TC6_CONTEXT, "S1")',
                'TC6.run_variant!(TC6_CONTEXT, "S3")',
                'TC6.run_variant!(TC6_CONTEXT, "S6-B")',
            )
            analysis_position = combined_code.find("EDA2.load_context(")
            if analysis_position < 0 or any(combined_code.find(marker) > analysis_position for marker in generation_markers):
                problems.append(f"{path.name}: all four transaction variants must be generated before EDA2 starts")
            if 'TC6.run_variant!(part2_context, "S6-B")' in combined_code:
                problems.append(f"{path.name}: S6-B must not be deferred until archive packaging")
            markdown = "\n".join("".join(cell.get("source", [])) for cell in cells
                if cell.get("cell_type") == "markdown").casefold()
            for heading in ("phần 1", "phần 2"):
                if heading not in markdown:
                    problems.append(f"{path.name}: notebook must explain '{heading}'")
            if "fashion-tc6-handoff" in combined_code or "eda2_archives = filter" in combined_code:
                problems.append(f"{path.name}: legacy uploaded-input workflow remains in the unified notebook")

    for index, cell in enumerate(cells):
        if cell.get("cell_type") != "code":
            continue
        if index == 0 or cells[index - 1].get("cell_type") != "markdown":
            problems.append(
                f"{path.name}: code cell {index} is not immediately preceded by Markdown"
            )
        source = "".join(cell.get("source", [])).casefold()
        for marker in PYTHON_ORCHESTRATION_MARKERS:
            if marker in source:
                problems.append(
                    f"{path.name}: code cell {index} contains Python orchestration marker '{marker}'"
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

    actual_experiments = {path.name for path in EXPERIMENT_DIR.glob("*.ipynb")}
    expected_experiments = set(EXPECTED_EXPERIMENT_NOTEBOOKS)
    for missing in sorted(expected_experiments - actual_experiments):
        problems.append(f"missing experiment notebook: {missing}")
    for filename in EXPECTED_EXPERIMENT_NOTEBOOKS:
        path = EXPERIMENT_DIR / filename
        if path.is_file():
            problems.extend(validate_notebook(path, experiment=True))

    if problems:
        print("Release notebook validation FAILED:")
        for problem in problems:
            print(f"- {problem}")
        return 1

    print(
        f"PASS: {len(EXPECTED_NOTEBOOKS)} release and "
        f"{len(EXPECTED_EXPERIMENT_NOTEBOOKS)} experiment notebooks; "
        "introductions, Julia kernels, and cell notes are valid."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
