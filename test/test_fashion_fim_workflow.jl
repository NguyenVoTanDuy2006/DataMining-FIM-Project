include(joinpath(@__DIR__, "..", "src", "fashion_fim", "FashionFIMWorkflow.jl"))
using .FashionFIMWorkflow

@testset "Release Fashion-FIM transaction input" begin
    mktempdir() do dir
        path = joinpath(dir, "transactions.jsonl")
        write(path,
            "{\"tid\":1,\"image_id\":\"train:0\",\"items\":[1,4]}\n" *
            "{\"tid\":2,\"image_id\":\"test:0\",\"items\":[]}\n")
        loaded = load_transactions(path; expected_n=2, unique_mapping=true)
        @test loaded.transactions == [[1, 4], Int[]]
        @test loaded.tid == [1, 2]
        @test loaded.image_id == ["train:0", "test:0"]
        @test loaded.empty_count == 1
        @test loaded.singleton_support[1] == 1
        @test length(loaded.transactions) == 2

        write(path,
            "{\"tid\":1,\"image_id\":\"train:0\",\"items\":[]}\n" *
            "{\"tid\":2,\"image_id\":\"train:0\",\"items\":[]}\n")
        @test_throws ArgumentError load_transactions(path; unique_mapping=true)
        write(path, "{\"tid\":1,\"image_id\":\"train:60000\",\"items\":[]}\n")
        @test_throws ArgumentError load_transactions(path)
        write(path, "{\"tid\":1,\"image_id\":5,\"items\":[]}\n")
        legacy = load_transactions(path)
        @test legacy.image_id == [5]
    end
end
