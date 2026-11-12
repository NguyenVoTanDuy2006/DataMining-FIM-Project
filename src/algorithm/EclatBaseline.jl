"""
    build_vertical(transactions::Vector{Vector{Int}}) -> Dict{Int, Set{Int}}

Chuyển dữ liệu dạng transaction sang biểu diễn dọc: mỗi item ánh xạ tới tập
ID của các transaction có chứa item đó.

# Tham số
- `transactions`: danh sách transaction; ID transaction được đánh số từ 1.
  Mỗi transaction trùng nhau vẫn có ID riêng. Item trùng trong một transaction
  chỉ làm ID transaction xuất hiện một lần trong `Set`.

# Trả về
- `Dict{Int, Set{Int}}`: item ID → tập ID transaction chứa item.

# Lỗi
- Ném `ArgumentError` nếu gặp item ID không dương.
"""
function build_vertical(
    transactions::Vector{Vector{Int}}
)::Dict{Int, Set{Int}}
    vertical = Dict{Int, Set{Int}}()

    for (tid, transaction) in enumerate(transactions)
        for item in transaction
            item > 0 || throw(
                ArgumentError("Item IDs must be positive")
            )

            if !haskey(vertical, item)
                vertical[item] = Set{Int}()
            end

            push!(vertical[item], tid)
        end
    end

    return vertical
end

"""
    get_frequent_items(vertical, min_count) -> Vector{Tuple{Int, Set{Int}}}

Lọc các item đơn đạt ngưỡng support tối thiểu và sắp chúng theo item ID tăng dần.

# Tham số
- `vertical`: biểu diễn dọc, item ID → tập ID transaction.
- `min_count`: số transaction tối thiểu mà item phải xuất hiện trong đó.

# Trả về
- Vector các cặp `(item_id, tids)` đạt ngưỡng; `tids` là tập transaction chứa
  item tương ứng, các cặp có thứ tự theo `item_id` tăng dần.
"""
function get_frequent_items(
    vertical::Dict{Int, Set{Int}},
    min_count::Int
)::Vector{Tuple{Int, Set{Int}}}
    candidates = Tuple{Int, Set{Int}}[]

    for item in sort(collect(keys(vertical)))
        tids = vertical[item]

        if length(tids) >= min_count
            push!(candidates, (item, tids))
        end
    end

    return candidates
end

"""
    eclat_dfs!(results, prefix, candidates, min_count) -> nothing

Đệ quy duyệt các candidate theo chiều sâu (DFS). Ghép TID-set của từng cặp
candidate để sinh các itemset mở rộng, ghi support của itemset đạt ngưỡng vào
`results`, rồi tiếp tục với những nhánh còn đủ support.

# Tham số
- `results`: dictionary được cập nhật tại chỗ; khóa là tuple item ID tăng dần,
  giá trị là support count.
- `prefix`: các item đã chọn cho nhánh hiện tại, theo thứ tự tăng dần.
- `candidates`: các cặp `(item_id, tids)` có thứ tự tăng dần; chỉ các item lớn
  hơn item cuối trong prefix được xét để không sinh itemset lặp.
- `min_count`: support count tối thiểu để giữ candidate và tiếp tục mở rộng.

# Trả về
- `nothing`; kết quả được ghi trực tiếp vào `results`.
"""
function eclat_dfs!(
    results::Dict{Tuple{Vararg{Int}}, Int},
    prefix::Vector{Int},
    candidates::Vector{Tuple{Int, Set{Int}}},
    min_count::Int
)::Nothing
    for i in eachindex(candidates)
        item, tids = candidates[i]
        new_prefix = [prefix; item]
        results[Tuple(new_prefix)] = length(tids)

        next_candidates = Tuple{Int, Set{Int}}[]

        for j in (i + 1):length(candidates)
            next_item, next_tids = candidates[j]
            common_tids = intersect(tids, next_tids)

            if length(common_tids) >= min_count
                push!(next_candidates, (next_item, common_tids))
            end
        end

        if !isempty(next_candidates)
            eclat_dfs!(results, new_prefix, next_candidates, min_count)
        end
    end

    return nothing
end

"""
    mine_baseline(transactions, minsup) -> Dict{Tuple{Vararg{Int}}, Int}

Khai thác toàn bộ frequent itemset bằng Eclat baseline với `Set{Int}` TID-set.
`minsup` được hiểu là tỷ lệ trên tổng số transaction và quy đổi thành support
count bằng `ceil(Int, minsup * số_transaction)`.

# Tham số
- `transactions`: danh sách transaction chứa item ID nguyên dương.
- `minsup`: tỷ lệ support trong khoảng `(0, 1]`.

# Trả về
- Dictionary ánh xạ mỗi tuple item ID tăng dần tới số transaction chứa itemset.
  Dictionary rỗng nếu không có transaction hoặc không có itemset đạt ngưỡng.

# Lỗi
- Ném `ArgumentError` nếu `minsup` nằm ngoài `(0, 1]` hoặc có item ID không dương.
"""
function mine_baseline(
    transactions::Vector{Vector{Int}},
    minsup::Real
)::Dict{Tuple{Vararg{Int}}, Int}
    if !(0 < minsup <= 1)
        throw(ArgumentError("minsup must be in (0, 1]"))
    end

    results = Dict{Tuple{Vararg{Int}}, Int}()

    for transaction in transactions, item in transaction
        item > 0 || throw(ArgumentError("item IDs must be positive"))
    end

    isempty(transactions) && return results

    min_count = ceil(Int, minsup * length(transactions))
    vertical = build_vertical(transactions)
    candidates = get_frequent_items(vertical, min_count)

    eclat_dfs!(results, Int[], candidates, min_count)
    return results
end
