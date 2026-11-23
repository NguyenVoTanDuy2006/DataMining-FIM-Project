using CodecZlib: GzipDecompressor
import Downloads
using SHA: sha256
using TOML

export FASHION_CLASSES, download_fashion_mnist, read_fashion_mnist, load_fashion_mnist,
    format_image_id, parse_image_id, build_dataset_manifest, write_dataset_manifest,
    read_dataset_manifest, create_dataset_manifest, validate_dataset_manifest,
    new_release_run_id

const FASHION_CLASSES = (
    "T-shirt/top", "Trouser", "Pullover", "Dress", "Coat",
    "Sandal", "Shirt", "Sneaker", "Bag", "Ankle boot",
)

const FASHION_SOURCE = "https://github.com/zalandoresearch/fashion-mnist"
const FASHION_DOWNLOAD_BASE =
    "https://raw.githubusercontent.com/zalandoresearch/fashion-mnist/master/data/fashion"

# SHA-256 of the official archives, also checked against the upstream MD5 list.
const FASHION_FILES = (
    (name="train-images-idx3-ubyte.gz", sha256="3aede38d61863908ad78613f6a32ed271626dd12800ba2636569512369268a84"),
    (name="train-labels-idx1-ubyte.gz", sha256="a04f17134ac03560a47e3764e11b92fc97de4d1bfaf8ba1a3aa29af54cc90845"),
    (name="t10k-images-idx3-ubyte.gz", sha256="346e55b948d973a97e58d2351dde16a484bd415d4595297633bb08f03db6a073"),
    (name="t10k-labels-idx1-ubyte.gz", sha256="67da17c76eaffca5446c3361aaab5c3cd6d1c2608764d35dfb1850b086bf8dd5"),
)
const FASHION_DATASET_MANIFEST_SCHEMA_VERSION = 1

"""
    format_image_id(split, zero_based_index)

Return the canonical external identity for a Fashion-MNIST image. The split
index is zero-based and bounded by the official train/test split sizes.
"""
function format_image_id(split::Union{Symbol,AbstractString}, zero_based_index::Integer)
    split_name = String(split)
    split_name in ("train", "test") || throw(ArgumentError("split must be train or test"))
    limit = split_name == "train" ? 60_000 : 10_000
    0 <= zero_based_index < limit ||
        throw(ArgumentError("$split_name image index must be in 0:$(limit - 1)"))
    return "$split_name:$zero_based_index"
end

"""
    parse_image_id(value)

Parse a canonical Fashion-MNIST image ID and return `(split, zero_based_index)`.
"""
function parse_image_id(value::AbstractString)
    matched = match(r"^(train|test):(0|[1-9][0-9]*)$", value)
    isnothing(matched) && throw(ArgumentError("Invalid Fashion-MNIST image ID: $value"))
    split = Symbol(matched.captures[1])
    index = parse(Int, matched.captures[2])
    format_image_id(split, index)
    return (split, index)
end

"Create a unique, filesystem-safe release run identifier."
function new_release_run_id()
    return "fashion_$(time_ns())"
end

function build_dataset_manifest(archive_paths::AbstractDict, archive_hashes::AbstractDict;
    run_id::AbstractString, train_count::Integer=60_000, test_count::Integer=10_000,
    run_root::AbstractString="")
    paths = Dict{String,String}(String(name) => String(path) for (name, path) in archive_paths)
    hashes = Dict{String,String}(String(name) => lowercase(String(digest))
        for (name, digest) in archive_hashes)
    manifest = Dict{String,Any}(
        "schema_version" => FASHION_DATASET_MANIFEST_SCHEMA_VERSION,
        "run_id" => String(run_id),
        "dataset" => "Fashion-MNIST",
        "archive_paths" => paths,
        "archive_sha256" => hashes,
        "train_count" => Int(train_count),
        "test_count" => Int(test_count),
        "image_shape" => [28, 28],
        "class_count" => length(FASHION_CLASSES),
        "image_id_scheme" => "split:zero_based_index",
        "image_id_examples" => ["train:0", "train:59999", "test:0", "test:9999"],
        "run_root" => String(run_root),
        "validation_status" => "PASS",
        "created_at_unix" => time(),
    )
    validate_dataset_manifest(manifest)
    return manifest
end

