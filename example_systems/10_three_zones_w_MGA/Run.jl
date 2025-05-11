using GenX, Gurobi

@everywhere include("/home/ml6802/GenX-Bend-0.4/GenX/src/GenX.jl")

run_genx_case!(dirname(@__FILE__), Gurobi.Optimizer)
