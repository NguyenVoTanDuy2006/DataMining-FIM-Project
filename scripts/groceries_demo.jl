# Chạy từ thư mục gốc: julia --project=. scripts/groceries_demo.jl
import Pkg
Pkg.activate(joinpath(@__DIR__, ".."); io=devnull)

using EclatFIM: mine, parse_basket, encode_baskets, write_item_mapping, generate_rules

# Đọc từng giỏ hàng, giữ cả những giỏ có cùng danh sách sản phẩm.
function load_baskets(path)
    baskets = Vector{String}[]
    for line in eachline(path)
        push!(baskets, parse_basket(line))
    end
    return baskets
end

# Sắp xếp tên trước khi gán ID để các lần chạy có cùng mapping.
function build_mapping(baskets)
    vocabulary = Set{String}()
    for basket in baskets, product in basket
        push!(vocabulary, product)
    end

    product_names = sort(collect(vocabulary))
    item_to_id = Dict{String, Int}()
    for (id, product) in enumerate(product_names)
        item_to_id[product] = id
    end
    return item_to_id, product_names
end

# Mỗi dòng là một giao dịch, các ID được ngăn cách bằng dấu cách.
function write_spmf(path, transactions)
    open(path, "w") do io
        for transaction in transactions
            println(io, join(transaction, " "))
        end
    end
end

# Bao dấu nháy kép nếu ô CSV có dấu phẩy, nháy kép hoặc xuống dòng.
function csv_field(value)
    text = string(value)
    if occursin(",", text) || occursin("\"", text) ||
       occursin("\n", text) || occursin("\r", text)
        return "\"" * replace(text, "\"" => "\"\"") * "\""
    end
    return text
end

function write_csv_row(io, values)
    println(io, join((csv_field(value) for value in values), ","))
end

# Nếu lift bằng nhau, dùng thêm tiêu chí để thứ tự không phụ thuộc Dict.
function select_top_rules(rules, limit=10)
    sorted_rules = sort(
        rules;
        by=rule -> (
            -rule.lift,
            -rule.confidence,
            -rule.support,
            rule.antecedent,
            rule.consequent,
        ),
    )
    return first(sorted_rules, min(limit, length(sorted_rules)))
end

function write_top_rules(path, top_rules, product_names, minsup, minconf)
    open(path, "w") do io
        write_csv_row(
            io,
            ("rank", "antecedent", "consequent", "support_count",
             "support", "confidence", "lift", "minsup", "minconf"),
        )
        for (rank, rule) in enumerate(top_rules)
            left = join([product_names[id] for id in rule.antecedent], " + ")
            right = join([product_names[id] for id in rule.consequent], " + ")
            write_csv_row(
                io,
                (rank, left, right, rule.support_count, rule.support,
                 rule.confidence, rule.lift, minsup, minconf),
            )
        end
    end
end

# Mỗi minsup chỉ chạy Eclat một lần, rồi thử ba ngưỡng confidence.
function write_parameter_summary(path, transactions)
    open(path, "w") do io
        write_csv_row(io, ("minsup", "minconf", "itemsets", "rules"))
        for minsup in (0.005, 0.01, 0.02, 0.03)
            itemsets = mine(transactions, minsup; backend=:set)
            for minconf in (0.3, 0.5, 0.7)
                rules = generate_rules(itemsets, length(transactions), minconf)
                write_csv_row(io, (minsup, minconf, length(itemsets), length(rules)))
            end
        end
    end
end

function main(; project_dir=normpath(joinpath(@__DIR__, "..")))
    # 1. Đọc dữ liệu và mã hóa tên sản phẩm thành ID.
    input_path = joinpath(project_dir, "data", "raw", "groceries.csv")
    baskets = load_baskets(input_path)
    item_to_id, product_names = build_mapping(baskets)
    transactions = encode_baskets(baskets, item_to_id)

    # 2. Lưu dữ liệu đã mã hóa và mapping.
    processed_dir = joinpath(project_dir, "data", "processed")
    results_dir = joinpath(project_dir, "results", "groceries")
    mkpath(processed_dir)
    mkpath(results_dir)
    write_spmf(joinpath(processed_dir, "groceries_spmf.txt"), transactions)
    write_item_mapping(joinpath(processed_dir, "item_mapping.csv"), product_names)

    # 3. Khai thác cấu hình chính và chọn tối đa 10 luật theo lift.
    minsup = 0.01
    minconf = 0.5
    itemsets = mine(transactions, minsup; backend=:set)
    rules = generate_rules(itemsets, length(transactions), minconf)
    top_rules = select_top_rules(rules)
    top_path = joinpath(results_dir, "top10_rules.csv")
    write_top_rules(top_path, top_rules, product_names, minsup, minconf)

    # 4. Lưu bảng so sánh đủ 12 cấu hình.
    summary_path = joinpath(results_dir, "parameter_summary.csv")
    write_parameter_summary(summary_path, transactions)

    println("Số giỏ hàng: ", length(transactions))
    println("Số sản phẩm khác nhau: ", length(product_names))
    println("Số frequent itemsets: ", length(itemsets))
    println("Số luật đạt ngưỡng: ", length(rules))
    println("Số luật trong bảng top: ", length(top_rules))
    println("Đã lưu: ", top_path)
    println("Đã lưu: ", summary_path)

    # Trả thống kê để test không cần phân tích nội dung in trên màn hình.
    return (
        n_transactions=length(transactions),
        n_products=length(product_names),
        n_itemsets=length(itemsets),
        n_rules=length(rules),
        n_top_rules=length(top_rules),
    )
end

# Include để kiểm thử sẽ không tự chạy hoặc ghi đè dữ liệu thật.
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