"Validate the release dataset manifest contract without opening the archives."
function validate_dataset_manifest(manifest::AbstractDict)
    get(manifest, "schema_version", nothing) == FASHION_DATASET_MANIFEST_SCHEMA_VERSION ||
        throw(ArgumentError("Unsupported Fashion-MNIST dataset manifest schema"))
    get(manifest, "dataset", nothing) == "Fashion-MNIST" ||
        throw(ArgumentError("Dataset manifest must identify Fashion-MNIST"))
    run_id = get(manifest, "run_id", "")
    occursin(r"^[A-Za-z0-9][A-Za-z0-9_-]*$", string(run_id)) ||
        throw(ArgumentError("Dataset manifest has an invalid run_id"))
    get(manifest, "train_count", nothing) == 60_000 ||
        throw(ArgumentError("Expected 60,000 train images in dataset manifest"))
    get(manifest, "test_count", nothing) == 10_000 ||
        throw(ArgumentError("Expected 10,000 test images in dataset manifest"))
    get(manifest, "image_shape", nothing) == [28, 28] ||
        throw(ArgumentError("Expected image_shape [28, 28] in dataset manifest"))
    get(manifest, "class_count", nothing) == 10 ||
        throw(ArgumentError("Expected ten classes in dataset manifest"))
    get(manifest, "image_id_scheme", nothing) == "split:zero_based_index" ||
        throw(ArgumentError("Unsupported image ID scheme in dataset manifest"))
    get(manifest, "validation_status", nothing) == "PASS" ||
        throw(ArgumentError("Dataset manifest is not marked PASS"))
    names = Set(file.name for file in FASHION_FILES)
    paths = get(manifest, "archive_paths", nothing)
    hashes = get(manifest, "archive_sha256", nothing)
    paths isa AbstractDict && Set(keys(paths)) == names ||
        throw(ArgumentError("Dataset manifest must contain paths for all four archives"))
    hashes isa AbstractDict && Set(keys(hashes)) == names ||
        throw(ArgumentError("Dataset manifest must contain hashes for all four archives"))
    for file in FASHION_FILES
        lowercase(string(hashes[file.name])) == file.sha256 ||
            throw(ArgumentError("Dataset manifest has an unexpected SHA-256 for $(file.name)"))
        isempty(strip(string(paths[file.name]))) &&
            throw(ArgumentError("Dataset manifest has an empty path for $(file.name)"))
    end
    return true
end

"Write a validated dataset manifest atomically as TOML."
function write_dataset_manifest(path::AbstractString, manifest::AbstractDict)
    validate_dataset_manifest(manifest)
    mkpath(dirname(path))
    temporary = string(path, ".tmp")
    try
        open(temporary, "w") do io
            TOML.print(io, manifest)
            flush(io)
        end
        mv(temporary, path; force=true)
    finally
        isfile(temporary) && rm(temporary; force=true)
    end
    return path
end

"Read and validate a dataset manifest; optionally verify every archive hash."
function read_dataset_manifest(path::AbstractString; verify_archives::Bool=false,
    repo_root::AbstractString=pwd())
    manifest = TOML.parsefile(path)
    validate_dataset_manifest(manifest)
    if verify_archives
        for file in FASHION_FILES
            archive_path = string(manifest["archive_paths"][file.name])
            archive_path = isabspath(archive_path) ? archive_path : joinpath(repo_root, archive_path)
            _verify_fashion_checksum(archive_path, file.sha256)
        end
    end
    return manifest
end

"Load the verified official dataset and produce the run-scoped input manifest."
function create_dataset_manifest(data_dir::AbstractString, run_root::AbstractString;
    repo_root::AbstractString=pwd(), run_id::AbstractString=new_release_run_id(),
    download_missing::Bool=true)
    if download_missing
        download_fashion_mnist(data_dir)
    end
    train = load_fashion_mnist(data_dir; split=:train)
    test = load_fashion_mnist(data_dir; split=:test)
    observed_classes = Set(vcat(train.labels, test.labels))
    observed_classes == Set(0:9) || throw(ArgumentError("Dataset must contain all labels 0:9"))
    root = normpath(abspath(repo_root))
    paths = Dict(file.name => relpath(joinpath(data_dir, file.name), root) for file in FASHION_FILES)
    hashes = Dict(file.name => bytes2hex(open(sha256, joinpath(data_dir, file.name))) for file in FASHION_FILES)
    relative_run_root = relpath(abspath(run_root), root)
    manifest = build_dataset_manifest(paths, hashes; run_id, run_root=relative_run_root)
    manifest_path = joinpath(run_root, "dataset", "dataset_manifest.toml")
    write_dataset_manifest(manifest_path, manifest)
    return (; manifest, manifest_path, train, test)
end

