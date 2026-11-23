const EXPECTED_K = [16, 32, 64, 128, 256]
const EXPECTED_SEEDS = [42, 123, 2026]
const VARIANTS = ["S0", "S1", "S3"]
const EXPECTED_CODEBOOKS = length(EXPECTED_K) * length(EXPECTED_SEEDS)
const EXPECTED_DATABASES = EXPECTED_CODEBOOKS * length(VARIANTS)
const EXPECTED_IMAGES = 70_000

const CLASS_NAMES = ["T-shirt/top", "Trouser", "Pullover", "Dress", "Coat",
    "Sandal", "Shirt", "Sneaker", "Bag", "Ankle boot"]

struct DatabaseSpec
    database_id::String
    k::Int
    seed::Int
    variant::String
    run_dir::String
    source_dir::String
end

mutable struct EDA2Context
    repo_root::String
    config_path::String
    config::Dict{String,Any}
    output_root::String
    baseline_root::String
    spatial_root::String
    specs::Vector{DatabaseSpec}
    labels::Vector{Int}
    image_ids::Vector{Int}
end

_run_name(k, seed, variant) = "FashionMNIST_T2_$(variant)_B0_K$(k)_seed$(seed)"
_canonical_run(k, seed) = "FashionMNIST_T2_S0_B0_K$(k)_seed$(seed)"
function _theoretical_size(variant, k)
    variant == "S0" && return k
    variant == "S1" && return 4k
    variant == "S3" && return 3k
    throw(ArgumentError("Unsupported EDA2 variant: $variant"))
end
output_path(ctx::EDA2Context, parts...) = joinpath(ctx.output_root, parts...)

function _absolute(repo_root, path)
    normpath(isabspath(String(path)) ? String(path) : joinpath(repo_root, String(path)))
end

function _path_contains(parent, child)
    rel=relpath(child,parent)
    rel=="." || !(rel==".." || startswith(rel,"../"))
end

function load_context(config_path::AbstractString; repo_root=pwd())
    repo_root = normpath(abspath(String(repo_root)))
    config_path = normpath(abspath(String(config_path)))
    isfile(config_path) || throw(ArgumentError("EDA2 config not found: $config_path"))
    config = TOML.parsefile(config_path)
    run = get(config, "run", Dict{String,Any}())
    input = get(config, "input", Dict{String,Any}())
    baseline = _absolute(repo_root, get(input, "baseline_root", "results/fashion/tc/tc6_configs/S0"))
    spatial = _absolute(repo_root, get(input, "spatial_root", "results/fashion/tc/tc6_configs"))
    out = _absolute(repo_root, get(run, "output_root", "results/fashion/eda2/v2"))
    Int(get(input,"expected_images",0))==EXPECTED_IMAGES || throw(ArgumentError("input.expected_images must be 70,000"))
    Int.(get(input,"expected_k",Int[]))==EXPECTED_K || throw(ArgumentError("input.expected_k differs from the fixed EDA2 design"))
    Int.(get(input,"expected_seeds",Int[]))==EXPECTED_SEEDS || throw(ArgumentError("input.expected_seeds differs from the fixed EDA2 design"))
    String.(get(input,"variants",String[]))==VARIANTS || throw(ArgumentError("input.variants differs from the fixed EDA2 design"))
    pilot=get(config,"pilot",Dict{String,Any}())
    0<Float64(get(pilot,"common_minsup_fraction",0.03))<=1 || throw(ArgumentError("common minsup must be in (0,1]"))
    Int(get(pilot,"common_max_itemset_length",2))>=1 || throw(ArgumentError("common max itemset length must be positive"))
    Float64.(get(pilot,"minsup_fractions",[0.01,0.03,0.05,0.10]))==[0.01,0.03,0.05,0.10] || throw(ArgumentError("C3 minsup fractions must use the common grid [0.01, 0.03, 0.05, 0.10]"))
    Int(get(pilot,"deep_max_itemset_length",0))>=1 || throw(ArgumentError("deep_max_itemset_length must be positive"))
    Int(get(pilot,"deep_repetitions",0))>=1 || throw(ArgumentError("deep_repetitions must be positive"))
    resources=get(config,"resources",Dict{String,Any}())
    Float64(get(resources,"per_database_timeout_seconds",0))>0 || throw(ArgumentError("C1 timeout must be positive"))
    Float64(get(resources,"deep_timeout_seconds",0))>0 || throw(ArgumentError("C3 timeout must be positive"))
    Int(get(resources,"max_pair_candidates",0))>0 || throw(ArgumentError("max_pair_candidates must be positive"))
    Int(get(resources,"max_itemsets_per_run",0))>0 || throw(ArgumentError("max_itemsets_per_run must be positive"))
    sampling=get(config,"sampling",Dict{String,Any}())
    Int(get(sampling,"jaccard_pair_sample_size",0))>0 || throw(ArgumentError("Jaccard pair sample size must be positive"))
    Int(get(sampling,"class_within_pair_target",0))>0 && Int(get(sampling,"class_between_pair_target",0))>0 || throw(ArgumentError("B5 pair targets must be positive"))
    for input_root in (baseline, spatial)
        !_path_contains(input_root,out) || throw(ArgumentError("EDA2 output must not be inside a TC input root: $out"))
        !_path_contains(out,input_root) || throw(ArgumentError("EDA2 output and TC input roots must not contain one another"))
    end
    isdir(baseline) || throw(ArgumentError("S0 input root does not exist: $baseline"))
    isdir(spatial) || throw(ArgumentError("TC6 input root does not exist: $spatial"))
    mkpath(out)
    snapshot_path=joinpath(out,"config_snapshot.toml")
    if isfile(snapshot_path)
        _sha256(snapshot_path)==_sha256(config_path) ||
            throw(ArgumentError("EDA2 config differs from the existing output snapshot; use a fresh output_root for a new run"))
    else
        cp(config_path,snapshot_path;force=true)
    end
    return EDA2Context(repo_root, config_path, config, out, baseline, spatial,
        DatabaseSpec[], Int[], Int[])
end

function discover_inputs(ctx::EDA2Context)
    specs = DatabaseSpec[]
    for k in EXPECTED_K, seed in EXPECTED_SEEDS, variant in VARIANTS
        run_id = _run_name(k, seed, variant)
        root = variant == "S0" ? ctx.baseline_root : joinpath(ctx.spatial_root, variant)
        run_dir = joinpath(root, run_id)
        source_dir = joinpath(ctx.baseline_root, _canonical_run(k, seed))
        push!(specs, DatabaseSpec("B0_K$(k)_seed$(seed)_$(variant)", k, seed, variant, run_dir, source_dir))
    end
    ctx.specs = specs
    return copy(specs)
end
