using Test
using EclatFIM

function assert_backend_equality(transactions, minsups)
    for minsup in minsups
        @test mine(transactions, minsup; backend = :set) ==
              mine(transactions, minsup; backend = :bitvector)
    end
end

@testset "Eclat correctness and edge cases" begin
    transactions = [
        [1, 2, 3],
        [1, 3],
        [2, 3],
        [1, 2],
        [1, 2, 3],
    ]
    expected = Dict(
        (1,) => 4,
        (2,) => 4,
        (3,) => 4,
        (1, 2) => 3,
        (1, 3) => 3,
        (2, 3) => 3,
        (1, 2, 3) => 2,
    )

    @test mine(transactions, 0.4) == expected
    @test mine([reverse(transaction) for transaction in transactions], 0.4) == expected
    @test mine([[1], [1, 2]], 1.0) == Dict((1,) => 2)
    @test mine([[1, 1, 2], [1, 2]], 1.0) == Dict(
        (1,) => 2,
        (2,) => 2,
        (1, 2) => 2,
    )
    @test mine([[1, 2], [1, 2]], 0.5) == Dict(
        (1,) => 2,
        (2,) => 2,
        (1, 2) => 2,
    )
    @test isempty(mine([[1], [2]], 1.0))
    @test isempty(mine(Vector{Vector{Int}}(), 0.5))
    @test mine([[1], Int[]], 0.5) == Dict((1,) => 1)

    # ceil(minsup * transaction_count) makes these exact support boundaries.
    @test mine([[1], [1], [2], [2]], 0.5) == Dict((1,) => 2, (2,) => 2)
    @test mine([[1], [1], [2], [2]], 0.51) == Dict()

    for backend in (:set, :bitvector)
        @test_throws ArgumentError mine([[1]], 0.0; backend)
        @test_throws ArgumentError mine([[1]], 1.5; backend)
        @test_throws ArgumentError mine([[0]], 0.5; backend)
    end

    assert_backend_equality(transactions, [0.2, 0.4, 0.6, 1.0])
    @test_throws ArgumentError mine(transactions, 0.4; backend = :unknown)
end

@testset "SPMF I/O and exact comparison" begin
    input = " 3 1 2 2\n\n1   3\n"
    @test read_spmf_transactions(IOBuffer(input)) == [[3, 1, 2, 2], Int[], [1, 3]]
    @test_throws ArgumentError read_spmf_transactions(IOBuffer("1 nope\n"))
    @test_throws ArgumentError read_spmf_transactions(IOBuffer("1 0\n"))

    itemsets = Dict((1,) => 2, (1, 3) => 1, (2,) => 2)
    output = IOBuffer()
    write_spmf_itemsets(output, itemsets)
    @test String(take!(output)) == "1 #SUP: 2\n1 3 #SUP: 1\n2 #SUP: 2\n"

    parsed = read_spmf_itemsets(IOBuffer("1 #SUP: 2\n1 3 #SUP: 1\n2 #SUP: 2\n"))
    @test parsed == itemsets
    @test compare_itemsets(parsed, itemsets) ==
          (missing = [], extra = [], support_mismatches = [])
    @test compare_itemsets(Dict((1,) => 3), itemsets).support_mismatches ==
          [((1,), 3, 2)]
    @test read_spmf_itemsets(IOBuffer("2 1 #SUP: 1\n")) == Dict((1, 2) => 1)
    @test_throws ArgumentError read_spmf_itemsets(IOBuffer("1 1 #SUP: 1\n"))
    @test_throws ArgumentError read_spmf_itemsets(IOBuffer("1 #SUP: nope\n"))
    @test_throws ArgumentError read_spmf_itemsets(IOBuffer("1 #SUP: 0\n"))
end

# Giữ test thuật toán ở trên và bổ sung test phần ứng dụng của TV2.
include("test_groceries.jl")
include("test_association_rules.jl")
include("test_eclat_optimized.jl")
