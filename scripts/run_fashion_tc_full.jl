using EclatFIM

const ROOT = dirname(@__DIR__)
const CONFIG = joinpath(ROOT, "configs", "tc_full.toml")
const DATA = joinpath(ROOT, "data", "raw", "fashion-mnist")

config = EclatFIM.FashionTC.read_config(CONFIG)
output = normpath(joinpath(ROOT, config["run"]["output_root"]))
result = EclatFIM.FashionTC.run_full(CONFIG; data_dir=DATA, output_root=output)
println("Full TC benchmark status: ", result.status)
println("Output: ", result.output_root)
