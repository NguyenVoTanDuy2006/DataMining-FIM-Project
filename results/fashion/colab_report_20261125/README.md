# Fashion-MNIST: selected evidence for the group report

Source: real Google Colab CPU run `fashion_655719818688`, source commit
`edf92f9`, using the portable TC1–TC7/demo runner with an authorized K-means
iteration-cap extension from 300 to 3,000. All 70,000 images were processed.
The library reported convergence at iteration 372, tolerance `1e-4`, with
a cost-increase warning at iteration 370; this does not prove stable assignments.
Full hashes and environment are in `runtime_observations.toml`.

- `comparison.csv`: six thresholds, median/min/max of five mine-only timings
  per backend after a full-database warm-up, exact parity and direct audit flags.
- `timings_raw.csv`: all 60 timing observations (seconds); no construction,
  input reading, export, support auditing or plotting in the timed region.
- `length_distribution.csv`: histogram extracted from each exported Set result;
  all six totals reconcile with `comparison.csv`.
- `patterns.csv`: four patterns selected by the demo, support and ten class counts.
  These are not the release selector output. Semantic review remains pending.
- `runtime_observations.toml`: construction/fit times are single observations.
  Sampled process RSS every five seconds is separate from the unmeasured exact
  peak RSS and must not be attributed to either mining backend.

The full local package is `results/colab/fashion_full_20261125/` from repo root.
It contains raw datasets, codebook, transactions, assignments, manifests, galleries,
the extended runner and log. It is intentionally excluded from Git. Selected report
figures are in `reports/figures/fashion/`; `colab_pattern_3.png` is the original
run's P3 gallery. No historical run images/counts were substituted.

Run `python scripts/plot_fashion_report.py` from repo root to validate the selected
tables and regenerate `reports/figures/fashion/colab_mining.pdf`.
Timing scope differs from the fresh-process benchmark in Chapter II.
