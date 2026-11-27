function _rand_pairs(rng, indices, target)
    n = length(indices)
    max_pairs = n * (n - 1) ÷ 2
    target = min(target, max_pairs)
    out, seen = Tuple{Int,Int}[], Set{Tuple{Int,Int}}()
    while length(out) < target
        a, b = rand(rng, indices), rand(rng, indices)
        a == b && continue
        pair = a < b ? (a, b) : (b, a)
        pair in seen && continue
        push!(seen, pair); push!(out, pair)
    end
    sort!(out)
    return out
end

function _make_pair_manifests!(ctx)
    params = get(ctx.config, "sampling", Dict{String,Any}())
    rng = MersenneTwister(Int(get(params, "pair_sampling_seed", 2026)))
    n_pairs = Int(get(params, "jaccard_pair_sample_size", 20_000))
    all_tids = collect(1:EXPECTED_IMAGES)
    pairs = _rand_pairs(rng, all_tids, n_pairs)
    _write_csv(output_path(ctx, "transactions", "jaccard_pair_manifest.csv"),
        ["tid_a", "tid_b", "seed"], [[a, b, Int(get(params, "pair_sampling_seed", 2026))] for (a, b) in pairs])

    labels = ctx.labels
    if length(labels) != EXPECTED_IMAGES
        class_manifest_path = output_path(ctx, "transactions", "class_similarity_pair_manifest.csv")
        _write_csv(class_manifest_path,
            ["tid_a", "tid_b", "class_a", "class_b", "pair_type", "sampling_stratum", "seed"],
            Vector{Vector{Any}}())
        return pairs, Vector{Vector{Any}}(), _sha256(class_manifest_path)
    end
    class_seed=Int(get(params, "class_pair_sampling_seed", 2026))
    class_rng=MersenneTwister(class_seed)
    class_tids = [findall(==(c), labels) for c in 0:9]
    within_target = Int(get(params, "class_within_pair_target", 50_000))
    between_target = Int(get(params, "class_between_pair_target", 50_000))
    within_per = div(within_target, 10)
    within = Tuple{Int,Int,Int,Int}[]
    for c in 0:9
        append!(within, [(a, b, c, c) for (a, b) in _rand_pairs(class_rng, class_tids[c+1], within_per)])
    end
    classes = [(a, b) for a in 0:9 for b in a+1:9]
    quotas = fill(div(between_target, length(classes)), length(classes))
    for i in 1:rem(between_target, length(classes)); quotas[i] += 1; end
    between = Tuple{Int,Int,Int,Int}[]
    for (i, (a, b)) in enumerate(classes)
        left, right, seen = class_tids[a+1], class_tids[b+1], Set{Tuple{Int,Int}}()
        quota = min(quotas[i], length(left) * length(right))
        while length(seen) < quota
            t1, t2 = rand(class_rng, left), rand(class_rng, right)
            pair = t1 < t2 ? (t1, t2) : (t2, t1)
            push!(seen, pair)
        end
        append!(between, [(a1, b1, a, b) for (a1, b1) in sort!(collect(seen))])
    end
    class_rows = Vector{Vector{Any}}()
    for (a, b, c, d) in within
        push!(class_rows, [a, b, c, d, "within", "class_$c", Int(get(params, "class_pair_sampling_seed", 2026))])
    end
    for (a, b, c, d) in between
        push!(class_rows, [a, b, c, d, "between", "class_$(c)_$(d)", Int(get(params, "class_pair_sampling_seed", 2026))])
    end
    class_manifest_path=output_path(ctx, "transactions", "class_similarity_pair_manifest.csv")
    _write_csv(class_manifest_path,
        ["tid_a", "tid_b", "class_a", "class_b", "pair_type", "sampling_stratum", "seed"], class_rows)
    return pairs, class_rows, _sha256(class_manifest_path)
end
