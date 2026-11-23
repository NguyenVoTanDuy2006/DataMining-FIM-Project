function sample_reconstruction_pca(features, ids, dimensions; alpha = nothing)
    (; X, pca) = features
    reconstructed, scores = reconstruct_pca_chunk(X[:, ids], pca, dimensions; alpha)
    return reconstructed
end

function evaluate_baseline_and_pca!(results, features, sample, pca_dimensions)
    (; X, N, CHUNK_SIZE) = features
    (; pair_i, pair_j, pair_ids, pair_slot, raw_pair_distances) = sample
    (; pca, PCA_FIT_SECONDS, raw_mean_feature_variance) = features
    pca_eigenvalues = pca.pca_eigenvalues
    zero_rmse = zeros(Float32, N)
    baseline_started = time()
    append_vector_metrics!(results, "B0", "Raw baseline", 16, nothing, 0.0,
        zero_rmse, 1.0, 1.0, time() - baseline_started, process_high_water_mib(), features)

    for dimensions in pca_dimensions
        started = time()
        squared_error_sum = 0.0
        patch_rmse = Vector{Float32}(undef, N)
        for first in 1:CHUNK_SIZE:N
            last = min(first + CHUNK_SIZE - 1, N)
            range = first:last
            original = X[:, range]
            reconstructed, _ = reconstruct_pca_chunk(original, pca, dimensions)
            difference = Float64.(original) .- reconstructed
            squared_by_patch = vec(sum(abs2, difference; dims = 1))
            squared_error_sum += sum(squared_by_patch)
            patch_rmse[range] .= sqrt.(Float32.(squared_by_patch ./ 16))
        end
        mse = squared_error_sum / (N * 16)
        ids_reconstructed = sample_reconstruction_pca(features, pair_ids, dimensions)
        approx_distances = [sqrt(sum(abs2, ids_reconstructed[:, pair_slot[pair_i[i]]] .-
            ids_reconstructed[:, pair_slot[pair_j[i]]])) for i in eachindex(pair_i)]
        rank_value = spearman_correlation(raw_pair_distances, approx_distances)
        evr = sum(pca_eigenvalues[1:dimensions]) / sum(pca_eigenvalues)
        append_vector_metrics!(results, "P$(lpad(dimensions, 2, '0'))", "PCA", dimensions,
            nothing, mse, patch_rmse, rank_value, evr, PCA_FIT_SECONDS + time() - started,
            process_high_water_mib(), features)
        println("PCA $dimensions D hoàn tất; normalized distortion = ",
            round(mse / raw_mean_feature_variance; digits = 6))
        GC.gc()
    end
end

function evaluate_pixel_quantization!(results, features, sample, q)
    (; X, N, CHUNK_SIZE) = features
    (; pair_i, pair_j, pair_ids, pair_slot, raw_pair_distances) = sample
    started = time()
    counts = Dict{UInt128,Int}()
    squared_error_sum = 0.0
    patch_rmse = Vector{Float32}(undef, N)
    for first in 1:CHUNK_SIZE:N
        last = min(first + CHUNK_SIZE - 1, N)
        range = first:last
        original = X[:, range]
        reconstructed = reconstruct_pixel_quantization(original, q)
        difference = Float64.(original) .- reconstructed
        squared_by_patch = vec(sum(abs2, difference; dims = 1))
        squared_error_sum += sum(squared_by_patch)
        patch_rmse[range] .= sqrt.(Float32.(squared_by_patch ./ 16))
        count_pixel_keys!(counts, original, q)
    end
    mse = squared_error_sum / (N * 16)
    sample_reconstruction = reconstruct_pixel_quantization(X[:, pair_ids], q)
    approx_distances = [sqrt(sum(abs2, sample_reconstruction[:, pair_slot[pair_i[i]]] .-
        sample_reconstruction[:, pair_slot[pair_j[i]]])) for i in eachindex(pair_i)]
    rank_value = spearman_correlation(raw_pair_distances, approx_distances)
    append_vector_metrics!(results, "Q$(lpad(q, 2, '0'))", "Pixel quantization", 16,
        counts, mse, patch_rmse, rank_value, missing, time() - started,
        process_high_water_mib(), features)
    println("Q$q hoàn tất; unique = ", length(counts), " / ", N)
    GC.gc()
end

function evaluate_pca_quantization!(results, features, sample, dimensions, alpha)
    (; X, N, CHUNK_SIZE) = features
    (; pair_i, pair_j, pair_ids, pair_slot, raw_pair_distances) = sample
    (; pca, PCA_FIT_SECONDS, raw_mean_feature_variance) = features
    (; mu, pca_basis, pca_eigenvalues) = pca
    started = time()
    steps = pca_quantization_steps(pca_eigenvalues, dimensions, alpha)
    counts = Dict{NTuple{dimensions,Int32},Int}()
    squared_error_sum = 0.0
    patch_rmse = Vector{Float32}(undef, N)
    basis = pca_basis[:, 1:dimensions]

    for first in 1:CHUNK_SIZE:N
        last = min(first + CHUNK_SIZE - 1, N)
        range = first:last
        original = X[:, range]
        scores = transpose(basis) * (Float64.(original) .- mu)
        bins = quantize_pca_scores(scores, steps)
        reconstructed_scores = reconstruct_pca_scores(bins, steps)
        reconstructed = mu .+ basis * reconstructed_scores
        difference = Float64.(original) .- reconstructed
        squared_by_patch = vec(sum(abs2, difference; dims = 1))
        squared_error_sum += sum(squared_by_patch)
        patch_rmse[range] .= sqrt.(Float32.(squared_by_patch ./ 16))
        count_integer_tuple_keys!(counts, bins, Val(dimensions))
    end

    mse = squared_error_sum / (N * 16)
    sample_reconstruction = sample_reconstruction_pca(features, pair_ids, dimensions; alpha)
    approx_distances = [sqrt(sum(abs2, sample_reconstruction[:, pair_slot[pair_i[i]]] .-
        sample_reconstruction[:, pair_slot[pair_j[i]]])) for i in eachindex(pair_i)]
    rank_value = spearman_correlation(raw_pair_distances, approx_distances)
    evr = sum(pca_eigenvalues[1:dimensions]) / sum(pca_eigenvalues)
    alpha_code = replace(string(round(Int, alpha * 100)), "." => "")
    id = "PQ$(lpad(dimensions, 2, '0'))_A$(alpha_code)"
    append_vector_metrics!(results, id, "PCA + quantization", dimensions, counts,
        mse, patch_rmse, rank_value, evr, PCA_FIT_SECONDS + time() - started,
        process_high_water_mib(), features)
    println("$id hoàn tất; unique = ", length(counts), " / ", N)
    GC.gc()
end
