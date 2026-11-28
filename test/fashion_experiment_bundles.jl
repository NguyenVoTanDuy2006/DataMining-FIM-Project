using Test
using TOML
using EclatFIM

const BUNDLE_IO = EclatFIM.FashionMNIST.ExperimentBundleIO
const EDA2_BUNDLE_TEST = EclatFIM.FashionMNISTEDA2

function write_test_bundle(root, destination; extra_files=String[])
    mkpath(root)
    write(joinpath(root, "result.txt"), "fixture\n")
    for relative in extra_files
        mkpath(dirname(joinpath(root, relative)))
        write(joinpath(root, relative), "extra\n")
    end
    BUNDLE_IO.write_bundle(root, destination, Dict{String,Any}(
        "bundle_kind" => "fashion_eda2_analysis",
        "scope" => "S0_ONLY",
        "status" => "COMPLETED",
        "decision_status" => "INCONCLUSIVE",
    ))
end

function write_toml(path, value)
    mkpath(dirname(path))
    open(path, "w") do io
        TOML.print(io, value)
    end
end

function write_complete_s0_fixture(source_root)
    required = (
        "patch_assignments.csv", "transactions.jsonl", "tid_image_mapping.csv",
        "image_metadata.csv", "config_snapshot.toml", "integrity_report.toml",
        "checkpoint.toml", "codebook.bin", "tc4_metrics.toml",
    )
    for k in (16, 32, 64, 128, 256), seed in (42, 123, 2026)
        run_id = "FashionMNIST_T2_S0_B0_K$(k)_seed$(seed)"
        run_root = joinpath(source_root, run_id)
        mkpath(run_root)
        for filename in required
            write(joinpath(run_root, filename), "fixture $(filename)\n")
        end
        write_toml(joinpath(run_root, "checkpoint.toml"), Dict(
            "run_id" => run_id, "status" => "COMPLETED",
            "source_generation_revision" => "fixture-source-commit",
        ))
        write_toml(joinpath(run_root, "integrity_report.toml"), Dict(
            "status" => "PASS", "transaction_count" => 70_000,
        ))
    end
end

