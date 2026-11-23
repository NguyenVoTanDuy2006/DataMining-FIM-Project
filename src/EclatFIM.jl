module EclatFIM

export mine, mine_count, read_spmf_transactions, write_spmf_itemsets,
    read_spmf_itemsets, compare_itemsets, FashionMNIST

include("utils/SPMFIO.jl")
include("algorithm/EclatBaseline.jl")
include("algorithm/EclatOptimized.jl")
include("algorithm/EclatCompatibility.jl")
include("applications/Groceries.jl")
include("applications/AssociationRules.jl")
include("applications/Fashion-Mnist/FashionMNIST.jl")

end # module EclatFIM
