"""Run the notebook's recovery checks without repeating the benchmarks.

Usage: python test/check_colab_notebook.py
Requires Julia; uses Python's standard library only.
"""
import json
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
notebook = json.loads((root / "notebooks/eclat_groceries_benchmarks.ipynb").read_text())
assert notebook["metadata"]["kernelspec"]["name"] == "julia"
assert notebook["metadata"]["language_info"]["name"] == "julia"
cells = ["".join(cell["source"]) for cell in notebook["cells"]]
setup_cell = next(cell for cell in cells if "function show_csv" in cell)
benchmark_cell = next(cell for cell in cells if "function benchmark_and_show" in cell)
archive_cell = next(cell for cell in cells if "archive_path =" in cell)
clone_guard = setup_cell.split("if ispath(REPO_ROOT)", 1)[1].split("\nrepo =", 1)[0]
show_csv = "function show_csv" + setup_cell.split("function show_csv", 1)[1].split('\nprintln("Julia:', 1)[0]
benchmark = "function benchmark_and_show" + benchmark_cell.split("function benchmark_and_show", 1)[1]
package_guard = archive_cell.split('cp("Project.toml"', 1)[0]
# Embed the actual notebook code, rather than reimplementing its guards.
script = "using Test, Markdown\n" + 'include(' + json.dumps(str(root / "src/applications/Fashion-Mnist/transaction_io/CSVFields.jl")) + ')\n'
script += show_csv + "\n" + benchmark + "\n"
script += r'''
function run_julia(script, args...)
    mining_calls[] += 1
    output = args[end]
    mkpath(output)
    write(joinpath(output, "summary.csv"), "name,value\nfixture,1\n")
    write(joinpath(output, "runs.csv"), "name,value\nfixture,1\n")
end
mktempdir() do temporary
    global REPO_ROOT = joinpath(temporary, "broken-checkout")
    mkpath(REPO_ROOT)
    write(joinpath(REPO_ROOT, "user.txt"), "keep")
'''
script += "    @test_throws ErrorException Core.eval(Main, Meta.parseall(" + json.dumps("if ispath(REPO_ROOT)" + clone_guard).replace("$", "\\$") + "))\n"
script += r'''
    @test read(joinpath(REPO_ROOT, "user.txt"), String) == "keep"
    global RUN_ROOT = joinpath(temporary, "run")
    mkpath(RUN_ROOT)
    source = joinpath(temporary, "source")
    mkpath(source)
    write(joinpath(source, "table.csv"), "julia_median_seconds,value\nmine_after_full_database_warmup,1\n")
    # Exercise the notebook renderer and inspect the emitted Markdown object.
    recorder = TextDisplay(IOBuffer())
    pushdisplay(recorder)
    try
        show_csv(joinpath(source, "table.csv"))
        @test occursin("julia_median_seconds", String(take!(recorder.io)))
    finally
        popdisplay(recorder)
    end
    global PYTHON = ARGS[1]
    global BENCHMARK_RUNS = 1
    global mining_calls = Ref(0)
    mkpath(joinpath(RUN_ROOT, "benchmarks", "partial"))
    @test_throws ErrorException benchmark_and_show("partial", "unused.py")
    @test mining_calls[] == 0
    plot = joinpath(temporary, "plot.py")
    write(plot, "raise SystemExit(1)\n")
    @test_throws ProcessFailedException benchmark_and_show("fixture", plot)
    @test isfile(joinpath(RUN_ROOT, "benchmarks", "fixture", "mining_complete"))
    write(plot, "pass\n")
    benchmark_and_show("fixture", plot)
    @test mining_calls[] == 1
    global TESTS_PASSED = true
    for relative in ("tests.txt", "groceries/parameter_summary.csv", "groceries/top10_rules.csv",
            "groceries/groceries_spmf_0.01.txt", "spmf_references/Groceries.txt",
            "spmf_references/Chess.txt", "spmf_references/Mushroom.txt",
            "spmf_references/Retail.txt", "spmf_references/T10I4D100K.txt")
        path = joinpath(RUN_ROOT, relative)
        mkpath(dirname(path))
        write(path, "fixture")
    end
    for name in ("processes", "peak_ram", "scalability", "transaction_length")
        directory = joinpath(RUN_ROOT, "benchmarks", name)
        mkpath(directory)
        for file in ("mining_complete", "summary.csv", "runs.csv")
            touch(joinpath(directory, file))
        end
        stems = name == "processes" ? ("runtime_processes", "itemset_counts") : (name,)
        for stem in stems, extension in ("png", "svg")
            write(joinpath(directory, "$stem.$extension"), "fixture")
        end
    end
    missing = joinpath(RUN_ROOT, "benchmarks", "peak_ram", "peak_ram.svg")
    rm(missing)
'''
script += "    @test_throws AssertionError Core.eval(Main, Meta.parseall(" + json.dumps(package_guard).replace("$", "\\$") + "))\n"
script += '    touch(missing)\n'
script += "    @test_throws AssertionError Core.eval(Main, Meta.parseall(" + json.dumps(package_guard).replace("$", "\\$") + "))\n"
script += '    write(missing, "fixture")\n'
script += "    Core.eval(Main, Meta.parseall(" + json.dumps(package_guard).replace("$", "\\$") + "))\nend\n"
script += r'''mktempdir() do temporary
    global RUN_ROOT = temporary
    global TESTS_PASSED = true
'''
script += "    @test_throws AssertionError Core.eval(Main, Meta.parseall(" + json.dumps(package_guard).replace("$", "\\$") + "))\nend\n"
script += 'println("Notebook recovery checks PASS")\n' 
subprocess.run(["julia", "--startup-file=no", "--color=no", "-", sys.executable], input=script, text=True, check=True, cwd=root)
