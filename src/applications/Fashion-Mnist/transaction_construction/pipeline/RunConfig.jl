function _repo_path(repo_root, path)
    return isabspath(path) ? normpath(path) : normpath(joinpath(repo_root, path))
end

function _validate_training_method(method)
    method in ("raw_full_batch_kmeans", "q20_weighted_kmeans") ||
        throw(ArgumentError("Unsupported TC4 training_method: $method"))
    return method
end

function _validate_split_config(config)
    run_config = get(config, "run", Dict())
    mode = get(run_config, "mode", "")
    mode in ("smoke", "full") || throw(ArgumentError("run.mode phải là smoke hoặc full"))
    output_root = get(run_config, "output_root", "")
    isempty(output_root) && throw(ArgumentError("Thiếu run.output_root"))
    backend = get(get(config, "execution", Dict()), "backend", "cpu")
    backend == "cpu" || throw(ArgumentError("execution.backend hiện chỉ hỗ trợ cpu"))
    if mode == "smoke"
        occursin(joinpath("tc", "smoke"), output_root) ||
            throw(ArgumentError("Smoke output phải nằm trong thư mục riêng tc/smoke"))
    else
        occursin(joinpath("tc", "smoke"), output_root) &&
            throw(ArgumentError("Full output không được ghi vào vùng smoke"))
    end
    return config
end

"""Read the split or combined TC profile using its existing TOML schema."""
function read_config(path::AbstractString)
    config = TOML.parsefile(path)
    _is_combined_profile(config) || _validate_split_config(config)
    return config
end

_is_combined_profile(config) = haskey(config, "tc6_transaction_encoding")

function _profile_repo_root(config_path, repo_root, combined)
    isnothing(repo_root) || return normpath(abspath(repo_root))
    first(splitpath(relpath(config_path, FASHION_MNIST_ROOT))) == "configs" &&
        return DEFAULT_REPO_ROOT
    return combined ? pwd() : dirname(dirname(config_path))
end
