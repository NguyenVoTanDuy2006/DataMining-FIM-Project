function _write_transactions(path, transactions)
    open(path, "w") do io
        for tx in transactions
            println(io, join(tx, ' '))
        end
    end
end