@testset "Fashion experiment bundle paths and archives" begin
    @test BUNDLE_IO.validate_relative_path("S0/run/transactions.jsonl") == "S0/run/transactions.jsonl"
    for unsafe in ("/absolute/file", "../escape", "S0/../../escape", "S0\\run\\file", "C:/drive/file", "./file", "")
        @test_throws ArgumentError BUNDLE_IO.validate_relative_path(unsafe)
    end

    mktempdir() do temporary_root
        payload = joinpath(temporary_root, "payload")
        archive = joinpath(temporary_root, "analysis.tar.gz")
        write_test_bundle(payload, archive)
        extracted = BUNDLE_IO.read_bundle(archive; expected_kind="fashion_eda2_analysis")
        @test read(joinpath(extracted.root, "result.txt"), String) == "fixture\n"
        @test extracted.manifest["schema_version"] == 1
        @test length(extracted.manifest["files"]) == 1
        @test length(extracted.archive_sha256) == 64

        @test_throws ArgumentError BUNDLE_IO.read_bundle(archive; expected_kind="fashion_s0_source")

        invalid_schema = joinpath(temporary_root, "invalid-schema")
        cp(payload, invalid_schema)
        manifest = TOML.parsefile(joinpath(invalid_schema, "manifest.toml"))
        manifest["schema_version"] = 99
        open(joinpath(invalid_schema, "manifest.toml"), "w") do io
            TOML.print(io, manifest)
        end
        invalid_archive = joinpath(temporary_root, "invalid-schema.tar.gz")
        BUNDLE_IO.write_bundle(invalid_schema, invalid_archive,
            Dict{String,Any}("bundle_kind" => "fashion_eda2_analysis", "scope" => "S0_ONLY",
                "status" => "COMPLETED", "decision_status" => "INCONCLUSIVE"); preserve_manifest=true)
        @test_throws ArgumentError BUNDLE_IO.read_bundle(invalid_archive)

        tampered_root = joinpath(temporary_root, "tampered")
        cp(payload, tampered_root)
        write(joinpath(tampered_root, "result.txt"), "changed after inventory\n")
        tampered_archive = joinpath(temporary_root, "tampered.tar.gz")
        BUNDLE_IO.write_bundle(tampered_root, tampered_archive, Dict{String,Any}(); preserve_manifest=true)
        @test_throws ArgumentError BUNDLE_IO.read_bundle(tampered_archive)

        unlisted_root = joinpath(temporary_root, "unlisted")
        cp(payload, unlisted_root)
        write(joinpath(unlisted_root, "surprise.txt"), "not listed\n")
        unlisted_archive = joinpath(temporary_root, "unlisted.tar.gz")
        BUNDLE_IO.write_bundle(unlisted_root, unlisted_archive, Dict{String,Any}(); preserve_manifest=true)
        @test_throws ArgumentError BUNDLE_IO.read_bundle(unlisted_archive)

        missing_root = joinpath(temporary_root, "missing")
        cp(payload, missing_root)
        rm(joinpath(missing_root, "result.txt"))
        missing_archive = joinpath(temporary_root, "missing.tar.gz")
        BUNDLE_IO.write_bundle(missing_root, missing_archive, Dict{String,Any}(); preserve_manifest=true)
        @test_throws ArgumentError BUNDLE_IO.read_bundle(missing_archive)

        duplicate_root = joinpath(temporary_root, "duplicate")
        cp(payload, duplicate_root)
        duplicate_manifest = TOML.parsefile(joinpath(duplicate_root, "manifest.toml"))
        push!(duplicate_manifest["files"], copy(first(duplicate_manifest["files"])))
        open(joinpath(duplicate_root, "manifest.toml"), "w") do io
            TOML.print(io, duplicate_manifest)
        end
        duplicate_archive = joinpath(temporary_root, "duplicate.tar.gz")
        BUNDLE_IO.write_bundle(duplicate_root, duplicate_archive, Dict{String,Any}(); preserve_manifest=true)
        @test_throws ArgumentError BUNDLE_IO.read_bundle(duplicate_archive)

        symlink_root = joinpath(temporary_root, "symlink")
        mkpath(symlink_root)
        symlink(joinpath(payload, "result.txt"), joinpath(symlink_root, "linked.txt"))
        @test_throws ArgumentError BUNDLE_IO.file_inventory(symlink_root)
        symlink_archive = joinpath(temporary_root, "symlink-member.tar.gz")
        BUNDLE_IO._gzip_tar!(symlink_root, symlink_archive)
        @test_throws ArgumentError BUNDLE_IO.read_bundle(symlink_archive)
    end
end

@testset "Fashion S0 source package identities and partial status" begin
    mktempdir() do temporary_root
        source_root = joinpath(temporary_root, "S0")
        mkpath(source_root)
        archive = joinpath(temporary_root, "s0-source.tar.gz")
        BUNDLE_IO.write_s0_source_bundle(source_root, archive;
            packaging_source_commit="test-commit")
        package = BUNDLE_IO.read_bundle(archive; expected_kind="fashion_s0_source")
        runs = package.manifest["runs"]
        expected = Set("FashionMNIST_T2_S0_B0_K$(k)_seed$(seed)"
            for k in (16, 32, 64, 128, 256) for seed in (42, 123, 2026))
        @test length(runs) == 15
        @test Set(row["run_id"] for row in runs) == expected
        @test all(row["status"] == "MISSING" for row in runs)
        @test package.manifest["status"] == "PARTIAL"
        @test package.manifest["packaging_source_commit"] == "test-commit"
        @test all(row["source_generation_revision"] == "UNRECORDED" for row in runs)
        rm(package.root; recursive=true, force=true)
    end
end

