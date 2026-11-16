module ScalabilityTests

using Test
using EclatFIM: read_spmf_transactions, read_spmf_itemsets
include("../scripts/benchmark_scalability.jl")
using .ScalabilityBenchmark: nested_indices, prepare_subsets, read_metrics, worker_command,
    run_command, parse_options

@testset "Scalability nested samples and settings" begin
    selections = nested_indices(100; seed = 20261116)
    @test [length(selections[p]) for p in (10, 25, 50, 75, 100)] == [10, 25, 50, 75, 100]
    @test selections == nested_indices(100; seed = 20261116)
    @test selections[10] != nested_indices(100; seed = 7)[10]
    @test selections[100] == collect(1:100)
    for (smaller, larger) in zip((10, 25, 50, 75), (25, 50, 75, 100))
        @test issubset(Set(selections[smaller]), Set(selections[larger]))
        @test issorted(selections[smaller])
        @test allunique(selections[smaller])
    end
    @test [length(nested_indices(88162)[p]) for p in (10, 25, 50, 75, 100)] ==
          [8816, 22040, 44081, 66121, 88162]
    @test_throws ArgumentError nested_indices(0)
    @test_throws ArgumentError nested_indices(1)
    @test_throws ArgumentError nested_indices(100; percentages = [10, 10])
    @test_throws ArgumentError nested_indices(100; percentages = [25, 10])
    @test_throws ArgumentError nested_indices(100; percentages = [0, 100])
    @test parse_options(String[])[1:4] == (5, 0.04, 20261116, 600.0)
    @test_throws ArgumentError parse_options(["--runs"])
    @test_throws ArgumentError parse_options(["--runs", "0"])
    @test_throws ArgumentError parse_options(["--minsup", "NaN"])
    @test_throws ArgumentError parse_options(["--seed", "-1"])
    @test_throws ArgumentError parse_options(["--timeout-seconds", "Inf"])
end

@testset "Scalability subset files and worker timing" begin
    mktempdir(@__DIR__; prefix = "scalability_") do directory
        full_input = joinpath(directory, "full.txt")
        write(full_input, repeat("1 2\n1 3\n1 2\n2 3\n", 5))
        subsets, total = prepare_subsets(full_input, joinpath(directory, "subsets"))
        @test total == 20
        @test [s.n_transactions for s in subsets] == [2, 5, 10, 15, 20]
        @test read(last(subsets).input_path, String) == read(full_input, String)
        original = read_spmf_transactions(full_input)
        for subset in subsets
            indices = parse.(Int, readlines(subset.indices_path))
            @test length(indices) == subset.n_transactions
            @test read_spmf_transactions(subset.input_path) == original[indices]
        end
        # Existing output must fail before any real-data work or overwrite.
        existing = joinpath(directory, "existing")
        mkpath(existing)
        write(joinpath(existing, "summary.csv"), "keep me")
        @test_throws ErrorException ScalabilityBenchmark.main(["--output-dir", existing])
        @test read(joinpath(existing, "summary.csv"), String) == "keep me"

        toy = joinpath(directory, "toy.txt")
        write(toy, "1 2 3\n1 3\n2 3\n1 2\n1 2 3\n")
        expected = Dict((1,) => 4, (2,) => 4, (3,) => 4,
            (1, 2) => 3, (1, 3) => 3, (2, 3) => 3, (1, 2, 3) => 2)
        for backend in (:set, :bitvector)
            output, metrics = joinpath(directory, "$backend.txt"), joinpath(directory, "$backend.csv")
            run_command(worker_command(toy, output, metrics, 0.4, backend),
                joinpath(directory, "$backend.log"), 60.0)
            measured = read_metrics(metrics)
            @test measured.n_transactions == 5
            @test measured.n_itemsets == 7
            @test measured.mining_seconds > 0
            @test measured.julia_threads == 1
            @test read_spmf_itemsets(output) == expected
        end
        path = joinpath(directory, "bad.csv")
        for row in ("0,7,0.1,1", "5,-1,0.1,1", "5,7,NaN,1", "5,7,0,1", "5,7,0.1,2")
            write(path, ScalabilityBenchmark.METRICS_HEADER * "\n" * row * "\n")
            @test_throws ErrorException read_metrics(path)
        end
    end
end

end # module
