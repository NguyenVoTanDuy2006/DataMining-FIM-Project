using EclatFIM: rule_metrics, evaluate_rule, proper_antecedents, generate_rules

@testset "Luat ket hop - cong thuc" begin
    # Số đếm tính tay giúp phát hiện lỗi cộng support hoặc chia sai dấu ngoặc.
    support, confidence, lift = rule_metrics(4, 6, 5, 10)
    @test support ≈ 0.4
    @test confidence ≈ 2 / 3
    @test lift ≈ 4 / 3

    itemsets = Dict(
        (1,) => 6, (2,) => 5, (3,) => 4,
        (1, 2) => 4, (1, 3) => 3, (2, 3) => 2,
        (1, 2, 3) => 2,
    )
    forward = evaluate_rule(itemsets, (1,), (2,), 10)
    backward = evaluate_rule(itemsets, (2,), (1,), 10)
    @test forward[1] ≈ 0.4
    @test forward[2] ≈ 2 / 3
    @test backward[2] ≈ 0.8
    @test forward[3] ≈ backward[3]
    @test forward[2] != backward[2]

    # Hai vế có thể đến theo thứ tự khác với khóa đã sắp xếp trong Dict.
    triple = evaluate_rule(itemsets, (3,), (1, 2), 10)
    @test triple[1] ≈ 0.2
    @test triple[2] ≈ 0.5
    @test triple[3] ≈ 1.25
end

@testset "Luat ket hop - tap con hop le" begin
    @test isempty(proper_antecedents(()))
    @test isempty(proper_antecedents((1,)))
    @test Set(proper_antecedents((1, 2))) == Set([(1,), (2,)])
    @test Set(proper_antecedents((1, 2, 3))) ==
          Set([(1,), (2,), (3,), (1, 2), (1, 3), (2, 3)])

    # Bốn item có 14 tập con khác rỗng và khác toàn bộ itemset.
    subsets = proper_antecedents((1, 2, 3, 4))
    @test length(subsets) == 14
    @test length(Set(subsets)) == 14
    @test all(subset -> 0 < length(subset) < 4, subsets)
end

@testset "Luat ket hop - sinh va loc" begin
    itemsets = Dict(
        (1,) => 6, (2,) => 5, (3,) => 4,
        (1, 2) => 4, (1, 3) => 3, (2, 3) => 2,
        (1, 2, 3) => 2,
    )
    original_itemsets = copy(itemsets)
    rules = generate_rules(itemsets, 10, 0.0)

    # Đáp án độc lập: hai chiều cho mỗi cặp và sáu luật từ bộ ba.
    expected_directions = Set([
        ((1,), (2,)), ((2,), (1,)),
        ((1,), (3,)), ((3,), (1,)),
        ((2,), (3,)), ((3,), (2,)),
        ((1,), (2, 3)), ((2,), (1, 3)), ((3,), (1, 2)),
        ((1, 2), (3,)), ((1, 3), (2,)), ((2, 3), (1,)),
    ])
    directions = [(rule.antecedent, rule.consequent) for rule in rules]
    @test length(rules) == 12
    @test Set(directions) == expected_directions
    @test length(Set(directions)) == length(rules)
    @test itemsets == original_itemsets

    for rule in rules
        # Hai vế rời nhau và hợp lại thành một itemset đã khai thác.
        @test isempty(intersect(rule.antecedent, rule.consequent))
        key = Tuple(sort(collect(union(rule.antecedent, rule.consequent))))
        @test rule.support_count == itemsets[key]
        @test rule.support ≈ itemsets[key] / 10
        @test 0 < rule.confidence <= 1
    end

    # Bằng ngưỡng vẫn được giữ; không thêm lại một luật cũ bị loại.
    filtered = generate_rules(itemsets, 10, 2 / 3)
    @test any(rule -> rule.antecedent == (1,) && rule.consequent == (2,), filtered)
    @test all(rule -> rule.confidence >= 2 / 3, filtered)

    certain = generate_rules(itemsets, 10, 1.0)
    @test length(certain) == 1
    @test certain[1].antecedent == (2, 3)
    @test certain[1].consequent == (1,)
    @test isempty(generate_rules(Dict((1,) => 6, (2,) => 5), 10, 0.5))
    @test isempty(generate_rules(Dict{Tuple{Vararg{Int}}, Int}(), 10, 0.5))
end
