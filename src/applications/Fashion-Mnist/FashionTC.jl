module FashionTC

using Clustering
using LinearAlgebra
using Random
using SHA
using Serialization
using Statistics
using Tar
using TOML
using ..FashionMNIST: FASHION_FILES, FASHION_MNIST_ROOT, _verify_fashion_checksum, load_fashion_mnist, mine,
    format_image_id, read_dataset_manifest
import ..FashionTransactionIO: parse_compact_transaction as _parse_transaction_line,
    write_transaction_jsonl as _write_transaction_jsonl

export read_config, balanced_smoke_indices, fit_q10_positive, extract_patches,
    make_descriptors, fit_kmeans, assign_words, encode_transactions, run_smoke,
    prepare_run, run_tc0!, run_tc1!, run_tc2!, run_tc3!, run_tc4!, run_tc5!,
    run_tc6!, run_tc7!, run_full, run_tc, TCv2State, run_unit_smoke_checks!

const DEFAULT_REPO_ROOT = normpath(joinpath(@__DIR__, "..", "..", ".."))
const TC_V2_SCHEMA_VERSION = 1

include("transaction_construction/pipeline/RunState.jl")
include("transaction_construction/pipeline/RunConfig.jl")
include("transaction_construction/dataset/Sampling.jl")
include("transaction_construction/artifacts/ArtifactIO.jl")
include("transaction_construction/dataset/DatasetPreparation.jl")
include("transaction_construction/patches/Patches.jl")
include("transaction_construction/patches/ForegroundFilter.jl")
include("transaction_construction/descriptors/RawDescriptors.jl")
include("transaction_construction/codebook/KMeans.jl")
include("transaction_construction/codebook/WeightedKMeans.jl")
include("transaction_construction/descriptors/PCA.jl")
include("transaction_construction/descriptors/PixelQuantization.jl")
include("transaction_construction/descriptors/PCAQuantization.jl")
include("transaction_construction/codebook/CodebookMetrics.jl")
include("transaction_construction/artifacts/Checkpoints.jl")
include("transaction_construction/artifacts/ArchiveExport.jl")
include("transaction_construction/codebook/CodebookTraining.jl")
include("transaction_construction/codebook/WordAssignment.jl")
include("transaction_construction/transactions/TransactionText.jl")
include("transaction_construction/transactions/ImageMapping.jl")
include("transaction_construction/transactions/BinaryBoVW.jl")
include("transaction_construction/artifacts/SplitExportValidation.jl")
include("transaction_construction/artifacts/CombinedExportValidation.jl")
include("transaction_construction/pipeline/SmokeChecks.jl")
include("transaction_construction/pipeline/Pipeline.jl")
include("transaction_construction/benchmark/BenchmarkMetrics.jl")
include("transaction_construction/benchmark/VectorTradeoff.jl")
include("transaction_construction/benchmark/WeightedBenchmark.jl")
include("transaction_construction/benchmark/BenchmarkExport.jl")
include("transaction_construction/benchmark/BenchmarkPlots.jl")

end
