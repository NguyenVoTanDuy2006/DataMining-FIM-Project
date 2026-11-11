module EclatFIM

export mine

include("utils/SPMFIO.jl")
include("algorithm/EclatBaseline.jl")
include("algorithm/EclatOptimized.jl")
include("applications/Groceries.jl")
include("applications/AssociationRules.jl")
include("applications/FashionMNIST.jl")
include("applications/VisualCodebook.jl")
include("applications/VisualMining.jl")

function mine(
    transactions::Vector{Vector{Int}},
    minsup::Real;
    backend::Symbol = :set
)
    if backend == :set
        return mine_baseline(transactions, minsup)
    end

    throw(ArgumentError("Backend $backend is not implemented yet"))
end

end
