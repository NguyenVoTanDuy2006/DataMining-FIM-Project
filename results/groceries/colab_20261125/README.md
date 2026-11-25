# Groceries: selected real Colab evidence

Run session fim-groceries-20261125, source commit edf92f9, full9,835 transactions/169 products.
The12 parameter configurations and top10 rules match historical CSVs byte-for-byte;
all333 itemset/support pairs at1% match the independent SPMF reference.

`timings_raw.csv` contains140 samples across28 groups,5 repetitions after one
untimed warmup per group. `timing_summary.csv` gives median/min/max in seconds.
Mining uses four minsups; rule generation and fullpipeline use each of12 parameter
pairs. Fullpipeline includes CSV parsing/normalization/encoding/mining/rules, but
excludes Julia startup/JIT. The three phases were timed independently. No peakRSS.
Set backend, oneJulia/BLAS thread, Julia1.13.3; environment.txt records the dedicated
ColabCPU runtime. Do not mix these times with freshprocess benchmark results.

Historical result tables remain in results/groceries/. Fullsource/input/reference
and remote logs/driver/ZIP stay local at results/colab/groceries_20261125/.
The original verify.py there checked inputSHA, reference itemsets, byte-identical
outputs and all140 observations. This directory keeps only selected report evidence.

The captured environment.txt contains an erroneous summary line `itemsets_0.01=3`; do not use it as an itemset count. The downloaded itemset file and independent SPMF reference each contain333 entries, verified by exact set/support comparison. The report uses333. Original evidence was retained unchanged.

Selected text/summary copies use normalized LF line endings; original archived Colab evidence remains unchanged.
