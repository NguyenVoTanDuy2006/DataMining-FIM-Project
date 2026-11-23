mutable struct TCState
    config_path::String
    data_dir::String
    output_root::String
    work_root::String
    config::Dict{String,Any}
    checks::Dict{String,String}
    data::Dict{Symbol,Any}
    started_at::Float64
end

mutable struct TCv2State
    config_path::String
    repo_root::String
    data_dir::String
    output_root::String
    config::Dict{String,Any}
    stage::Int
    images::Array{UInt8,3}
    labels::Vector{Int}
    image_ids::Vector{Int}
    original_splits::Vector{String}
    original_indices::Vector{Int}
    descriptor_matrix::Matrix{Float32}
    descriptor_index::Vector{NamedTuple}
    retained_per_image::Vector{Int}
    archive_hashes::Dict{String,String}
    run_ids::Vector{String}
    run_dirs::Dict{String,String}
    checks::Dict{String,String}
    started_at::Float64
end
