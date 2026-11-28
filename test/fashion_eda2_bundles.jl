using Test
using TOML
using EclatFIM

const EDA2_BUNDLES_TEST = EclatFIM.FashionMNISTEDA2
const EDA2_BUNDLE_IO_TEST = EclatFIM.FashionMNIST.ExperimentBundleIO

function write_eda2_test_config(root, scope)
    config = TOML.parsefile(joinpath(EclatFIM.FASHION_MNIST_ROOT, "configs", "transaction_eda.toml"))
    config["input"]["scope"] = scope
    config["input"]["baseline_root"] = joinpath(root, "S0")
    config["input"]["spatial_root"] = joinpath(root, "spatial")
    config["run"]["output_root"] = joinpath(root, "analysis_" * lowercase(scope))
    config["run"]["fail_fast_on_invalid_input"] = false
    config_path = joinpath(root, "runtime.toml")
    open(config_path, "w") do io
        TOML.print(io, config)
    end
    return config_path
end

@testset "EDA2 standalone scope and missing-input handling" begin
    mktempdir() do root
        mkpath(joinpath(root, "S0"))
        s0_config = write_eda2_test_config(root, "S0_ONLY")
        s0_context = EDA2_BUNDLES_TEST.load_context(s0_config; repo_root=root)
        s0_specs = EDA2_BUNDLES_TEST.discover_inputs(s0_context)
        @test s0_context.scope == "S0_ONLY"
        @test length(s0_specs) == 15
        @test all(spec.variant == "S0" for spec in s0_specs)
        @test all(!isdir(spec.run_dir) for spec in s0_specs)
        labels, image_ids = EDA2_BUNDLES_TEST._read_labels!(s0_context)
        @test isempty(labels)
        @test isempty(image_ids)

        full_config = write_eda2_test_config(root, "FULL_S0_S1_S3")
        full_context = EDA2_BUNDLES_TEST.load_context(full_config; repo_root=root)
        full_specs = EDA2_BUNDLES_TEST.discover_inputs(full_context)
        @test full_context.scope == "FULL_S0_S1_S3"
        @test length(full_specs) == 45
        @test Set(spec.variant for spec in full_specs) == Set(("S0", "S1", "S3"))
        @test !isdir(full_context.spatial_root)

        invalid_config = write_eda2_test_config(root, "S0_ONLY")
        invalid = TOML.parsefile(invalid_config)
        invalid["input"]["scope"] = "S6_B"
        open(invalid_config, "w") do io
            TOML.print(io, invalid)
        end
        @test_throws ArgumentError EDA2_BUNDLES_TEST.load_context(invalid_config; repo_root=root)
    end
end

@testset "EDA2 result phase status contract" begin
    mktempdir() do root
        output_root = joinpath(root, "analysis")
        mkpath(output_root)
        write(joinpath(output_root, "summary.md"), "fixture\n")
        archive = joinpath(root, "eda2-analysis.tar.gz")
        EDA2_BUNDLE_IO_TEST.write_bundle(output_root, archive, Dict{String,Any}(
            "bundle_kind" => "fashion_eda2_analysis",
            "scope" => "FULL_S0_S1_S3",
            "status" => "PARTIAL",
            "decision_status" => "INCONCLUSIVE",
            "phase_statuses" => Dict(
                "C1_common_pilot" => "COMPLETED_WITH_CENSORING",
                "C2_shortlist_review" => "AWAITING_HUMAN_REVIEW",
                "C3_deep_mining" => "NOT_REQUESTED",
                "class_label_measures" => "UNAVAILABLE",
            ),
        ))
        bundle = EDA2_BUNDLE_IO_TEST.read_bundle(archive;
            expected_kind="fashion_eda2_analysis")
        @test bundle.manifest["status"] == "PARTIAL"
        @test bundle.manifest["phase_statuses"]["C2_shortlist_review"] == "AWAITING_HUMAN_REVIEW"
        @test bundle.manifest["phase_statuses"]["C1_common_pilot"] == "COMPLETED_WITH_CENSORING"
        rm(bundle.root; recursive=true, force=true)

        bad_root = joinpath(root, "bad-analysis")
        mkpath(bad_root)
        write(joinpath(bad_root, "summary.md"), "fixture\n")
        bad_archive = joinpath(root, "bad-eda2-analysis.tar.gz")
        EDA2_BUNDLE_IO_TEST.write_bundle(bad_root, bad_archive, Dict{String,Any}(
            "bundle_kind" => "fashion_eda2_analysis",
            "scope" => "S0_ONLY",
            "status" => "COMPLETED",
            "phase_statuses" => Dict("C1_common_pilot" => "PRETEND_COMPLETE"),
        ))
        @test_throws ArgumentError EDA2_BUNDLE_IO_TEST.read_bundle(bad_archive)
    end
