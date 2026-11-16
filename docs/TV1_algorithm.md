TV1: Eclat Algorithm and Optimization

This note is the technical content for TV1's algorithm section. The Julia API
is `mine(transactions, minsup; backend=:set|:bitvector)` and returns a
`Dict{Tuple{Vararg{Int}},Int}`. Support values are transaction counts.

## Vertical representation

Eclat stores one transaction-ID set (TID-set) per item. For transaction IDs
starting at 1:

```text
T1 = {1, 2, 3}
T2 = {1, 3}
T3 = {2, 3}
T4 = {1, 2}

TID(1) = {1, 2, 4}
TID(2) = {1, 3, 4}
TID(3) = {1, 2, 3}
TID(1, 2) = TID(1) intersect TID(2) = {1, 4}
```

The support of an itemset is the size of its TID-set. Duplicate transactions
keep separate transaction IDs. Duplicate items inside one transaction only set
the same TID again.

## DFS and equivalence classes

Candidates are sorted by item ID. A prefix and the candidates after its last
item form an equivalence class. DFS extends one candidate at a time, so an
itemset is generated once and its extension candidates are already ordered.

```text
Eclat(prefix, candidates, min_count):
    for each (item, tids) in candidates:
        current = prefix followed by item
        emit current with support |tids|
        next = empty candidate list
        for each later (other_item, other_tids):
            common = tids intersect other_tids
            if |common| >= min_count:
                append (other_item, common) to next
        if next is not empty:
            Eclat(current, next, min_count)
```

The anti-monotonicity rule provides pruning: if an itemset is infrequent, no
superset can be frequent. Therefore an intersection below `min_count` is not
stored as a child and its whole subtree is skipped.

## Implementations

The baseline in `src/algorithm/EclatBaseline.jl` uses `Set{Int}` TID-sets and
set intersection. The optimized implementation in
`src/algorithm/EclatOptimized.jl` stores one `BitVector` per item, intersects
with elementwise `.&`, and counts set bits. Both implementations use the same
DFS order, support threshold, and output contract. No SPMF implementation code
is copied.

Let `N` be the number of transactions, `M` the number of distinct items, and
`F` the number of frequent itemsets emitted. The output can be exponential in
`M`, so the total mining cost is output-sensitive. Building baseline TID-sets
uses `O(sum_i |TID(i)|)` storage, at most `O(NM)`. BitVectors use `O(MN)` bits
for the vertical representation. A Set intersection is proportional to the
smaller operand (on average), while a BitVector intersection scans roughly
`N / word_size` machine words. The BitVector representation can therefore
reduce dense intersection overhead, but it can waste memory when many items are
rare.

### Singleton pruning before BitVector allocation

The BitVector miner now counts transaction support in a first pass, retaining
the last transaction ID seen for each item so duplicates within a basket count
once. Only items reaching `min_count` receive a length-`N` BitVector. A second
pass fills those vectors before the existing candidate sorting and DFS.
Duplicate transactions still receive different TIDs. Input validation covers
all observed items, including those removed by the support filter.

This uses `O(M)` counting state and `O(F1 * N)` bits for the initial vertical
representation, where `F1` is the number of frequent singletons, rather than
`O(M * N)` bits. It adds a counting pass; runtime must still be measured rather
than assumed to improve. Intersections still allocate fresh BitVectors.
The public `mine` API and result contract are unchanged.

On the TV2 Retail input at minsup 4%, only 7 of 16,470 observed items survive.
The full-dataset peak RSS measurements for Set and the pruned BitVector miner
are in [the memory report](report_benchmark.md#peak-ram).

## Correctness verification

`src/utils/SPMFIO.jl` reads transaction files, writes
`item #SUP: count` output, parses SPMF output, and reports missing, extra, and
support-mismatched itemsets. The parser sorts each parsed SPMF itemset because
SPMF does not guarantee output order; duplicate items and malformed counts are
rejected.

The verification command is:

```sh
java -jar /path/to/spmf2.64.jar run Eclat INPUT SPMF_OUTPUT MINSUP
julia --project=. scripts/verify_spmf.jl INPUT SPMF_OUTPUT MINSUP set
julia --project=. scripts/verify_spmf.jl INPUT SPMF_OUTPUT MINSUP bitvector
```

The automated suite compares every itemset key and support count, not only the
number of results, for the full Groceries, Chess, Mushroom, Retail and T10I4D100K
databases in `data/`. It reads the normalized SPMF inputs and saved SPMF reference
outputs; it does not sample transactions or call Java during the test run.
The current Mushroom input has 8,124 transactions.

| Database   | Transactions | Minsup | Frequent itemsets | Set   | BitVector |
| ---------- | -----------: | -----: | ----------------: | ----- | --------- |
| Groceries  |        9,835 |   0.01 |               333 | exact | exact     |
| Chess      |        3,196 |  0.875 |             1,386 | exact | exact     |
| Mushroom   |        8,124 |   0.70 |                31 | exact | exact     |
| Retail     |       88,162 |   0.04 |                18 | exact | exact     |
| T10I4D100K |      100,000 |  0.015 |               237 | exact | exact     |

## Optimization measurements

Use the current four-dataset results in
[the benchmark report](report_benchmark.md#peak-ram).
Each backend runs in five independent single-threaded Julia processes at the
middle minsup of the existing pilot grid. Peak RSS is recorded with
`Sys.maxrss()` after mining and before output serialization; it includes Julia
startup, JIT, toy warm-up and input loading. The report contains median/min/max,
raw samples, exact SPMF checks and source/data checksums. These RAM measurements
do not establish runtime improvements.

The [fresh-process runtime experiment](report_benchmark.md#runtime) compares
Set, BitVector and SPMF on all four datasets and seven minsup thresholds each.
It includes startup/JIT and I/O for all three programs; it does not isolate
the mining kernel or promise a speedup for every threshold.

The Retail scalability experiment measures post-warm-up `mine` wall-clock time
for both backends on nested 10%, 25%, 50%, 75% and 100% subsets, holding relative
minsup at 4%. See [the scalability report](report_benchmark.md#scalability)
for the curves and their limits; these timings exclude startup, input loading
and output writing and must not be mixed with the whole-process Julia/SPMF timings.

The [transaction-length experiment](report_benchmark.md#transaction-length)
holds N=5,000, M=64 and minsup=5% fixed while extending each synthetic basket to
4, 8, 12, 16 and 20 distinct items. It reuses the same per-TID permutation across
lengths, so supports cannot decrease. The experiment measures post-warm-up mine
time and frequent-itemset counts for both backends, verified against SPMF. Longer
transactions change TID density, candidate survival and output size together;
the report does not attribute all runtime changes to one isolated mechanism.

## Original paper

M. J. Zaki, "Scalable Algorithms for Association Mining," _IEEE Transactions
on Knowledge and Data Engineering_, vol. 12, no. 3, pp. 372-390, 2000,
doi:10.1109/69.846291.
