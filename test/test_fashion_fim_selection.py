import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts" / "fashion_fim"))

import selection


def candidate(items, support_count, minsup_percent=5):
    items = tuple(items)
    return {"items": items, "support_count": support_count,
            "minsup_percent": minsup_percent,
            "pattern_id": selection.itemset_id(items)}


class FashionFIMSelectionTests(unittest.TestCase):
    def test_selects_four_deterministically_from_support_and_length_grid(self):
        rows = [candidate((item,), support) for item, support in
                [(1, 70_000), (2, 50_000), (3, 20_000), (4, 5_000)]]
        selected, threshold, relaxed = selection.select_representatives(rows)
        reversed_selected, reversed_threshold, reversed_relaxed = selection.select_representatives(list(reversed(rows)))
        self.assertEqual(len(selected), 4)
        self.assertEqual([row["pattern_id"] for row in selected],
                         [row["pattern_id"] for row in reversed_selected])
        self.assertEqual((threshold, relaxed), (0.80, False))
        self.assertEqual((reversed_threshold, reversed_relaxed), (0.80, False))
        self.assertEqual(selected[0]["support_bucket"], "high")

    def test_short_sample_seeds_short_pair_and_long_itemset_groups(self):
        rows = [candidate((1,), 70_000), candidate((2,), 50_000),
                candidate((3, 4), 40_000), candidate((5, 6), 30_000),
                candidate((7, 8, 9), 10_000), candidate((10,), 5_000)]
        selected, _threshold, _relaxed = selection.select_representatives(rows)
        self.assertEqual(len(selected), 4)
        self.assertEqual([(row["length_bucket"], row["support_bucket"]) for row in selected[:3]],
                         [("1", "high"), ("2", "mid"), (">=3", "low")])

    def test_retries_once_at_jaccard_090_and_returns_four(self):
        rows = [candidate(tuple(range(1, 10)) + (extra,), support)
                for extra, support in [(10, 42_000), (11, 28_000), (12, 14_000), (13, 7_000)]]
        selected, threshold, relaxed = selection.select_representatives(rows)
        self.assertEqual(len(selected), 4)
        self.assertEqual((threshold, relaxed), (0.90, True))
        self.assertTrue(all(row["diversity_max_jaccard"] <= 0.90 for row in selected))

    def test_allows_three_when_fourth_fails_even_after_relaxation(self):
        rows = [candidate((item,), support) for item, support in
                [(1, 70_000), (2, 30_000), (3, 5_000)]]
        selected, threshold, relaxed = selection.select_representatives(rows)
        self.assertEqual(len(selected), 3)
        self.assertEqual((threshold, relaxed), (0.90, True))

    def test_catalog_deduplicates_thresholds_and_uses_highest_reference_minsup(self):
        rows = [candidate((1, 3), 42_000, 5), candidate((1, 3), 42_000, 20),
                candidate((2, 4), 14_000, 5)]
        catalog = selection.validate_catalog(rows)
        self.assertEqual(len(catalog), 2)
        self.assertEqual(catalog[0]["minsup_percent"], 20)

    def test_equal_support_counts_share_one_tertile(self):
        rows = [candidate((item,), support) for item, support in
                [(1, 70_000), (2, 40_000), (3, 40_000), (4, 5_000)]]
        buckets = selection.support_tertiles(selection.validate_catalog(rows))
        self.assertEqual(buckets[40_000], "mid")

    def test_rejects_inconsistent_duplicate_support_and_fewer_than_three(self):
        with self.assertRaisesRegex(ValueError, "Support differs"):
            selection.validate_catalog([candidate((1, 2), 20_000), candidate((1, 2), 21_000, 10)])
        with self.assertRaisesRegex(ValueError, "at least 3"):
            selection.select_representatives([candidate((1,), 50_000), candidate((2,), 10_000)])


if __name__ == "__main__":
    unittest.main()
