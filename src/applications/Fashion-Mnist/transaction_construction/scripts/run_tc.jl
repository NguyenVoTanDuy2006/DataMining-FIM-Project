using EclatFIM

const TC = EclatFIM.FashionTC
const PROFILE_DIR = joinpath(EclatFIM.FASHION_MNIST_ROOT, "configs", "transactions")
const PROFILES = ("split_smoke", "split_full", "combined_smoke", "combined_full", "release")
const USAGE = "Usage: julia --project=. run_tc.jl PROFILE_OR_TOML [DATASET_MANIFEST]"

function main(args)
    if isempty(args) || args == ["--help"]
        println(USAGE)
        println("Profiles: ", join(PROFILES, ", "), ". Release requires DATASET_MANIFEST.")
        return
    end
    length(args) <= 2 || throw(ArgumentError(USAGE))
    profile = first(args)
    config_path = if profile in PROFILES
        joinpath(PROFILE_DIR, profile * ".toml")
    elseif isfile(profile)
        abspath(profile)
    else
        throw(ArgumentError("Unknown profile or TOML path: $profile"))
    end
    config = TC.read_config(config_path)
    manifest = length(args) == 2 ? args[2] : nothing
    release = config["run"]["mode"] == "release"
    release && isnothing(manifest) && throw(ArgumentError("Release requires DATASET_MANIFEST"))
    !release && !isnothing(manifest) &&
        throw(ArgumentError("DATASET_MANIFEST is only used by the release profile"))
    repo_root = pkgdir(EclatFIM)
    data_dir = TC._is_combined_profile(config) ? nothing : joinpath(repo_root, "data", "raw", "fashion-mnist")
    result = TC.run_tc(config_path; repo_root, data_dir, dataset_manifest_path=manifest)
    if result isa AbstractDict
        println("Pipeline status: ", result["pipeline_status"])
        println("Report: ", joinpath(repo_root, config["run"]["output_root"], "smoke_test_report.json"))
    else
        println("Output: ", result.output_root)
    end
end

main(ARGS)
