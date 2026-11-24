"""Download verified inputs and prepare the five full correctness databases."""
module PrepareData

using Downloads
using SHA

module Benchmarks
include("benchmark_processes.jl")
end
module Groceries
include("groceries_demo.jl")
end

const ROOT = normpath(joinpath(@__DIR__, ".."))
const CHECKSUMS = (
    ("chess", "a12ea887df58a396709430af5bf0a9a32d1f6eba8e7c13dd41f28b98572c5db2"),
    ("mushroom", "6cf94bc482712c3936f0b40c921381ab2b776c3d9941880fecac4d83ca5cbeb5"),
    ("retail", "d967431ba522e32f0fbb243f2ee113ecd4cb374cb0234c1b0858dae1d499a055"),
    ("T10I4D100K", "464d7b87aa7fdc0dc432ddad0493515569b2968b0f229ce39399c454a8c62e0c"),
)

function verified_download(url, path, digest; downloader=Downloads.download)
    checksum(p) = open(io -> bytes2hex(sha256(io)), p)
    if isfile(path)
        checksum(path) == digest || error("Checksum mismatch: $path; existing file was preserved")
        return path
    end
    mkpath(dirname(path))
    temporary, io = mktemp(dirname(path))
    close(io)
    try
        downloader(url, temporary)
        checksum(temporary) == digest || error("Downloaded checksum mismatch: $url")
        mv(temporary, path)
    finally
        isfile(temporary) && rm(temporary)
    end
    return path
end

function main(args=ARGS)
    isempty(args) || throw(ArgumentError("Usage: julia --project=. scripts/prepare_data.jl"))
    for (name, digest) in CHECKSUMS
        verified_download("https://fimi.uantwerpen.be/data/$name.dat",
            joinpath(ROOT, "data", "benchmark", "raw", "$name.dat"), digest)
    end
    verified_download(
        "https://raw.githubusercontent.com/stedy/Machine-Learning-with-R-datasets/master/groceries.csv",
        joinpath(ROOT, "data", "raw", "groceries.csv"),
        "ff1be892fd6b9b57d1a7bc50de067798963dda607619645988b21789bf23ae3b")
    foreach(Benchmarks.prepare_input, Benchmarks.DATASETS)
    Groceries.main(; project_dir=ROOT)
    println("Five full correctness inputs ready; run julia --project=. test/runtests.jl")
end

end # module

if abspath(PROGRAM_FILE) == @__FILE__
    PrepareData.main()
end
