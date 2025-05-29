using Revise

using GenX
using Gurobi
using JuMP

m, inputs = run_genx_case!(dirname(@__FILE__), Gurobi.Optimizer)

vars = all_variables(m)

for var in vars[80:100]
    println(var, "    ", value(var))
end