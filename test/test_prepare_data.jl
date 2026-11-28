module PrepareDataTests
using Test, SHA
include("../scripts/prepare_data.jl")

@testset "Verified input download preserves existing data" begin
    mktempdir() do dir
        path = joinpath(dir, "input.dat")
        digest = bytes2hex(sha256("1 2\n"))
        good = (_, target) -> write(target, "1 2\n")
        bad = (_, target) -> write(target, "corrupt")
        @test_throws ErrorException PrepareData.verified_download("fixture", path, digest; downloader=bad)
        @test isempty(readdir(dir))
        @test PrepareData.verified_download("fixture", path, digest; downloader=good) == path
        @test PrepareData.verified_download("fixture", path, digest; downloader=bad) == path
        write(path, "user data")
        @test_throws ErrorException PrepareData.verified_download("fixture", path, digest; downloader=good)
        @test read(path, String) == "user data"
    end
end
end
