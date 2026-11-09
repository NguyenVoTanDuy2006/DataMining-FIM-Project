using CodecZlib: GzipDecompressor
import Downloads
using SHA: sha256

export FASHION_CLASSES, download_fashion_mnist, read_fashion_mnist, load_fashion_mnist

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
