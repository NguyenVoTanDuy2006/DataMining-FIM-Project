module OptimizedPruningTests

using Test
using Random
using EclatFIM

@testset "BitVector singleton pruning before allocation" begin
    transactions = [[1, 9, 9, 9], [1, 2], [1, 2], Int[]]
    original = deepcopy(transactions)
    @test EclatFIM.count_item_supports(transactions) == Dict(1 => 3, 2 => 2, 9 => 1)
    vertical = EclatFIM.build_vertical_bitvector(transactions, 2)
    @test Set(keys(vertical)) == Set([1, 2])
    @test vertical[1] == BitVector([1, 1, 1, 0])
    @test vertical[2] == BitVector([0, 1, 1, 0])
    @test !haskey(vertical, 9)
    @test transactions == original
    @test EclatFIM.build_vertical_bitvector(transactions, 3) ==
          Dict(1 => BitVector([1, 1, 1, 0]))
    @test isempty(EclatFIM.build_vertical_bitvector(transactions, 4))
    @test Set(keys(EclatFIM.build_vertical_bitvector(transactions))) == Set([1, 2, 9])
    @test isempty(EclatFIM.build_vertical_bitvector(Vector{Int}[], 1))
    @test_throws ArgumentError EclatFIM.build_vertical_bitvector([[1]], 0)
    # Invalid items cannot disappear silently when the support filter rejects them.
    @test_throws ArgumentError EclatFIM.build_vertical_bitvector([[1], [0]], 2)
    @test_throws ArgumentError mine([[1], [-1]], 1.0; backend = :bitvector)

    # Many rare IDs, including non-contiguous large IDs, must never get dense vectors.
    sparse = [[1; collect(1000 * tid .+ (1:100))] for tid in 1:20]
    sparse[1][end] = 10^9
    @test length(EclatFIM.count_item_supports(sparse)) == 2001
    pruned = EclatFIM.build_vertical_bitvector(sparse, 2)
    @test Set(keys(pruned)) == Set([1])
    @test length(pruned[1]) == 20
    @test count(pruned[1]) == 20
    @test mine(sparse, 0.1; backend = :bitvector) == Dict((1,) => 20)
end

function brute_force(transactions, minsup)
    vocabulary = sort(unique(vcat(Int[], transactions...)))
    expected = Dict{Tuple{Vararg{Int}}, Int}()
    isempty(transactions) && return expected
    threshold = ceil(Int, minsup * length(transactions))
    for mask in 1:((1 << length(vocabulary)) - 1)
        key = Tuple(vocabulary[i] for i in eachindex(vocabulary) if !iszero(mask & (1 << (i - 1))))
        support = count(t -> all(item -> item in t, key), transactions)
        support >= threshold && (expected[key] = support)
    end
    return expected
end

@testset "Pruned BitVector matches independent exhaustive oracle" begin
    rng = MersenneTwister(20261116)
    for _ in 1:40
        transactions = [rand(rng, 1:5, rand(rng, 0:8)) for _ in 1:rand(rng, 0:12)]
        original = deepcopy(transactions)
        for minsup in (0.2, 0.5, 1.0)
            expected = brute_force(transactions, minsup)
            @test mine(transactions, minsup; backend = :bitvector) == expected
            @test mine(transactions, minsup; backend = :set) == expected
        end
        @test transactions == original
    end
end

end # module
