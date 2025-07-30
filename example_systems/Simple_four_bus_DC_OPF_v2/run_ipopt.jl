using Revise

using GenX
using Ipopt
using JuMP

m, inputs = run_genx_case!(dirname(@__FILE__), Ipopt.Optimizer)
#inputs = run_genx_case!(d"irname(@__FILE__), Gurobi.Optimizer)

#=
vars = all_variables(m)

for var in vars[20:40]
    println(var, "    ", value(var))
end
=#