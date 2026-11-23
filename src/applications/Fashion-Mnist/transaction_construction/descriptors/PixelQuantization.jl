function quantize_pixel(value, q)
    pixel = clamp(round(Int, Float64(value) * 255), 0, 255)
    return clamp(q * round(Int, pixel / q), 0, 255)
end

function reconstruct_pixel_quantization(chunk, q)
    reconstructed = Matrix{Float64}(undef, size(chunk))
    for column in axes(chunk, 2), dimension in axes(chunk, 1)
        reconstructed[dimension, column] = quantize_pixel(chunk[dimension, column], q) / 255
    end
    return reconstructed
end

function count_pixel_keys!(counts::Dict{UInt128,Int}, chunk, q)
    @inbounds for column in axes(chunk, 2)
        key = zero(UInt128)
        for dimension in axes(chunk, 1)
            quantized = quantize_pixel(chunk[dimension, column], q)
            key = (key << 8) | UInt128(quantized)
        end
        counts[key] = get(counts, key, 0) + 1
    end
    return counts
end

function decode_pixel_key(key::UInt128, dimension)
    shift = 8 * (16 - dimension)
    return Int((key >> shift) & UInt128(0xff))
end

function build_pixel_quant_representation(features, q)
    (; X, N, CHUNK_SIZE) = features
    counts = Dict{UInt128,Int}()
    for first in 1:CHUNK_SIZE:N
        last = min(first + CHUNK_SIZE - 1, N)
        count_pixel_keys!(counts, X[:, first:last], q)
    end
    keys_sorted = sort!(collect(keys(counts)))
    Z = Matrix{Float32}(undef, 16, length(keys_sorted))
    weights = Vector{Int}(undef, length(keys_sorted))
    for (column, key) in enumerate(keys_sorted)
        for dimension in 1:16
            Z[dimension, column] = Float32(decode_pixel_key(key, dimension)) / 255f0
        end
        weights[column] = counts[key]
    end
    return Z, weights
end
