import pathlib
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts" / "fashion_fim"))

import interpretation


class FashionFIMInterpretationTests(unittest.TestCase):
    def test_stable_image_ids_are_validated_and_decoded(self):
        self.assertEqual(interpretation.parse_stable_image_id("train:0"), ("train", 0))
        self.assertEqual(interpretation.parse_stable_image_id("test:9999"), ("test", 9999))
        for value in ("train:60000", "test:10000", "validation:0", "train:-1"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                interpretation.parse_stable_image_id(value)

    def test_selected_itemset_csv_contract(self):
        row = {"selection_order": "1", "backend": "set", "minsup_percent": "5",
               "items": "[1,4,19]", "support_count": "3500", "pattern_id": "P-abc"}
        pattern = interpretation.parse_selected_itemset_row(row)
        self.assertEqual(pattern["items_tuple"], (1, 4, 19))
        self.assertEqual(pattern["support_count"], 3500)
        self.assertEqual(pattern["backend"], "set")
        self.assertEqual(pattern["observed_at_minsup"], "5%")
        row["backend"] = "bitvector"
        with self.assertRaises(ValueError):
            interpretation.parse_selected_itemset_row(row)

    def test_selection_handoff_requires_three_or_four_rows(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            output_dir = pathlib.Path(temp_dir)
            mining_dir = output_dir / "mining"
            mining_dir.mkdir()
            path = mining_dir / "selected_itemsets.csv"
            fields = "selection_order,backend,minsup_percent,items,support_count,pattern_id\n"
            path.write_text(fields +
                "1,set,5,[1],4000,P-one\n2,set,5,[2],4000,P-two\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "exactly 3 or 4"):
                interpretation.load_selected(output_dir)
            path.write_text(fields +
                "1,set,5,[1],4000,P-one\n2,set,5,[2],4000,P-two\n"
                "3,set,5,[3],4000,P-three\n", encoding="utf-8")
            self.assertEqual(len(interpretation.load_selected(output_dir)), 3)

    def test_retrieval_and_class_totals_must_reconcile(self):
        interpretation.validate_retrieval_count(2, ["train:0", "test:0"])
        with self.assertRaises(ValueError):
            interpretation.validate_retrieval_count(3, ["train:0", "test:0"])
        interpretation.validate_class_count_reconciliation({i: 1 for i in range(10)}, 10)
        with self.assertRaises(ValueError):
            interpretation.validate_class_count_reconciliation({i: 0 for i in range(10)}, 1)

    def test_review_starts_pending(self):
        self.assertEqual(interpretation.initial_review_status(), "PENDING_REVIEW")


if __name__ == "__main__":
    unittest.main()
