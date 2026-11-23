"""Fit full-batch CPU K-means; K-means++ dùng seed đã chỉ định."""
function fit_kmeans(X; k=8, seed=42, maxiter=20, tolerance=1e-4,
    initial_indices=nothing)
    _, n = size(X)
    n >= k || throw(ArgumentError("Cần tối thiểu K descriptors train; nhận $n, K=$k"))
    fit_started = time()
    initialization = isnothing(initial_indices) ? :kmpp : initial_indices
    result = Clustering.kmeans(X, k; init=initialization, maxiter, tol=tolerance,
        display=:none, rng=MersenneTwister(seed))
    return (; centroids=result.centers, labels=result.assignments,
        objective=result.totalcost, iterations=result.iterations,
        converged=result.converged,
        stop_reason=result.converged ? "library_tolerance" : "max_iterations",
        history=NamedTuple[], initialization_seconds=NaN,
        fit_seconds=time() - fit_started, backend="cpu",
        library="Clustering.jl",
        library_version=string(Base.pkgversion(Clustering)),
        initialization=isnothing(initial_indices) ? ":kmpp" : "provided descriptor indices",
        maxiter, tolerance)
end
