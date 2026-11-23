"""Chọn mẫu cân bằng xác định; trả chỉ số Julia (bắt đầu từ 1)."""
function balanced_smoke_indices(labels, per_class::Int, seed::Int)
    rng = MersenneTwister(seed)
    ids = Int[]
    for label in 0:9
        candidates = findall(==(label), labels)
        length(candidates) >= per_class || error("Không đủ ảnh cho lớp $label")
        append!(ids, sort(shuffle(rng, candidates)[1:per_class]))
    end
    return ids
end
