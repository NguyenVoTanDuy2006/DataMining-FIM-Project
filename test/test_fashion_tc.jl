using Test

const TC = Main.EclatFIM.FashionTC

@testset "Fashion-MNIST TC helpers" begin
    repo_root = dirname(@__DIR__)
    smoke_config = TC.read_config(joinpath(repo_root,"configs","tc_smoke.toml"))
    full_config = TC.read_config(joinpath(repo_root,"configs","tc_full.toml"))
    @test smoke_config["run"]["mode"] == "smoke"
    @test full_config["run"]["mode"] == "full"
    @test occursin("tc", full_config["run"]["output_root"])

    labels = repeat(collect(0:9), inner=3)
    @test TC.balanced_smoke_indices(labels, 2, 42) == TC.balanced_smoke_indices(labels, 2, 42)
    @test length(TC.balanced_smoke_indices(labels, 2, 42)) == 20

    image = reshape(UInt8.(rem.(1:28*28, 256)), 28, 28, 1)
    patches, index = TC.extract_patches(image, [17])
    @test length(patches) == 49
    @test index[1] == (image_id=17, patch_id=1, patch_row=1, patch_col=1)
    @test index[end] == (image_id=17, patch_id=49, patch_row=7, patch_col=7)
    restored = zeros(UInt8, 28, 28)
    for (patch, row) in zip(patches, index)
        y = (row.patch_row - 1) * 4 + 1
        x = (row.patch_col - 1) * 4 + 1
        restored[y:y+3, x:x+3] .= patch
    end
    @test restored == image[:, :, 1]

    descriptors, mapping, retained = TC.make_descriptors(patches, index, 0; alpha=0)
    @test size(descriptors) == (16, 49)
    @test length(mapping) == length(retained) == 49
    @test all(0 .<= descriptors .<= 1)

    transactions = [[1, 2], [1, 3], Int[], [1, 2, 3]]
    patterns = Main.EclatFIM.mine(transactions, 2)
    @test length(transactions) == 4
    @test patterns[(1,)] == 3
    @test patterns[(2,)] == 2
    @test patterns[(1, 2)] == 2
    @test !haskey(patterns, (2, 3))

    mktempdir() do dir
        transaction_path = joinpath(dir, "transactions.txt")
        TC._write_transactions(transaction_path, [[1, 2], Int[], [2]])
        loaded = [isempty(strip(line)) ? Int[] : parse.(Int, split(strip(line)))
            for line in eachline(transaction_path)]
        @test loaded == [[1, 2], Int[], [2]]
        @test length(loaded) == 3
    end

    model_a = TC.fit_kmeans(Float32[0 0.1 0.9 1; 0 0.1 0.9 1]; k=2, seed=42, maxiter=20)
    model_b = TC.fit_kmeans(Float32[0 0.1 0.9 1; 0 0.1 0.9 1]; k=2, seed=42, maxiter=20)
    @test size(model_a.centroids) == (2, 2)
    @test model_a.centroids == model_b.centroids
    @test model_a.library == "Clustering.jl"
    @test model_a.initialization == ":kmpp"
end
