"""Portable Fashion demo using the existing TC stages and Eclat miners."""
module FashionColabDemo

using EclatFIM, TOML, Serialization
using PNGFiles: save
using ColorTypes: Gray

const TC = EclatFIM.FashionTC
const ROOT = normpath(joinpath(@__DIR__, ".."))

function main(args=ARGS)
    length(args) <= 1 || throw(ArgumentError("Usage: fashion_colab_demo.jl [images_per_class|full]"))
    profile = isempty(args) ? "100" : only(args)
    full = profile == "full"
    per_class = full ? 7000 : parse(Int, profile)
    1 <= per_class <= 7000 || throw(ArgumentError("images_per_class must be in 1:7000"))
    run_id = new_release_run_id()
    output = joinpath(ROOT, "results", "colab", run_id)
    mkpath(output)
    data_dir = joinpath(ROOT, "data", "raw", "fashion-mnist")
    download_fashion_mnist(data_dir)
    profiles = joinpath(EclatFIM.FASHION_MNIST_ROOT, "configs", "transactions")
    config = TOML.parsefile(joinpath(profiles, full ? "release.toml" : "combined_smoke.toml"))
    manifest_path = nothing
    if full
        # Use the exact release construction contract for the full-data demo.
        release_root = joinpath(ROOT, "results", "fashion", "release", run_id)
        dataset = create_dataset_manifest(data_dir, release_root; repo_root=ROOT, run_id)
        manifest_path = dataset.manifest_path
    else
        config["run"]["output_root"] = relpath(joinpath(output, "transactions"), ROOT)
        config["dataset"]["smoke_per_class"] = per_class
        config["dataset"]["sample_seed"] = 123
        config["dataset"]["expected_images"] = 10per_class
    end
    config["tc4_codebook"]["k_candidates"] = [32]
    config["tc4_codebook"]["random_seeds"] = [123]
    config["tc4_codebook"]["max_iterations"] = 300
    config_path = joinpath(output, "config.toml")
    open(io -> TOML.print(io, config), config_path, "w")
    state = TC.prepare_run(config_path; repo_root=ROOT, dataset_manifest_path=manifest_path)
    construction_seconds = @elapsed begin
        for stage in (TC.run_tc1!, TC.run_tc2!, TC.run_tc3!, TC.run_tc4!, TC.run_tc5!, TC.run_tc6!, TC.run_tc7!)
            println(stage(state))
            flush(stdout)
        end
    end
    run_dir = state.run_dirs[only(state.run_ids)]
    input_path = joinpath(run_dir, "transactions.jsonl")
    input = EclatFIM.FashionFIMWorkflow.load_transactions(input_path;
        expected_n=10per_class, unique_mapping=true)
    transactions = input.transactions
    # ponytail: portable demo reports mine-only time; use the release supervisor for bounded process RSS measurements.
    selected_pool = Dict{Tuple{Vararg{Int}},Int}()
    open(joinpath(output, "comparison.csv"), "w") do io
        println(io, "minsup,min_count,set_seconds,bitvector_seconds,itemsets,exact_parity,direct_support_audit")
        for fraction in (0.8, 0.6, 0.4, 0.2, 0.1, 0.05)
            min_count = ceil(Int, fraction * length(transactions))
            results = Dict{Symbol,Dict{Tuple{Vararg{Int}},Int}}()
            times = Dict{Symbol,Float64}()
            for backend in (:set, :bitvector)
                mine_count([[1, 2], [2]], 1; backend)
                # Audit is deliberately outside the mining timer.
                elapsed = @elapsed patterns = mine_count(transactions, min_count; backend,
                    deadline=time() + 120, max_itemsets=100_000)
                for (items, support) in patterns
                    count(tx -> all(in(tx), items), transactions) == support ||
                        error("Direct support mismatch for $items")
                end
                results[backend] = patterns
                times[backend] = elapsed
                write_spmf_itemsets(joinpath(output, "$(backend)_$(round(Int, fraction * 100)).txt"), patterns)
            end
            results[:set] == results[:bitvector] || error("Backend parity failed")
            selected_pool = results[:set]
            println(io, join((fraction, min_count, times[:set], times[:bitvector],
                length(selected_pool), true, true), ','))
            flush(io)
        end
    end
    candidates = sort!(collect(keys(selected_pool)); by=p -> (-length(p), -selected_pool[p], p))
    selected = Tuple{Vararg{Int}}[]
    for category in (1, 2, 3)
        index = findfirst(p -> category == 3 ? length(p) >= 3 : length(p) == category, candidates)
        isnothing(index) || push!(selected, candidates[index])
    end
    for pattern in candidates
        length(selected) >= 4 && break
        pattern in selected || push!(selected, pattern)
    end
    isempty(selected) && error("No frequent patterns at 5%; inspect comparison.csv")
    book = open(deserialize, joinpath(run_dir, "codebook.bin"))
    words = open(deserialize, joinpath(run_dir, "assignments.bin"))
    metrics = TOML.parsefile(joinpath(run_dir, "tc4_metrics.toml"))
    open(joinpath(output, "patterns.csv"), "w") do io
        println(io, "pattern,items,support_count," * join(("class_$i" for i in 0:9), ','))
        for (number, pattern) in enumerate(selected)
            tids = findall(tx -> all(in(tx), pattern), transactions)
            counts = [count(tid -> state.labels[tid] == label, tids) for label in 0:9]
            sum(counts) == selected_pool[pattern] || error("Class counts do not reconcile")
            println(io, join((number, join(pattern, ';'), length(tids), counts...), ','))
            # Centroids, actual source patches from the first supporting image, then six images.
            width = 28 * max(length(pattern), 3)
            gallery = zeros(Float32, 112, width)
            for (column, word) in enumerate(pattern)
                gallery[1:28, (column-1)*28+1:column*28] .=
                    repeat(reshape(book.centroids[:, word], 4, 4); inner=(7, 7))
                witness = findfirst(i -> words[i] == word &&
                    state.descriptor_index[i].image_id == state.image_ids[first(tids)], eachindex(words))
                isnothing(witness) && error("Missing source patch for word $word")
                patch = state.descriptor_index[witness]
                y, x = 4(patch.patch_row - 1) + 1, 4(patch.patch_col - 1) + 1
                pixels = Float32.(state.images[y:y+3, x:x+3, first(tids)]) ./ 255f0
                gallery[29:56, (column-1)*28+1:column*28] .= repeat(pixels; inner=(7, 7))
            end
            for (slot, tid) in enumerate(first(tids, min(6, length(tids))))
                row, column = divrem(slot - 1, 3)
                gallery[57+28row:84+28row, 1+28column:28+28column] .=
                    Float32.(state.images[:, :, tid]) ./ 255f0
            end
            save(joinpath(output, "pattern_$number.png"), Gray.(gallery))
        end
    end
    metadata = Dict("status" => "PASS", "profile" => profile, "images" => length(transactions),
        "seed" => 123, "k" => 32, "julia_version" => string(VERSION),
        "input_sha256" => input.input_sha256, "transaction_path" => relpath(input_path, ROOT),
        "construction_seconds" => construction_seconds, "measurement" => "mine_only_after_toy_warmup",
        "fit_status" => metrics["status"], "max_iterations" => 300,
        "peak_rss" => "NOT_MEASURED", "review_status" => "PENDING_REVIEW")
    open(io -> TOML.print(io, metadata), joinpath(output, "manifest.toml"), "w")
    println("Demo output: ", output)
    return output
end

end # module
if abspath(PROGRAM_FILE) == @__FILE__
    FashionColabDemo.main()
end
