function pca_quantization_steps(eigenvalues, dimensions, alpha)
    return alpha .* sqrt.(eigenvalues[1:dimensions])
end

function quantize_pca_scores(scores, steps)
    bins = zeros(Int32, size(scores))
    for component in axes(scores, 1)
        step = steps[component]
        if step > eps(Float64)
            @views bins[component, :] .= round.(Int32, scores[component, :] ./ step)
        end
    end
    return bins
end

function reconstruct_pca_scores(bins, steps)
    return ifelse.(steps .<= eps(Float64), 0.0, bins .* steps)
end

function count_integer_tuple_keys!(counts::Dict{NTuple{D,Int32},Int}, bins, ::Val{D}) where D
    @inbounds for column in axes(bins, 2)
        key = ntuple(index -> bins[index, column], Val(D))
        counts[key] = get(counts, key, 0) + 1
    end
    return counts
end

function build_pca_quant_representation(features, dimensions, alpha)
    (; X, N, CHUNK_SIZE) = features
    (; mu, pca_basis, pca_eigenvalues) = features.pca
    steps = pca_quantization_steps(pca_eigenvalues, dimensions, alpha)
    basis = pca_basis[:, 1:dimensions]
    counts = Dict{NTuple{dimensions,Int32},Int}()
    for first in 1:CHUNK_SIZE:N
        last = min(first + CHUNK_SIZE - 1, N)
        scores = transpose(basis) * (Float64.(X[:, first:last]) .- mu)
        bins = quantize_pca_scores(scores, steps)
        count_integer_tuple_keys!(counts, bins, Val(dimensions))
    end

    keys_sorted = sort!(collect(keys(counts)))
    Z = Matrix{Float32}(undef, dimensions, length(keys_sorted))
    weights = Vector{Int}(undef, length(keys_sorted))
    for (column, key) in enumerate(keys_sorted)
        for component in 1:dimensions
            Z[component, column] = Float32(key[component] * steps[component])
        end
        weights[column] = counts[key]
    end
    return Z, weights
end
