using EclatFIM: parse_basket, encode_baskets, write_item_mapping

@testset "Groceries - xu ly gio hang" begin
    # Bỏ trùng trong một giỏ, giữ khoảng trắng bên trong tên sản phẩm.
    @test parse_basket(" milk,bread, milk , eggs ") == ["milk", "bread", "eggs"]
    @test parse_basket("whole milk,cream cheese ,whole milk") ==
          ["whole milk", "cream cheese"]
    @test parse_basket("eggs") == ["eggs"]

    baskets = [["milk", "bread"], ["milk", "bread"], ["eggs"]]
    original_baskets = deepcopy(baskets)
    mapping = Dict("bread" => 1, "eggs" => 2, "milk" => 3)
    transactions = encode_baskets(baskets, mapping)

    # Hai giỏ giống nhau vẫn được tính thành hai giao dịch riêng.
    @test transactions == [[1, 3], [1, 3], [2]]
    @test length(transactions) == 3
    @test baskets == original_baskets
    @test transactions isa Vector{Vector{Int}}
    @test isempty(encode_baskets(Vector{String}[], mapping))
    @test_throws KeyError encode_baskets([["coffee"]], mapping)

    mktempdir(@__DIR__; prefix="groceries_mapping_") do directory
        path = joinpath(directory, "item_mapping.csv")
        write_item_mapping(path, ["bread", "eggs", "milk"])
        @test readlines(path) ==
              ["id,item_name", "1,bread", "2,eggs", "3,milk"]
    end
end
