"""Exploratory data analysis of Fashion-MNIST transactions across S0, S1, S3 and S6-B."""
module FashionMNISTEDA2

using Random
using SHA
using Serialization
using Statistics
using TOML
using ..FashionMNIST: mine
import ..FashionTransactionIO: csv_fields as _csv_fields
using ..FashionTransactionIO: tryparse_compact_transaction

export EDA2Context, load_context, discover_inputs, run_analysis_a!, run_common_pilot!,
    prepare_shortlist!, run_deep_pilot!, prepare_pattern_review!, write_inconclusive_report!, output_path,
    write_configuration_recommendations!, source_sha256, shortlist_review_complete, common_pilot_scope_status,
    deep_pilot_rows_for_selection

const SOURCE_FILES = (
    "inputs/Context.jl",
    "inputs/ArtifactReaders.jl",
    "inputs/Lineage.jl",
    "artifacts/AnalysisArtifacts.jl",
    "analysis/CodebookAnalysis.jl",
    "analysis/PairSampling.jl",
    "analysis/TransactionMetrics.jl",
    "analysis/TransactionSimilarity.jl",
    "analysis/RunAnalysis.jl",
    "analysis/ConfigurationRecommendation.jl",
    "pilot_mining/BoundedMining.jl",
    "pilot_mining/CommonPilot.jl",
    "pilot_mining/Shortlist.jl",
    "pilot_mining/DeepPilot.jl",
    "review/PatternReview.jl",
    "review/SummaryReport.jl",
)

for path in SOURCE_FILES
    include(path)
end

"""Fingerprint the EDA implementation and the shared transaction readers it uses."""
function source_sha256()
    shared = joinpath(@__DIR__, "..", "transaction_io")
    paths = (@__FILE__, (joinpath(@__DIR__, path) for path in SOURCE_FILES)...,
        joinpath(shared, "FashionTransactionIO.jl"), joinpath(shared, "CSVFields.jl"),
        joinpath(shared, "CompactJSONL.jl"))
    return bytes2hex(sha256(join((_sha256(path) for path in paths), '\n')))
end

end # module
