using Revise

using GenX
using Gurobi
using JuMP

m = run_genx_case!(dirname(@__FILE__), Gurobi.Optimizer)

vars = all_variables(m)

for var in vars
    println(var, "    ", value(var))
end