function parse_basket(line)
    products = split(line, ",")
    clean_product = String[]
    for product in products 
        push!(clean_product, strip(product))
    end
    clean_basket = unique(clean_product)
    return clean_basket
end

function encode_baskets(baskets, item_to_id)
    transaction = Vector{Int}[]
    for basket in baskets
        item_ids = Int[]
        for product in basket
            id = item_to_id[product]
            push!(item_ids, id)
        end
        push!(transaction, sort(item_ids))
    end
    return transaction
end

function write_item_mapping(path, product_names)
    open(path, "w") do io
        println(io, "id,item_name")

        for (id, product) in enumerate(product_names)
            println(io, id,",",product)
        end
    end
end