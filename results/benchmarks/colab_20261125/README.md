# Selected real Colab benchmark evidence

Dedicated CPU runtime m-s-ass1c2-23zgvyg3cjwc1, source commit54049e1.
All groups completed with5 repetitions/configuration and exact output/support matches.
Original timestamps and hashes are retained. environment.md describes TableIV.

Each group contains summary.csv, runs.csv and metadata.md:
- processes:28 configurations,3 programs,420 freshprocess runtime samples.
- peak_ram:4 datasets,2Julia backends,40 freshprocess highwaterRSS samples.
- scalability:5nestedRetail subsets,2backends,50 mineafterwarmup samples.
- transaction_length:5syntheticlengths,2backends,50 mineafterwarmup samples.

Run `python scripts/plot_colab_report.py` from repo root to validate all560 samples
using existing benchmark validators and regenerate docs/report/figures/benchmarks/*.pdf.
Numbers in the report tables are rounded from summary.csv; timing CSVs use seconds,
RAM summary usesMiB and rawRSS usesbytes. Min/max are observed ranges, not CI.
Do not mix freshprocess time with hot mining time, allocations with RSS, or old
Windows/local smoke results with this Colab run. See each metadata.md for exactscope.

source_snapshot.json records exact source/input file hashes. Full original downloaded
ZIP, plotexports, reference outputs and runtime evidence are retained locally under
results/colab/benchmark_20261125/. Source/raw datasets are not duplicated here.