@testset "Fashion complete S0 package and TC6 handoff" begin
    mktempdir() do temporary_root
        source_root = joinpath(temporary_root, "source_runs")
        write_complete_s0_fixture(source_root)
        s0_archive = joinpath(temporary_root, "s0-source.tar.gz")
        BUNDLE_IO.write_s0_source_bundle(source_root, s0_archive;
            packaging_source_commit="packager-commit")
        s0_bundle = BUNDLE_IO.read_bundle(s0_archive; expected_kind="fashion_s0_source")
        @test s0_bundle.manifest["status"] == "COMPLETED"
        @test all(row["status"] == "COMPLETED" for row in s0_bundle.manifest["runs"])
        @test all(row["source_generation_revision"] == "fixture-source-commit" for row in s0_bundle.manifest["runs"])

        duplicate_identity_root = joinpath(temporary_root, "duplicate_source_identity")
        mkpath(duplicate_identity_root)
        duplicate_manifest_path = joinpath(s0_bundle.root, "manifest.toml")
        duplicate_manifest = TOML.parsefile(duplicate_manifest_path)
        duplicate_manifest["runs"][end]["run_id"] = duplicate_manifest["runs"][1]["run_id"]
        open(joinpath(duplicate_identity_root, "manifest.toml"), "w") do io
            TOML.print(io, duplicate_manifest)
        end
        for entry in duplicate_manifest["files"]
            relative = split(entry["path"], '/')
            target = joinpath(duplicate_identity_root, relative...)
            mkpath(dirname(target))
            cp(joinpath(s0_bundle.root, relative...), target)
        end
        duplicate_identity_archive = joinpath(temporary_root, "duplicate_s0_identity.tar.gz")
        BUNDLE_IO.write_bundle(duplicate_identity_root, duplicate_identity_archive,
            Dict{String,Any}(); preserve_manifest=true)
        @test_throws ArgumentError BUNDLE_IO.read_bundle(duplicate_identity_archive)

        spatial_root = joinpath(temporary_root, "spatial")
        for k in (16, 32, 64, 128, 256), seed in (42, 123, 2026), variant in ("S1", "S3", "S6-B")
            source_run = "FashionMNIST_T2_S0_B0_K$(k)_seed$(seed)"
            run_id = replace(source_run, "_S0_" => "_$(replace(variant, "-" => ""))_")
            run_root = joinpath(spatial_root, variant == "S6-B" ? "S6B" : variant, run_id)
            mkpath(run_root)
            write(joinpath(run_root, "transactions.jsonl"), "fixture transactions\n")
            write(joinpath(run_root, "item_mapping.csv"), "fixture mapping\n")
            write(joinpath(run_root, "source_artifacts.toml"), "fixture lineage\n")
            write_toml(joinpath(run_root, "checkpoint.toml"), Dict(
                "run_id" => run_id, "variant" => variant, "k" => k, "seed" => seed,
                "status" => "COMPLETED",
            ))
            write_toml(joinpath(run_root, "integrity_report.toml"), Dict(
                "status" => "PASS", "transaction_count" => 70_000,
            ))
        end
        databases = Dict{String,Any}[]
        for k in (16, 32, 64, 128, 256), seed in (42, 123, 2026)
            source_run = "FashionMNIST_T2_S0_B0_K$(k)_seed$(seed)"
            source_dir = joinpath(s0_bundle.root, "S0", source_run)
            push!(databases, Dict{String,Any}(
                "database_id" => source_run, "variant" => "S0", "k" => k, "seed" => seed,
                "transaction_path" => "results/fashion/tc/S0/$(source_run)/transactions.jsonl",
                "item_mapping_ref" => "implicit: item_id equals word_id in 1:K",
                "source_codebook_path" => "results/fashion/tc/S0/$(source_run)/codebook.bin",
                "source_run_path" => "results/fashion/tc/S0/$(source_run)",
                "source_lineage" => "results/fashion/tc/S0/$(source_run)/integrity_report.toml",
                "transaction_count" => 70_000,
                "transaction_sha256" => BUNDLE_IO.archive_sha256(joinpath(source_dir, "transactions.jsonl")),
            ))
            for variant in ("S1", "S3", "S6-B")
                run_id = replace(source_run, "_S0_" => "_$(replace(variant, "-" => ""))_")
                disk_variant = variant == "S6-B" ? "S6B" : variant
                run_dir = joinpath(spatial_root, disk_variant, run_id)
                push!(databases, Dict{String,Any}(
                    "database_id" => run_id, "variant" => variant, "k" => k, "seed" => seed,
                    "transaction_path" => "results/fashion/tc/$(disk_variant)/$(run_id)/transactions.jsonl",
                    "item_mapping_ref" => "results/fashion/tc/$(disk_variant)/$(run_id)/item_mapping.csv",
                    "source_codebook_path" => "results/fashion/tc/S0/$(source_run)/codebook.bin",
                    "source_run_path" => "results/fashion/tc/S0/$(source_run)",
                    "source_lineage" => "results/fashion/tc/$(disk_variant)/$(run_id)/source_artifacts.toml",
                    "transaction_count" => 70_000,
                    "transaction_sha256" => BUNDLE_IO.archive_sha256(joinpath(run_dir, "transactions.jsonl")),
                ))
            end
        end
        write_toml(joinpath(spatial_root, "eda2_database_manifest.toml"), Dict(
            "profile" => "full", "eda2_ready" => true, "database_count" => 60,
            "databases" => databases,
        ))
        spatial_summary_runs = [Dict{String,Any}(
            "run_id" => row["database_id"], "variant" => row["variant"],
            "status" => "COMPLETED", "integrity" => "PASS",
            "output_path" => row["transaction_path"],
        ) for row in databases if row["variant"] != "S0"]
        write_toml(joinpath(spatial_root, "spatial_extension_run_summary.toml"), Dict(
            "schema_version" => 1, "profile" => "full", "source_root" => "old/source",
            "output_root" => "old/output", "completed_new_runs" => 45,
            "expected_new_runs" => 45, "eda2_manifest_ready" => true,
            "eda2_manifest_path" => "old/output/eda2_database_manifest.toml",
            "global_integrity" => Dict("source_integrity" => "PASS", "spatial_integrity" => "PASS"),
            "runs" => spatial_summary_runs,
        ))
        runtime_config = joinpath(temporary_root, "runtime.toml")
        write_toml(runtime_config, Dict("profile" => "full"))
        verified_s0 = BUNDLE_IO.read_bundle(s0_archive; expected_kind="fashion_s0_source",
            destination=joinpath(temporary_root, "verified_s0"))
        handoff_archive = joinpath(temporary_root, "tc6-handoff.tar.gz")
        BUNDLE_IO.build_tc6_handoff(verified_s0.root, spatial_root, handoff_archive;
            producer_source_commit="producer-commit", producer_config_path=runtime_config,
            producer_notebook_sha256=repeat("a", 64), input_archive_sha256=repeat("b", 64))
        handoff = BUNDLE_IO.read_bundle(handoff_archive; expected_kind="fashion_tc6_spatial_handoff")
        @test handoff.manifest["status"] == "COMPLETED"
        @test length(handoff.manifest["source_runs"]) == 15
        @test length(handoff.manifest["spatial_runs"]) == 45
        @test all(row["status"] == "COMPLETED" for row in handoff.manifest["spatial_runs"])
        @test handoff.manifest["eda2_ready"]
        handoff_database_manifest = TOML.parsefile(joinpath(handoff.root, "eda2_database_manifest.toml"))
        @test handoff_database_manifest["eda2_ready"]
        @test length(handoff_database_manifest["databases"]) == 60
        s6b_database = only(filter(row -> row["database_id"] == "FashionMNIST_T2_S6B_B0_K16_seed42",
            handoff_database_manifest["databases"]))
        @test isfile(joinpath(handoff.root, split(s6b_database["transaction_path"], '/')...))
        handoff_summary = TOML.parsefile(joinpath(handoff.root, "spatial_extension_run_summary.toml"))
        @test handoff_summary["global_integrity"]["spatial_integrity"] == "PASS"
        @test handoff_summary["eda2_manifest_path"] == "eda2_database_manifest.toml"
        @test only(filter(row -> row["run_id"] == "FashionMNIST_T2_S1_B0_K16_seed42",
            handoff_summary["runs"]))["output_path"] ==
            "S1/FashionMNIST_T2_S1_B0_K16_seed42"
        @test isfile(joinpath(handoff.root, "producer_runtime_config.toml"))
        @test handoff.manifest["producer_notebook_sha256"] == repeat("a", 64)
        rm(s0_bundle.root; recursive=true, force=true)
        rm(handoff.root; recursive=true, force=true)

        partial_spatial_root = joinpath(temporary_root, "spatial_s6b_partial")
        cp(spatial_root, partial_spatial_root; force=true)
        failed_source = "FashionMNIST_T2_S0_B0_K16_seed42"
        failed_run = replace(failed_source, "_S0_" => "_S6B_")
        write_toml(joinpath(partial_spatial_root, "S6B", failed_run, "checkpoint.toml"), Dict(
            "run_id" => failed_run, "variant" => "S6-B", "k" => 16, "seed" => 42,
            "status" => "FAILED", "failure_reason" => "fixture failure",
        ))
        partial_archive = joinpath(temporary_root, "tc6-handoff-s6b-partial.tar.gz")
        BUNDLE_IO.build_tc6_handoff(verified_s0.root, partial_spatial_root, partial_archive)

        fresh_workspace = joinpath(temporary_root, "separate_eda2_workspace")
        mkpath(fresh_workspace)
        transferred_archive = joinpath(fresh_workspace, "handoff.tar.gz")
        cp(partial_archive, transferred_archive)
        transferred = BUNDLE_IO.read_bundle(transferred_archive;
            expected_kind="fashion_tc6_spatial_handoff",
            destination=joinpath(fresh_workspace, "input_bundle"))
        @test transferred.manifest["status"] == "PARTIAL"
        @test !transferred.manifest["eda2_ready"]
        @test !isfile(joinpath(transferred.root, "eda2_database_manifest.toml"))
        transferred_summary = TOML.parsefile(joinpath(transferred.root, "spatial_extension_run_summary.toml"))
        @test transferred_summary["eda2_manifest_ready"] == false
        @test count(row -> row["variant"] == "S6-B" && row["status"] == "FAILED",
            transferred.manifest["spatial_runs"]) == 1
        @test all(row -> row["status"] == "COMPLETED", transferred.manifest["source_runs"])
        @test all(row -> row["status"] == "COMPLETED",
            filter(row -> row["variant"] in ("S1", "S3"), transferred.manifest["spatial_runs"]))

        eda2_config = TOML.parsefile(joinpath(EclatFIM.FASHION_MNIST_ROOT, "configs", "transaction_eda.toml"))
        eda2_config["input"]["scope"] = "FULL_S0_S1_S3"
        eda2_config["input"]["baseline_root"] = joinpath(transferred.root, "S0")
        eda2_config["input"]["spatial_root"] = transferred.root
        eda2_config["run"]["output_root"] = joinpath(fresh_workspace, "analysis_output")
        eda2_config_path = joinpath(fresh_workspace, "runtime_eda2.toml")
        write_toml(eda2_config_path, eda2_config)
        eda2_context = EDA2_BUNDLE_TEST.load_context(eda2_config_path;
            repo_root=fresh_workspace)
        eda2_specs = EDA2_BUNDLE_TEST.discover_inputs(eda2_context)
        @test eda2_context.scope == "FULL_S0_S1_S3"
        @test length(eda2_specs) == 45
        @test all(count(spec -> spec.variant == variant, eda2_specs) == 15
            for variant in ("S0", "S1", "S3"))
        @test all(isdir(spec.run_dir) for spec in eda2_specs)
        @test !any(spec -> spec.variant == "S6-B", eda2_specs)

        corrupted_handoff_root = joinpath(fresh_workspace, "corrupted_handoff")
        cp(transferred.root, corrupted_handoff_root)
        corrupted_manifest_path = joinpath(corrupted_handoff_root, "manifest.toml")
        corrupted_manifest = TOML.parsefile(corrupted_manifest_path)
        spatial_row = first(filter(row -> row["variant"] == "S1", corrupted_manifest["spatial_runs"]))
        spatial_row["source_run_id"] = "FashionMNIST_T2_S0_B0_K32_seed123"
        open(corrupted_manifest_path, "w") do io
            TOML.print(io, corrupted_manifest)
        end
        corrupted_archive = joinpath(fresh_workspace, "corrupted-handoff.tar.gz")
        BUNDLE_IO.write_bundle(corrupted_handoff_root, corrupted_archive,
            Dict{String,Any}(); preserve_manifest=true)
        @test_throws ArgumentError BUNDLE_IO.read_bundle(corrupted_archive;
            expected_kind="fashion_tc6_spatial_handoff")
        rm(transferred.root; recursive=true, force=true)
        rm(verified_s0.root; recursive=true, force=true)
    end
end
