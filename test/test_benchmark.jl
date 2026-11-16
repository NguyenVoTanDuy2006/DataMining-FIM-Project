module BenchmarkCorrectnessTests

using Test
using EclatFIM: mine, read_spmf_transactions, read_spmf_itemsets, compare_itemsets

@testset "Correctness SPMF tren 5 CSDL" begin
    root = normpath(joinpath(@__DIR__, ".."))
    benchmark_data = joinpath(root, "data", "benchmark", "processed", "processes")
    benchmark_references = joinpath(root, "results", "benchmarks", "peak_ram", "spmf")
    cases = [
        (name = "Groceries", input = joinpath(root, "data", "processed", "groceries_spmf.txt"),
            reference = joinpath(root, "results", "groceries", "groceries_spmf_0.01.txt"),
            minsup = 0.01, n_transactions = 9835, n_itemsets = 333),
        (name = "Chess", input = joinpath(benchmark_data, "chess_spmf.txt"),
            reference = joinpath(benchmark_references, "chess_0.875.txt"),
            minsup = 0.875, n_transactions = 3196, n_itemsets = 1386),
        (name = "Mushroom", input = joinpath(benchmark_data, "mushroom_spmf.txt"),
            reference = joinpath(benchmark_references, "mushroom_0.7.txt"),
            minsup = 0.7, n_transactions = 8124, n_itemsets = 31),
        (name = "Retail", input = joinpath(benchmark_data, "retail_spmf.txt"),
            reference = joinpath(benchmark_references, "retail_0.04.txt"),
            minsup = 0.04, n_transactions = 88162, n_itemsets = 18),
        (name = "T10I4D100K", input = joinpath(benchmark_data, "T10I4D100K_spmf.txt"),
            reference = joinpath(benchmark_references, "T10I4D100K_0.015.txt"),
            minsup = 0.015, n_transactions = 100000, n_itemsets = 237),
    ]
    @test length(cases) == 5
    @test Set(c.name for c in cases) == Set(["Groceries", "Chess", "Mushroom", "Retail", "T10I4D100K"])

    for c in cases
        name = c.name
        @testset "$name" begin
            isfile(c.input) || error("Thiếu CSDL đầy đủ: $(c.input). Chuẩn bị dữ liệu trong data/ trước khi chạy test.")
            isfile(c.reference) || error("Thiếu đáp án SPMF: $(c.reference)")
            transactions = read_spmf_transactions(c.input)
            # SPMF may add @FILETYPE/@SOURCE metadata ahead of its itemset output.
            payload = filter(line -> !startswith(strip(line), "@"), readlines(c.reference))
            expected = read_spmf_itemsets(IOBuffer(join(payload, "\n")))
            @test length(transactions) == c.n_transactions
            @test length(expected) == c.n_itemsets > 0
            for backend in (:set, :bitvector)
                actual = mine(transactions, c.minsup; backend)
                difference = compare_itemsets(actual, expected)
                matched = count(pair -> get(actual, first(pair), -1) == last(pair), expected)
                println("$name / $backend: matched=$matched/$(length(expected)); ",
                    "missing=$(length(difference.missing)); extra=$(length(difference.extra)); ",
                    "support_mismatches=$(length(difference.support_mismatches))")
                # Whole-Dict equality catches missing/extra keys AND incorrect support counts.
                @test actual == expected
            end
        end
    end
end

end # module
