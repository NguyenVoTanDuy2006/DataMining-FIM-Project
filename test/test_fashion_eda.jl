@testset "Fashion-MNIST class summaries and seeded samples" begin
    labels = repeat(collect(0:9), 2)
    images = Array{UInt8}(undef, 28, 28, length(labels))
    for index in eachindex(labels)
        images[:, :, index] .= UInt8(labels[index] + 1)
        images[1, 1, index] = 0x00
        images[2, 4, index] = 0xc8
    end
    dataset = (; images, labels)

    counts = fashion_class_counts(dataset)
    @test length(counts) == 10
    @test [row.label for row in counts] == collect(0:9)
    @test all(row -> row.images == 2, counts)
    @test all(row -> row.class_name == FASHION_CLASSES[row.label + 1], counts)
    @test all(row -> row.black_pixel_fraction ≈ 1 / 784, counts)

    first = select_fashion_samples(labels; seed=42)
    second = select_fashion_samples(labels; seed=42)
    @test first == second
    @test length(unique(first)) == 10
    @test [labels[index] for index in first] == collect(0:9)
    @test_throws ArgumentError select_fashion_samples(labels; samples_per_class=3)
    @test_throws ArgumentError select_fashion_samples(labels; seed=-1)

    mktempdir() do dir
        result = save_fashion_eda(dir, dataset, dataset; seed=42)
        @test result.sample_indices == first
        @test length(result.train_counts) == length(result.test_counts) == 10
        @test occursin("x=\"48\" y=\"110\" width=\"6\" height=\"6\" fill=\"rgb(200,200,200)\"", result.image_svg)
        @test all(occursin("$label · $(FASHION_CLASSES[label + 1])", result.image_svg) for label in 0:9)
        @test read(joinpath(dir, "class_samples.svg"), String) == result.image_svg
        @test length(readlines(joinpath(dir, "class_counts.csv"))) == 21
        @test length(readlines(joinpath(dir, "eda_sample_indices.csv"))) == 11
        @test occursin("seed = 42", read(joinpath(dir, "eda_metadata.toml"), String))
        @test occursin("Zero-valued train pixels", read(joinpath(dir, "eda_summary.md"), String))
    end
end
