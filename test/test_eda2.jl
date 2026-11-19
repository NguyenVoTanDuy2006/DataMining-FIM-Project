using Test
using EclatFIM

const EDA2_TEST = EclatFIM.FashionMNISTEDA2

@testset "EDA2 input and mining invariants" begin
    @testset "JSONL transaction parsing" begin
        tid, image_id, items = EDA2_TEST._parse_transaction(
            "{\"tid\":7,\"image_id\":19,\"items\":[]}", "toy.jsonl", 7)
        @test (tid, image_id, items) == (7, 19, Int[])

        tid, image_id, items = EDA2_TEST._parse_transaction(
            "{\"tid\":8,\"image_id\":20,\"items\":[1,3,9]}", "toy.jsonl", 8)
        @test (tid, image_id, items) == (8, 20, [1, 3, 9])
        @test_throws ArgumentError EDA2_TEST._parse_transaction(
            "{\"tid\":8,\"image_id\":20,\"items\":[1,]}", "toy.jsonl", 8)
    end

    @testset "Jaccard and sampled-pair semantics" begin
        @test EDA2_TEST._jaccard(Int[], Int[]) == 1.0
        @test EDA2_TEST._jaccard(Int[], [1]) == 0.0
        @test EDA2_TEST._jaccard([1, 2], [1, 2]) == 1.0
        @test EDA2_TEST._jaccard([1], [2]) == 0.0
        @test EDA2_TEST._jaccard([1, 2], [2, 3]) == 1 / 3
        @test EDA2_TEST._auc([0.5], [0.5]) == 0.5
        @test EDA2_TEST._auc([0.8], [0.2]) == 1.0
    end

    @testset "Exact bounded Eclat support" begin
        transactions = [[1, 2], [1, 2, 3], [1, 3], [2], Int[]]
        cutoff = ceil(Int, 0.4 * length(transactions))
        @test cutoff == 2
        result = EclatFIM.mine(transactions, cutoff; max_length=3)
        @test result[(1,)] == 3
        @test result[(2,)] == 3
        @test result[(3,)] == 2
        @test result[(1, 2)] == 2
        @test result[(1, 3)] == 2
        @test !haskey(result, (2, 3))
        @test all(result[subset] >= result[itemset]
            for (itemset, _) in result if length(itemset) > 1
            for subset in [(itemset[1:end-1]...,), (itemset[2:end]...,)] if haskey(result, subset))
    end
end
