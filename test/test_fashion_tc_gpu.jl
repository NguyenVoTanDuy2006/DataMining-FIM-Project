using Test

const TC_GPU_TEST = Main.EclatFIM.FashionTC
const CUDA_GPU_TEST_AVAILABLE = Base.find_package("CUDA") !== nothing

if CUDA_GPU_TEST_AVAILABLE
    @eval using CUDA
end

@testset "Fashion-MNIST CUDA backend" begin
    if !TC_GPU_TEST.gpu_available()
        @info "Bỏ qua bài kiểm tra kernel CUDA vì runtime hiện tại không có GPU."
    else
        CUDA.allowscalar(false)

        descriptors = Float32[
            0.0 1.0 2.0 3.0 4.0;
            0.0 0.0 0.0 0.0 0.0
        ]
        centroids = Float32[
            0.0 2.0;
            0.0 0.0
        ]
        expected_words = TC_GPU_TEST.assign_words(descriptors, centroids; backend="cpu")
        cuda_words = TC_GPU_TEST.assign_words(descriptors, centroids;
            backend="cuda", batch_size=2)
        @test cuda_words == expected_words
        @test cuda_words[2] == 1
        @test length(cuda_words) == size(descriptors, 2)

        initial_indices = [1, 4]
        cpu_fit = TC_GPU_TEST.fit_kmeans(descriptors;
            k=2, seed=2026, maxiter=20, tolerance=1.0e-6,
            backend="cpu", initial_indices)
        cuda_fit = TC_GPU_TEST.fit_kmeans(descriptors;
            k=2, seed=2026, maxiter=20, tolerance=1.0e-6,
            backend="cuda", batch_size=2, initial_indices)
        @test cuda_fit.backend == "cuda"
        @test cuda_fit.iterations <= 20
        @test !isempty(cuda_fit.history)
        @test all(isfinite(row.objective) for row in cuda_fit.history)
        @test isapprox(cuda_fit.objective, cpu_fit.objective; atol=1.0e-4, rtol=1.0e-5)

        initial_centroids = descriptors[:, initial_indices]
        initial_words = TC_GPU_TEST.assign_words(descriptors, initial_centroids; backend="cpu")
        initial_objective = sum(sum(abs2, descriptors[:, column] .-
            initial_centroids[:, initial_words[column]]) for column in axes(descriptors, 2))
        one_iteration_fit = TC_GPU_TEST.fit_kmeans(descriptors;
            k=2, seed=2026, maxiter=1, tolerance=0.0,
            backend="cuda", batch_size=2, initial_indices)
        @test !one_iteration_fit.converged
        @test one_iteration_fit.stop_reason == "max_iterations"
        @test one_iteration_fit.iterations == 1
        @test isapprox(one_iteration_fit.history[1].objective_delta,
            one_iteration_fit.objective - initial_objective; atol=1.0e-5)

        duplicate_descriptors = zeros(Float32, 2, 8)
        duplicate_fit = TC_GPU_TEST.fit_kmeans(duplicate_descriptors;
            k=4, seed=42, maxiter=3, batch_size=3)
        @test size(duplicate_fit.centroids) == (2, 4)
        @test all(isfinite, duplicate_fit.centroids)
        @test all(word -> 1 <= word <= 4, duplicate_fit.labels)

        @test TC_GPU_TEST.assign_words(descriptors, centroids;
            backend="cuda", batch_size=2) == expected_words
    end
end
