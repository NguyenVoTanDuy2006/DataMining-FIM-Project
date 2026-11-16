from copy import deepcopy
from pathlib import Path
import runpy
import unittest

module = runpy.run_path(str(Path(__file__).resolve().parents[1] / "scripts/plot_scalability.py"))
validate = module["validate"]


class ScalabilityEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.summary, self.runs = [], []
        for percent in module["PERCENTAGES"]:
            size = 1000 * percent // 100
            for backend in ("set", "bitvector"):
                elapsed = size / (10000 if backend == "set" else 20000)
                shared = dict(dataset="retail", percent=str(percent), n_total="1000",
                    n_transactions=str(size), minsup="0.04", min_count=str(size * 4 // 100),
                    backend=backend, measurement=module["MEASUREMENT"], n_itemsets="5",
                    exact_match="true", spmf_match="true")
                self.summary.append(dict(shared, n_runs="2", median_seconds=str(1.1 * elapsed),
                    min_seconds=str(elapsed), max_seconds=str(1.2 * elapsed),
                    transactions_per_second=str(size / (1.1 * elapsed))))
                for run_id, value in ((1, elapsed), (2, 1.2 * elapsed)):
                    first = "set" if run_id % 2 else "bitvector"
                    self.runs.append(dict(shared, run_id=str(run_id), order_in_pair=str(1 if backend == first else 2),
                        mining_seconds=str(value), julia_threads="1", status="ok"))

    def test_complete_evidence_and_linear_fit(self):
        validate(self.summary, self.runs)
        rows = module["backend_rows"](self.summary, "set")
        slope, intercept, r_squared = module["linear_fit"](rows)
        self.assertAlmostEqual(slope, 0.00011)
        self.assertAlmostEqual(intercept, 0)
        self.assertAlmostEqual(r_squared, 1)

    def test_summary_corruption(self):
        for field, value in (("minsup", "0.02"), ("min_count", "999"), ("n_transactions", "101"),
                             ("median_seconds", "NaN"), ("max_seconds", "1"),
                             ("transactions_per_second", "1"), ("n_itemsets", "6")):
            with self.subTest(field=field):
                data = deepcopy(self.summary)
                data[0][field] = value
                with self.assertRaises(ValueError):
                    validate(data, self.runs)

    def test_raw_sample_corruption(self):
        for field, value in (("status", "failed"), ("spmf_match", "false"), ("exact_match", "false"),
                             ("mining_seconds", "0"), ("mining_seconds", "Inf"), ("julia_threads", "2"),
                             ("order_in_pair", "2"), ("run_id", "2"), ("n_itemsets", "4")):
            with self.subTest(field=field, value=value):
                data = deepcopy(self.runs)
                data[0][field] = value
                with self.assertRaises(ValueError):
                    validate(self.summary, data)

    def test_missing_or_duplicate_configurations(self):
        for summary, runs in ((self.summary[:-1], self.runs), (self.summary, self.runs[:-1]),
                              (self.summary, self.runs * 2), (self.summary[:-1] + self.summary[:1], self.runs)):
            with self.assertRaises(ValueError):
                validate(summary, runs)


if __name__ == "__main__":
    unittest.main()
