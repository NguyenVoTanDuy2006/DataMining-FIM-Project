function covariance_pca_basis(X; chunk_size = 32_768)
    dimension, n = size(X)
    mean_vector = vec(mean(X; dims = 2))
    covariance = zeros(Float64, dimension, dimension)

    for first in 1:chunk_size:n
        last = min(first + chunk_size - 1, n)
        centered = Float64.(X[:, first:last]) .- mean_vector
        covariance .+= centered * transpose(centered)
    end

    covariance ./= n
    decomposition = eigen(Symmetric(covariance))
    order = sortperm(decomposition.values; rev = true)
    eigenvalues = max.(decomposition.values[order], 0.0)
    basis = decomposition.vectors[:, order]
    return mean_vector, basis, eigenvalues
end

function reconstruct_pca_chunk(chunk, pca, dimensions; alpha = nothing)
    (; mu, pca_basis, pca_eigenvalues) = pca
    basis = pca_basis[:, 1:dimensions]
    scores = transpose(basis) * (Float64.(chunk) .- mu)
    reconstructed_scores = scores
    if !isnothing(alpha)
        steps = pca_quantization_steps(pca_eigenvalues, dimensions, alpha)
        bins = quantize_pca_scores(scores, steps)
        reconstructed_scores = reconstruct_pca_scores(bins, steps)
    end
    return mu .+ basis * reconstructed_scores, scores
end

function build_pca_representation(features, dimensions)
    (; X, N, CHUNK_SIZE) = features
    pca = features.pca
    Z = Matrix{Float32}(undef, dimensions, N)
    for first in 1:CHUNK_SIZE:N
        last = min(first + CHUNK_SIZE - 1, N)
        _, scores = reconstruct_pca_chunk(X[:, first:last], pca, dimensions)
        Z[:, first:last] .= Float32.(scores)
    end
    return Z, ones(Int, N)
end