function _verify_fashion_checksum(path, expected)
    actual = open(sha256, path) |> bytes2hex
    actual == expected || throw(ArgumentError("SHA-256 mismatch: $path"))
    return path
end

function _download_fashion_file(url, path, checksum; force=false, downloader=Downloads.download)
    if isfile(path) && !force
        return _verify_fashion_checksum(path, checksum)
    end
    mkpath(dirname(path))
    temporary, io = mktemp(dirname(path))
    close(io)
    try
        downloader(url, temporary)
        _verify_fashion_checksum(temporary, checksum)
        mv(temporary, path; force=true)
    finally
        isfile(temporary) && rm(temporary)
    end
    return path
end

"""
    download_fashion_mnist(data_dir; force=false)

Download the four original Fashion-MNIST `.gz` files into `data_dir`.
Existing files are reused only after SHA-256 verification. A failed download
never replaces an existing archive; use `force=true` to replace a corrupt file.
"""
function download_fashion_mnist(data_dir::AbstractString; force::Bool=false)
    return [
        _download_fashion_file(
            "$FASHION_DOWNLOAD_BASE/$(file.name)", joinpath(data_dir, file.name),
            file.sha256; force=force,
        ) for file in FASHION_FILES
    ]
end

function _read_fashion_images(path)
    bytes = transcode(GzipDecompressor, read(path))
    length(bytes) >= 16 || throw(ArgumentError("Truncated IDX image header: $path"))
    io = IOBuffer(bytes)
    magic, count, rows, columns = ntuple(_ -> Int(ntoh(read(io, UInt32))), 4)
    magic == 2051 || throw(ArgumentError("Expected IDX image magic 2051: $path"))
    (rows, columns) == (28, 28) || throw(ArgumentError("Expected 28×28 images: $path"))
    count > 0 || throw(ArgumentError("Image split must not be empty: $path"))
    length(bytes) == 16 + count * rows * columns ||
        throw(ArgumentError("IDX image count does not match payload: $path"))

    # IDX stores rows consecutively; Julia arrays store columns consecutively.
    pixels = reshape(bytes[17:end], columns, rows, count)
    return permutedims(pixels, (2, 1, 3))
end

function _read_fashion_labels(path)
    bytes = transcode(GzipDecompressor, read(path))
    length(bytes) >= 8 || throw(ArgumentError("Truncated IDX label header: $path"))
    io = IOBuffer(bytes)
    magic, count = ntuple(_ -> Int(ntoh(read(io, UInt32))), 2)
    magic == 2049 || throw(ArgumentError("Expected IDX label magic 2049: $path"))
    length(bytes) == 8 + count ||
        throw(ArgumentError("IDX label count does not match payload: $path"))
    labels = Int.(bytes[9:end])
    all(label -> 0 <= label <= 9, labels) ||
        throw(ArgumentError("Labels must be integers in 0:9: $path"))
    return labels
end

"""
    read_fashion_mnist(images_path, labels_path; expected_count=nothing)

Read gzip-compressed IDX files, validating magic numbers, 28×28 dimensions,
payload lengths, labels 0–9, and matching image/label counts. Returns
`(images, labels)`, with `images[row, column, image]::UInt8` and integer labels.
Pixels remain on the original 0–255 scale; no transpose or normalization is
left for callers to perform.
"""
function read_fashion_mnist(images_path::AbstractString, labels_path::AbstractString;
    expected_count::Union{Nothing,Int}=nothing)
    images = _read_fashion_images(images_path)
    labels = _read_fashion_labels(labels_path)
    size(images, 3) == length(labels) ||
        throw(ArgumentError("Image and label counts differ"))
    isnothing(expected_count) || length(labels) == expected_count ||
        throw(ArgumentError("Expected $expected_count examples, got $(length(labels))"))
    return (; images, labels)
end

"""
    load_fashion_mnist(data_dir; split=:train)

Load the official train (60,000) or test (10,000) split. `data_dir` contains the
four downloaded archives; downloading is an explicit, separate step.
"""
function load_fashion_mnist(data_dir::AbstractString; split::Symbol=:train)
    split in (:train, :test) || throw(ArgumentError("split must be :train or :test"))
    prefix, count = split == :train ? ("train", 60_000) : ("t10k", 10_000)
    dataset = read_fashion_mnist(
        joinpath(data_dir, "$prefix-images-idx3-ubyte.gz"),
        joinpath(data_dir, "$prefix-labels-idx1-ubyte.gz"); expected_count=count,
    )
    return (; dataset..., split)
end
