# Eclat Frequent Itemset Mining

Julia project for a from-scratch Eclat implementation, SPMF comparison, four
benchmarks, and two applications. See [the project plan](docs/plan.md) and
[assignment](docs/itemset.md) for the full team scope.

**Team:** Trung (TV1, algorithm), Khang (TV2, benchmarks and Groceries), Duy
(TV3, Fashion-MNIST and demo).

## Julia setup

Install Julia 1.9 or newer, then run:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. -e 'using EclatFIM'
```

The core API is:

```julia
using EclatFIM
transactions = [[1, 2, 3], [1, 2], [2, 3]]
mine(transactions, 0.5; backend = :bitvector)
```

`minsup` is a relative threshold in `(0, 1]` and is converted with
`ceil(minsup * transaction_count)`. The result maps sorted itemset tuples to
support counts. The `:set` and `:bitvector` backends have the same output.

## Tests

```sh
julia --project=. test/runtests.jl
```

The tests cover itemsets, empty and invalid input, duplicate transactions and
items, ordering, support boundaries, SPMF I/O, and exact backend equality.

## CLI

The minimal CLI reads and writes SPMF-compatible text files:

```sh
julia --project=. scripts/eclat_cli.jl \
    --input data/toy/example.txt \
    --minsup 0.4 \
    --backend bitvector \
    --output results/output.txt
```

Each output line has the form `1 2 3 #SUP: 4`. Use `--backend set` for the
baseline implementation.

## SPMF correctness verification

Keep external datasets and the SPMF jar outside this repository. For each
dataset, first generate an SPMF reference output and then compare every itemset
key and support count with both backends:

```sh
java -jar /path/to/spmf2.64.jar run Eclat INPUT SPMF_OUTPUT MINSUP
julia --project=. scripts/verify_spmf.jl INPUT SPMF_OUTPUT MINSUP set
julia --project=. scripts/verify_spmf.jl INPUT SPMF_OUTPUT MINSUP bitvector
```

The TV1 verification set is the toy database, Chess, Mushroom, Retail, and
T10I4D100K. The downloaded reference versions and chosen thresholds are recorded
in [the TV1 algorithm note](docs/TV1_algorithm.md); large datasets are not
committed.

## Current implementation status

- TV1 core Eclat, Set and BitVector backends, SPMF I/O, CLI, tests, exact-match
  verifier, and optimization note are implemented.
- TV1 exact verification passed on all five listed databases with both backends
  in the recorded runs.
- TV2 owns the full benchmark runner and application work; TV3 owns the visual
  mining and demo work. Their scaffold status is unchanged.
