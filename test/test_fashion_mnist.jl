using CodecZlib: GzipCompressor
using SHA: sha256

function write_idx_fixture(path, header, payload)
    io = IOBuffer()
    for value in header
        write(io, hton(UInt32(value)))
    end
    write(io, payload)
    write(path, transcode(GzipCompressor, take!(io)))
end

@testset "Fashion-MNIST IDX input" begin
    mktempdir() do dir
        images_path = joinpath(dir, "images.gz")
        labels_path = joinpath(dir, "labels.gz")
        # Non-symmetric pixels reveal row/column transposition and image swaps.
        images = [UInt8(mod(7 * row + 3 * column + index, 256))
            for row in 1:28, column in 1:28, index in 1:2]
        payload = vec(permutedims(images, (2, 1, 3)))
        write_idx_fixture(images_path, (2051, 2, 28, 28), payload)
        write_idx_fixture(labels_path, (2049, 2), UInt8[0, 9])
        dataset = read_fashion_mnist(images_path, labels_path; expected_count=2)
        @test size(dataset.images) == (28, 28, 2)
        @test eltype(dataset.images) == UInt8
        @test dataset.images == images
        @test dataset.labels == [0, 9]
        @test_throws ArgumentError read_fashion_mnist(images_path, labels_path; expected_count=3)
        @test_throws ArgumentError load_fashion_mnist(dir; split=:validation)

        for header in ((999, 2, 28, 28), (2051, 2, 14, 56), (2051, 3, 28, 28))
            write_idx_fixture(images_path, header, payload)
            @test_throws ArgumentError read_fashion_mnist(images_path, labels_path)
        end
        write(images_path, transcode(GzipCompressor, UInt8[0, 0, 8]))
        @test_throws ArgumentError read_fashion_mnist(images_path, labels_path)
        write_idx_fixture(images_path, (2051, 2, 28, 28), payload[1:end-1])
        @test_throws ArgumentError read_fashion_mnist(images_path, labels_path)
        write_idx_fixture(images_path, (2051, 2, 28, 28), vcat(payload, 0x00))
        @test_throws ArgumentError read_fashion_mnist(images_path, labels_path)
        write_idx_fixture(images_path, (2051, 2, 28, 28), payload)

        for (header, labels) in (
            ((999, 2), UInt8[0, 9]), ((2049, 2), UInt8[0, 10]),
            ((2049, 3), UInt8[0, 1, 9]), ((2049, 2), UInt8[0]),
        )
            write_idx_fixture(labels_path, header, labels)
            @test_throws ArgumentError read_fashion_mnist(images_path, labels_path)
        end
        write(labels_path, transcode(GzipCompressor, UInt8[0]))
        @test_throws ArgumentError read_fashion_mnist(images_path, labels_path)
    end
end

@testset "Verified Fashion-MNIST downloads" begin
    mktempdir() do dir
        path = joinpath(dir, "archive.gz")
        payload = UInt8[1, 3, 5]
        checksum = bytes2hex(sha256(payload))
        calls = Ref(0)
        downloader = function (_, temporary)
            calls[] += 1
            write(temporary, payload)
        end
        EclatFIM._download_fashion_file("fixture", path, checksum; downloader)
        @test read(path) == payload
        EclatFIM._download_fashion_file("fixture", path, checksum; downloader)
        @test calls[] == 1
        @test_throws ArgumentError EclatFIM._download_fashion_file(
            "fixture", path, "bad-checksum"; downloader,
        )
        @test calls[] == 1
        bad_downloader = (_, temporary) -> write(temporary, UInt8[9])
        @test_throws ArgumentError EclatFIM._download_fashion_file(
            "fixture", path, checksum; force=true, downloader=bad_downloader,
        )
        @test read(path) == payload
        @test readdir(dir) == ["archive.gz"]
    end
end
