using Test
using EclatFIM

@testset "Eclat Baseline" begin
    transactions = [
        [1, 2, 3],
        [1, 3],
        [2, 3],
        [1, 2],
        [1, 2, 3]
    ]

    expected = Dict(
        (1,) => 4,
        (2,) => 4,
        (3,) => 4,
        (1, 2) => 3,
        (1, 3) => 3,
        (2, 3) => 3,
        (1, 2, 3) => 2
    )

    @test mine(transactions, 0.4) == expected
    @test mine([reverse(t) for t in transactions], 0.4) == expected
    @test mine([[1, 1, 2], [1, 2]], 1.0) == Dict(
        (1,) => 2,
        (2,) => 2,
        (1, 2) => 2
    )
    @test isempty(mine([[1], [2]], 1.0))
    @test isempty(mine(Vector{Vector{Int}}(), 0.5))
    @test_throws ArgumentError mine([[1]], 0.0)
    @test_throws ArgumentError mine([[1]], 1.5)
    @test_throws ArgumentError mine([[0]], 0.5)
end

@testset "Eclat Backend Consistency" begin
    transactions = [
        [1, 2, 3],
        [1, 3],
        [2, 3],
        [1, 2],
        [1, 2, 3]
    ]

    expected = Dict(
        (1,) => 4,
        (2,) => 4,
        (3,) => 4,
        (1, 2) => 3,
        (1, 3) => 3,
        (2, 3) => 3,
        (1, 2, 3) => 2
    )

    for minsup in [0.2, 0.4, 0.6, 1.0]
        @test mine(transactions, minsup; backend=:set) ==
              mine(transactions, minsup; backend=:bitvector)
    end

    @test mine(transactions, 0.4; backend=:bitvector) == expected
    @test mine([[1, 1, 2], [1, 2]], 1.0; backend=:bitvector) == Dict(
        (1,) => 2,
        (2,) => 2,
        (1, 2) => 2
    )
    @test isempty(mine(Vector{Vector{Int}}(), 0.5; backend=:bitvector))
    @test_throws ArgumentError mine([[0]], 0.5; backend=:bitvector)
    @test_throws ArgumentError mine([[1]], 0.5; backend=:unknown)
end
