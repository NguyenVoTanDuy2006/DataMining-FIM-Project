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

Both commands compare every itemset key and support count, not only the number
of results. The local verification run used the toy database, Chess, Mushroom,
Retail, and T10I4D100K. The downloaded Mushroom version contains 8,416
transactions, which differs from the approximate count in the assignment table.

| Database   | Transactions | Minsup | Frequent itemsets | Set   | BitVector |
| ---------- | -----------: | -----: | ----------------: | ----- | --------- |
| Toy        |            5 |   0.40 |                 7 | exact | exact     |
| Chess      |        3,196 |   0.80 |             8,227 | exact | exact     |
| Mushroom   |        8,416 |   0.80 |                17 | exact | exact     |
| Retail     |       88,162 |   0.10 |                 9 | exact | exact     |
| T10I4D100K |      100,000 |   0.10 |                 0 | exact | exact     |

## Optimization measurements

These are TV1 isolation measurements, not a replacement for TV2's benchmark
runner. Each case used 1,000 deterministic transactions, one warm-up call, and
five timed calls in one Julia process. `median_ms` excludes the warm-up. The
allocation column is `@allocated` for one post-warm-up call; RSS is the process
peak from `/usr/bin/time` and includes Julia startup, package loading, and JIT.
The environment was Julia 1.13.3, Java 21.0.13, and EclatFIM 0.1.0.

| Shape  | Items | Width | Minsup | Backend   | Itemsets | Median ms | Allocated bytes | Peak RSS KB |
| ------ | ----: | ----: | -----: | --------- | -------: | --------: | --------------: | ----------: |
| Dense  |    40 |    20 |   0.20 | Set       |      818 | 76.706860 |      44,597,664 |     320,656 |
| Dense  |    40 |    20 |   0.20 | BitVector |      818 |  1.090338 |       2,938,408 |     318,244 |
| Sparse |   500 |    10 |   0.01 | Set       |      499 | 39.990831 |      19,780,120 |     316,340 |
| Sparse |   500 |    10 |   0.01 | BitVector |      499 |  3.951669 |      28,233,400 |     318,196 |

On these samples BitVector is faster, but it allocates more on the sparse case.
The RSS values are close because process/JIT memory dominates this small
comparison. TV2 should repeat the comparison over the four full datasets with
the common benchmark settings before making a final performance claim.

## Original paper

M. J. Zaki, "Scalable Algorithms for Association Mining," _IEEE Transactions
on Knowledge and Data Engineering_, vol. 12, no. 3, pp. 372-390, 2000,
doi:10.1109/69.846291.
