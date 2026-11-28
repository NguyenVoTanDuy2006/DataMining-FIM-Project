"""Reproduce the full-data K-means fit while varying only BLAS thread count.

Run: julia --project=. scripts/diagnose_kmeans.jl [THREADS ...]
Evidence/cache are local-only under results/colab/kmeans_diagnosis/.
This does not change the release configuration or overwrite its artifacts.
"""
module KMeansDiagnosis

using EclatFIM, Clustering, LinearAlgebra, Random, SHA, Serialization, TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const OUT = joinpath(ROOT, "results", "colab", "kmeans_diagnosis")
const TC = EclatFIM.FashionTC
const REFERENCE = joinpath(ROOT, "results", "colab", "full_70k_383458048574",
    "results", "fashion", "release", "fashion_383458048574", "transactions", "codebook.bin")

array_sha256(x) = bytes2hex(sha256(reinterpret(UInt8, vec(x))))

function descriptors()
    data_dir = joinpath(ROOT, "data", "raw", "fashion-mnist")
    # The standard loader checks archive SHA-256 and IDX geometry.
    train = load_fashion_mnist(data_dir; split=:train)
    test = load_fashion_mnist(data_dir; split=:test)
    images = cat(train.images, test.images; dims=3)
    return first(TC._image_descriptors(images, collect(1:70_000), 29;
        patch_size=4, alpha=0.0))
end

function main(args=ARGS)
    thread_counts = isempty(args) ? [1, 2, BLAS.get_num_threads()] : parse.(Int, args)
    all(>(0), thread_counts) || throw(ArgumentError("BLAS thread counts must be positive"))
    mkpath(OUT)
    cache = joinpath(OUT, "descriptors.bin")
    if !isfile(cache)
        X = descriptors()
        open(io -> serialize(io, X), cache, "w")
    else
        X = open(deserialize, cache)
    end
    @assert size(X) == (16, 2_143_746)
    @assert eltype(X) == Float32 && all(isfinite, X)
    @assert array_sha256(X) == "594c1e8e58b2ab8634afc9e4580a4bf337cee58dee8b26e33208f0bf4ed80ee6"
    reference = isfile(REFERENCE) ? open(deserialize, REFERENCE).centroids : nothing
    println("Descriptor SHA256: ", array_sha256(X))
    println("CPU: ", Sys.CPU_NAME, "; Julia ", VERSION, "; BLAS: ", BLAS.get_config())
    flush(stdout)
    for n_threads in unique(thread_counts)
        BLAS.set_num_threads(n_threads)
        seeds = Clustering.initseeds(:kmpp, X, 32; rng=MersenneTwister(123))
        tag = "$(Sys.CPU_NAME)_$(get(ENV, "OPENBLAS_CORETYPE", "auto"))_t$(n_threads)_$(time_ns())"
        log_path = joinpath(OUT, tag * ".log")
        GC.gc()
        started = time()
        println("START ", tag)
        flush(stdout)
        result = open(log_path, "w") do io
            redirect_stdout(io) do
                redirect_stderr(io) do
                    Clustering.kmeans(X, 32; init=:kmpp, maxiter=300, tol=1e-4,
                        display=:iter, rng=MersenneTwister(123))
                end
            end
        end
        @assert size(result.centers) == (16, 32) && all(isfinite, result.centers)
        @assert length(result.assignments) == size(X, 2)
        metrics = Dict{String,Any}(
            "julia_version" => string(VERSION), "cpu" => Sys.CPU_NAME,
            "julia_cpu_target" => unsafe_string(Base.JLOptions().cpu_target),
            "openblas_coretype_override" => get(ENV, "OPENBLAS_CORETYPE", "auto"),
            "blas_threads" => BLAS.get_num_threads(), "blas_config" => string(BLAS.get_config()),
            "library_version" => string(Base.pkgversion(Clustering)),
            "seed" => 123, "k" => 32, "maxiter" => 300, "tol" => 1e-4,
            "descriptor_sha256" => array_sha256(X), "descriptor_count" => size(X, 2),
            "initial_indices" => seeds, "iterations" => result.iterations,
            "converged" => result.converged, "objective" => Float64(result.totalcost),
            "objective_type" => string(typeof(result.totalcost)),
            "objective_ulp" => Float64(eps(result.totalcost)),
            "distortion" => Float64(result.totalcost / size(X, 2)),
            "centroid_sha256" => array_sha256(result.centers),
            "fit_seconds" => time() - started, "iteration_log" => basename(log_path))
        if !isnothing(reference)
            metrics["exact_colab_centroids"] = result.centers == reference
            metrics["max_abs_centroid_difference"] = Float64(maximum(abs.(result.centers .- reference)))
        end
        open(io -> TOML.print(io, metrics), joinpath(OUT, tag * ".toml"), "w")
        println("RESULT ", tag, ": iterations=", result.iterations,
            ", converged=", result.converged, ", objective=", result.totalcost,
            ", objective ULP=", eps(result.totalcost), ", evidence=", log_path)
        flush(stdout)
    end
end

end # module
if abspath(PROGRAM_FILE) == @__FILE__
    KMeansDiagnosis.main()
end
