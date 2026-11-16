# TODO(TV2): Derive association rules from mined itemsets and support counts.
function rule_metrics(count_xy, count_x, count_y, n_transactions)
    support = count_xy / n_transactions
    confidence = count_xy / count_x
    lift = confidence / (count_y/ n_transactions)
    return support, confidence, lift
end

# đánh giá luật
function evaluate_rule(frequent_itemsets, antecedent, consequent, n_transactions)
    # antecedent: vế trái.
    # consequent: vế phải.
    combined_items = union(antecedent, consequent)
    combined_key = Tuple(sort(collect(combined_items)))
    count_xy = frequent_itemsets[combined_key]
    count_x = frequent_itemsets[antecedent]
    count_y = frequent_itemsets[consequent]

    return rule_metrics(count_xy, count_x, count_y, n_transactions)
end

# tạo luật vế trái
function collect_antecedents(prefix, items, start_position, antecedents)
    for i in start_position:length(items)
        new_prefix = copy(prefix)
        push!(new_prefix, items[i])
 
        if length(new_prefix) < length(items)
            push!(antecedents, Tuple(new_prefix))

            collect_antecedents(
                new_prefix, items, i + 1, antecedents
            )
        end
    end
end

function proper_antecedents(itemset)
    antecedents = Tuple{Vararg{Int}}[]
    collect_antecedents(Int[], collect(itemset), 1, antecedents)

    return antecedents
end


function generate_rules(frequent_itemsets, n_transactions, minconf)
    rules = NamedTuple[]

    for (itemset, count_xy) in frequent_itemsets
        if length(itemset) >= 2
            for antecedent in proper_antecedents(itemset)
                consequent = Tuple(
                    setdiff(collect(itemset), collect(antecedent))
                )

                support, confidence, lift = evaluate_rule(
                    frequent_itemsets,
                    antecedent,
                    consequent,
                    n_transactions,
                )

                if confidence >= minconf
                    rule = (
                        antecedent = antecedent,
                        consequent = consequent,
                        support_count = count_xy,
                        support = support,
                        confidence = confidence,
                        lift = lift,
                    )

                    push!(rules, rule)
                end
            end
        end
    end

    return rules
end