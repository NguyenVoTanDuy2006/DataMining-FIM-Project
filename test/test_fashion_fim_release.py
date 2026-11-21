import json
import pathlib
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts" / "fashion_fim"))

import audit_outputs
import supervisor


class FashionFIMReleaseTests(unittest.TestCase):
    def test_backends_and_thresholds(self):
        self.assertEqual(supervisor.MIN_COUNTS, (56_000, 42_000, 28_000, 14_000, 7_000, 3_500))
        self.assertEqual(supervisor.validate_backend("set"), "set")
        self.assertEqual(supervisor.validate_backend("bitvector"), "bitvector")
        self.assertEqual(supervisor.worker_backend_arguments("bitvector"), ["--backend", "bitvector"])
        with self.assertRaises(ValueError):
            supervisor.validate_backend("unknown")
        common = (3_500, "a" * 64, "b" * 64, "b1")
        self.assertNotEqual(supervisor.run_id_for(*common, backend="set"),
                            supervisor.run_id_for(*common, backend="bitvector"))

    def test_input_preflight_keeps_empty_rows_and_stable_ids(self):
        rows = [
            {"tid": 1, "image_id": "train:0", "items": [1, 3]},
            {"tid": 2, "image_id": "test:0", "items": []},
            {"tid": 3, "image_id": "test:1", "items": [3]},
        ]
        with tempfile.TemporaryDirectory() as temp:
            path = pathlib.Path(temp) / "transactions.jsonl"
            path.write_text("".join(json.dumps(row, separators=(",", ":")) + "\n" for row in rows), encoding="utf-8")
            result = supervisor.input_preflight(path, expected_n=3)
            self.assertEqual(result["record_count"], 3)
            self.assertEqual(result["empty_count"], 1)
            self.assertEqual(result["legacy_guardrail_status"], "NOT_APPLICABLE")

    def test_direct_support_is_recomputed_for_every_itemset(self):
        rows = [
            {"tid": 1, "image_id": "train:0", "items": [1, 2]},
            {"tid": 2, "image_id": "train:1", "items": [1]},
            {"tid": 3, "image_id": "test:0", "items": []},
        ]
        with tempfile.TemporaryDirectory() as temp:
            path = pathlib.Path(temp) / "transactions.jsonl"
            path.write_text("".join(json.dumps(row, separators=(",", ":")) + "\n" for row in rows), encoding="utf-8")
            masks, count = audit_outputs.vertical_item_masks(path, expected_n=3)
            self.assertEqual(count, 3)
            patterns = {(1,): 2, (2,): 1, (1, 2): 1}
            self.assertEqual(audit_outputs.direct_support_audit(patterns, masks)["status"], "PASS")
            patterns[(1, 2)] = 2
            failed = audit_outputs.direct_support_audit(patterns, masks)
            self.assertEqual(failed["status"], "FAIL")
            self.assertEqual(failed["mismatch_count"], 1)

    def test_exact_parity_checks_keys_and_support_and_requires_completed_runs(self):
        equal = audit_outputs.compare_itemset_maps(
            {(1,): 3, (1, 2): 2}, {(1,): 3, (1, 2): 2},
            set_complete=True, bitvector_complete=True)
        self.assertEqual(equal["status"], "PASS")
        mismatched = audit_outputs.compare_itemset_maps(
            {(1,): 3, (1, 2): 2}, {(1,): 4, (2,): 2},
            set_complete=True, bitvector_complete=True)
        self.assertEqual(mismatched["status"], "FAIL")
        self.assertEqual(mismatched["missing_count"], 1)
        self.assertEqual(mismatched["extra_count"], 1)
        self.assertEqual(mismatched["support_mismatch_count"], 1)
        incomplete = audit_outputs.compare_itemset_maps(
            {(1,): 3}, {(1,): 3}, set_complete=True, bitvector_complete=False)
        self.assertEqual(incomplete["status"], "NOT_COMPARABLE")


if __name__ == "__main__":
    unittest.main()
