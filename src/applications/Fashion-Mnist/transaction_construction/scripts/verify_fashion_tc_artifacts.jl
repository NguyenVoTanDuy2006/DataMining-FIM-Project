using Serialization

length(ARGS) == 1 || error("Usage: julia verify_fashion_tc_artifacts.jl OUTPUT_DIR")
output = ARGS[1]
centroids = open(deserialize, joinpath(output, "codebook.bin"))
assignments = open(deserialize, joinpath(output, "assignments.bin"))
train = open(deserialize, joinpath(output, "train_descriptors.bin"))
validation = open(deserialize, joinpath(output, "validation_descriptors.bin"))
train_transactions = [isempty(strip(line)) ? Int[] : parse.(Int, split(strip(line)))
    for line in eachline(joinpath(output, "train_transactions.txt"))]
validation_transactions = [isempty(strip(line)) ? Int[] : parse.(Int, split(strip(line)))
    for line in eachline(joinpath(output, "validation_transactions.txt"))]

size(centroids) == (16, 8) || error("Unexpected codebook shape")
length(assignments.train_words) == size(train.descriptors, 2) || error("Train assignment count mismatch")
length(assignments.valid_words) == size(validation.descriptors, 2) || error("Validation assignment count mismatch")
length(train_transactions) == 100 || error("Train transaction count mismatch")
length(validation_transactions) == 20 || error("Validation transaction count mismatch")
println("Fresh-process artifact reload PASS: codebook, assignments, descriptors, 120 transactions")
