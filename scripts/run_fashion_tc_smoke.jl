using Dates

const ROOT = dirname(@__DIR__)
include(joinpath(ROOT, "src", "EclatFIM.jl"))
const CONFIG = joinpath(ROOT, "configs", "tc_smoke.toml")
const DATA = joinpath(ROOT, "data", "raw", "fashion-mnist")

println("Fashion-MNIST TC smoke started at ", now())
config = EclatFIM.FashionTC.read_config(CONFIG)
output = normpath(joinpath(ROOT, config["run"]["output_root"]))
report = EclatFIM.FashionTC.run_smoke(CONFIG; data_dir=DATA, output_root=output)
println("Smoke status: ", report["status"])
println("Pipeline status: ", report["pipeline_status"])
println("Report: ", joinpath(output, "smoke_test_report.json"))
report["pipeline_status"] == "PASS" || exit(1)
