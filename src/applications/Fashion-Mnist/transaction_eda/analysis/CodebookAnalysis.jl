function _centroid_svg(path, centroids, k)
    cols = min(16, k); rows = cld(k, cols)
    cell, tile = 14, 82
    width, height = max(860,40+cols*tile), max(620,60+rows*tile)
    open(path, "w") do io
        println(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$width\" height=\"$height\" viewBox=\"0 0 $width $height\">")
        println(io, "<rect width=\"100%\" height=\"100%\" fill=\"white\"/><text x=\"20\" y=\"28\" font-size=\"20\">K=$k centroid gallery (4×4 descriptors)</text>")
        for c in 1:k
            x0 = 20 + ((c-1)%cols)*tile; y0 = 50 + ((c-1)÷cols)*tile
            for r in 1:4, col in 1:4
                v = centroids[c, (col-1)*4+r]
                gray = round(Int, 255*clamp(v,0,1))
                println(io, "<rect x=\"$(x0+(col-1)*cell)\" y=\"$(y0+(r-1)*cell)\" width=\"$cell\" height=\"$cell\" fill=\"rgb($gray,$gray,$gray)\"/>")
            end
            println(io, "<text x=\"$x0\" y=\"$(y0+69)\" font-size=\"11\">word $c</text>")
        end
        println(io, "</svg>")
    end
end

function _codebook_analysis!(ctx)
    rows = Vector{Vector{Any}}()
    stability = Vector{Vector{Any}}()
    flags = Vector{Vector{Any}}()
    for k in EXPECTED_K, seed in EXPECTED_SEEDS
        spec = first(filter(s -> s.k == k && s.seed == seed && s.variant == "S0", ctx.specs))
        integrity = _metadata!(spec)
        metrics = TOML.parsefile(joinpath(spec.run_dir, "tc4_metrics.toml"))
        get(metrics,"k",0)==k && get(metrics,"seed",-1)==seed || error("TC4 metrics K/seed mismatch for $(spec.database_id)")
        get(metrics,"method","")=="raw_full_batch_kmeans" || error("TC4 metrics method mismatch for $(spec.database_id)")
        centroids = _read_codebook(joinpath(spec.run_dir, "codebook.bin"), k)
        gallery = output_path(ctx, "codebook", "figures", "centroids_K$(k)_seed$(seed).svg")
        mkpath(dirname(gallery)); _centroid_svg(gallery, centroids, k)
        status = String(get(metrics, "converged", false) ? "CONVERGED" : "NON_CONVERGED")
        empty = Int(get(metrics, "empty_clusters", 0) isa Vector ? length(metrics["empty_clusters"]) : metrics["empty_clusters"])
        flag = empty > 0 ? "DEGENERATE_WARNING" : status
        push!(rows, ["B0", k, seed, _canonical_run(k,seed), relpath(spec.run_dir,ctx.repo_root),
            get(metrics,"distance","unknown"), get(metrics,"distortion_mean_squared",""),
            get(metrics,"occupancy_fraction",""), empty, get(metrics,"normalized_entropy",""),
            get(metrics,"top_cluster_share",""), status, flag, get(metrics,"iterations",""),
            get(metrics,"library_version",""), get(metrics,"seed_stability_ari_mean",""),
            get(metrics,"stability_sample_size",""), get(integrity,"codebook_sha256","")])
        push!(flags, [k, seed, flag, get(metrics,"stop_reason",""), get(metrics,"converged",false)])
    end
    previous_distortion=nothing
    for k in EXPECTED_K
        vals = [parse(Float64,string(r[7])) for r in rows if r[2]==k && r[7] != ""]
        occ = [parse(Float64,string(r[8])) for r in rows if r[2]==k && r[8] != ""]
        ari = [parse(Float64,string(r[16])) for r in rows if r[2]==k && r[16] != ""]
        current_distortion=isempty(vals) ? nothing : mean(vals)
        improvement=isnothing(previous_distortion) || isnothing(current_distortion) || previous_distortion==0 ? "" : (previous_distortion-current_distortion)/previous_distortion
        push!(stability, [k, length(vals), isempty(vals) ? "" : mean(vals), isempty(vals) ? "" : std(vals),
            isempty(vals) ? "" : minimum(vals), isempty(vals) ? "" : maximum(vals), isempty(occ) ? "" : mean(occ), isempty(occ) ? "" : std(occ),
            isempty(ari) ? "" : mean(ari), isempty(ari) ? "" : std(ari), improvement,
            "Saved TC4 ARI only; cohort provenance must be reviewed"])
        previous_distortion=current_distortion
    end
    _write_csv(output_path(ctx,"codebook","codebook_metrics_15.csv"),
        ["method","K","seed","codebook_id","source_path","distortion_definition","distortion","occupancy","empty_clusters","cluster_entropy_norm","top1_cluster_share","convergence_status","flags","iterations","clustering_version","seed_stability_ari_mean_saved","stability_sample_size_saved","codebook_sha256"], rows)
    _write_csv(output_path(ctx,"codebook","codebook_metrics_by_k.csv"),
        ["K","seed_count","distortion_mean","distortion_std","distortion_min","distortion_max","occupancy_mean","occupancy_std","saved_ari_mean","saved_ari_std","relative_improvement_vs_previous_K","stability_note"], stability)
    _write_csv(output_path(ctx,"codebook","seed_stability_by_k.csv"),
        ["K","seed_count","distortion_mean","distortion_std","distortion_min","distortion_max","occupancy_mean","occupancy_std","saved_ari_mean","saved_ari_std","relative_improvement_vs_previous_K","stability_note"], stability)
    _write_csv(output_path(ctx,"codebook","codebook_flags.csv"), ["K","seed","flag","stop_reason","converged"], flags)
    return rows
end