end

@testset "EDA2 review, support-series, and partial-chart inputs" begin
    placeholder = [Dict{String,String}(
        "K" => string(k), "seed" => string(seed), "selected" => "false",
        "decision_reason" => "REVIEW_REQUIRED", "metrics_used" => "fixture evidence",
    ) for k in (16, 32, 64, 128, 256) for seed in (42, 123, 2026)]
    @test !EDA2_BUNDLES_TEST.shortlist_review_complete(placeholder)
    reviewed = [merge(row, Dict("decision_reason" => "Reviewed and deferred")) for row in placeholder]
    @test EDA2_BUNDLES_TEST.shortlist_review_complete(reviewed)
    @test !EDA2_BUNDLES_TEST.shortlist_review_complete(reviewed[1:end-1])
    @test !EDA2_BUNDLES_TEST.shortlist_review_complete(
        [merge(reviewed[1], Dict("decision_reason" => "INVALID_INPUT_BLOCKED")); reviewed[2:end]])

    support_rows = Dict{String,String}[]
    for (variant, bias) in (("S0", 0), ("S1", 10))
        for seed in (42, 123, 2026), minsup in (0.01, 0.05)
            push!(support_rows, Dict(
                "K" => "32", "seed" => string(seed), "variant" => variant,
                "minsup_fraction" => string(minsup),
                "frequent_singletons" => string(seed ÷ 100 + bias),
            ))
        end
    end
    s0_series = EDA2_BUNDLES_TEST._support_plot_series(support_rows, 32, [0.01, 0.05], ["S0"])
    @test length(s0_series) == 1
    @test first(only(s0_series)) == "S0"
    @test last(only(s0_series)) == [7.0, 7.0]
    full_series = EDA2_BUNDLES_TEST._support_plot_series(support_rows, 32, [0.01], ["S0", "S1"])
    @test [first(series) for series in full_series] == ["S0", "S1"]
    @test all(series -> last(series) isa Vector{Union{Missing,Float64}}, full_series)

    metric_rows = [Dict{String,String}(
        "K" => "32", "seed" => "42", "variant" => variant,
        "max_length" => "16", "p5_length" => "1", "p25_length" => "2",
        "median_length" => "4", "p75_length" => "6", "p95_length" => "10",
    ) for variant in ("S0", "S3")]
    available = EDA2_BUNDLES_TEST.transaction_metric_rows_for_variants(
        metric_rows, 32, 42, ["S0", "S1", "S3"])
    @test first.(available) == ["S0", "S3"]
    @test length(EDA2_BUNDLES_TEST.transaction_metric_rows_for_variants(
        metric_rows, 256, 2026, ["S0", "S1", "S3"])) == 0
end

