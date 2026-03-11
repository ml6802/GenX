using GenX, Gurobi

@time run_genx_case!(dirname(@__FILE__), Gurobi.Optimizer)
