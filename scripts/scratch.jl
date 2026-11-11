using EclatFIM

transactions = [
    [1, 2, 3],
    [1, 3],
    [2, 3],
    [1, 2],
    [1, 2, 3]
]

results = mine(transactions, 0.4)

for (itemset, support) in sort(collect(results); by=first)
    println("$itemset => $support")
end