@testset "EDA2 spatial lineage checksum whitelist" begin
    expected_files = (
        "patch_assignments.csv", "transactions.jsonl", "tid_image_mapping.csv",
        "config_snapshot.toml", "integrity_report.toml", "checkpoint.toml",
        "codebook.bin", "tc4_metrics.toml",
    )
    valid = Dict(name => repeat("a", 64) for name in expected_files)
    @test EDA2_BUNDLES_TEST._validate_source_lineage_hashes(valid) == valid
    @test_throws ErrorException EDA2_BUNDLES_TEST._validate_source_lineage_hashes(
        delete!(copy(valid), "tid_image_mapping.csv"))
    @test_throws ErrorException EDA2_BUNDLES_TEST._validate_source_lineage_hashes(
        merge(valid, Dict("../../outside" => repeat("b", 64))))
    @test_throws ErrorException EDA2_BUNDLES_TEST._validate_source_lineage_hashes(
        merge(valid, Dict("transactions.jsonl" => "not-a-sha256")))

    spatial_rules = Dict{String,Any}(
        "s1" => Dict("row_break_after" => 3, "col_break_after" => 3,
            "region_layout" => ["top_left", "top_right", "bottom_left", "bottom_right"],
            "item_id_formula" => "(region_id - 1) * K + word_id"),
        "s3" => Dict("rows_per_stripe" => [2, 3, 2],
            "item_id_formula" => "(stripe_id - 1) * K + word_id"),
    )
    snapshot = Dict{String,Any}(
        "encoding_version" => "tc6-spatial-v1.0", "variant" => "S1",
        "run_id" => "FashionMNIST_T2_S1_B0_K32_seed42",
        "source_run_id" => "FashionMNIST_T2_S0_B0_K32_seed42",
        "k" => 32, "seed" => 42, "transaction_count" => 70_000,
        "support_denominator" => 70_000, "method_alias" => "B0",
        "training_method" => "raw_full_batch_kmeans", "labels_in_items" => false,
        "transaction_format" => "jsonl", "spatial_rules" => spatial_rules,
    )
    @test EDA2_BUNDLES_TEST._validate_spatial_config_snapshot(snapshot, "S1", 32, 42,
        "FashionMNIST_T2_S0_B0_K32_seed42", "FashionMNIST_T2_S1_B0_K32_seed42")
    bad_encoding = copy(snapshot)
    bad_encoding["encoding_version"] = "tc6-spatial-v0.9"
    @test_throws ErrorException EDA2_BUNDLES_TEST._validate_spatial_config_snapshot(bad_encoding,
        "S1", 32, 42, "FashionMNIST_T2_S0_B0_K32_seed42", "FashionMNIST_T2_S1_B0_K32_seed42")
    bad_rules = deepcopy(snapshot)
    bad_rules["spatial_rules"]["s1"]["row_break_after"] = 2
    @test_throws ErrorException EDA2_BUNDLES_TEST._validate_spatial_config_snapshot(bad_rules,
        "S1", 32, 42, "FashionMNIST_T2_S0_B0_K32_seed42", "FashionMNIST_T2_S1_B0_K32_seed42")
    s3_snapshot = deepcopy(snapshot)
    s3_snapshot["variant"] = "S3"
    s3_snapshot["run_id"] = "FashionMNIST_T2_S3_B0_K32_seed42"
    @test EDA2_BUNDLES_TEST._validate_spatial_config_snapshot(s3_snapshot, "S3", 32, 42,
        "FashionMNIST_T2_S0_B0_K32_seed42", "FashionMNIST_T2_S3_B0_K32_seed42")
end

@testset "C1 scope status follows row identities and censoring flags" begin
    expected_ids = Set(["B0_K16_seed42_S0", "B0_K32_seed42_S0"])
    complete_rows = [Dict{String,String}(
        "database_id" => id, "status" => "COMPLETED_LENGTH_CAPPED", "censored" => "false",
    ) for id in expected_ids]
    @test EDA2_BUNDLES_TEST.common_pilot_scope_status(complete_rows, expected_ids) == "COMPLETED"
    censored_rows = deepcopy(complete_rows)
    censored_rows[1]["censored"] = "true"
    @test EDA2_BUNDLES_TEST.common_pilot_scope_status(censored_rows, expected_ids) == "PARTIAL"
    stale_rows = [merge(complete_rows[1], Dict("database_id" => "B0_K64_seed42_S0")); complete_rows[2]]
    @test EDA2_BUNDLES_TEST.common_pilot_scope_status(stale_rows, expected_ids) == "PARTIAL"
    @test EDA2_BUNDLES_TEST.common_pilot_scope_status(complete_rows[1:1], expected_ids) == "PARTIAL"
end

@testset "C3 cached rows are scoped to the current shortlist" begin
    rows = Dict{String,String}[]
    for (k, seed) in ((32, 123), (64, 42)), variant in ("S0", "S1", "S3")
        push!(rows, Dict("K" => string(k), "seed" => string(seed),
            "variant" => variant, "minsup_fraction" => "0.03"))
    end
    current = EDA2_BUNDLES_TEST.deep_pilot_rows_for_selection(rows, [(32, 123)],
        ["S0", "S1", "S3"], [0.03])
    @test length(rows) == 6
    @test length(current) == 3
    @test Set((parse(Int, row["K"]), parse(Int, row["seed"]), row["variant"],
        parse(Float64, row["minsup_fraction"])) for row in current) ==
        Set((32, 123, variant, 0.03) for variant in ("S0", "S1", "S3"))
    @test isempty(EDA2_BUNDLES_TEST.deep_pilot_rows_for_selection(rows, Tuple{Int,Int}[],
        ["S0", "S1", "S3"], [0.03]))
end
