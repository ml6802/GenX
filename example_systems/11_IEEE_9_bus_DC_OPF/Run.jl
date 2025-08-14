a=1

using Revise

using GenX
using Gurobi, JuMP

m, inputs = run_genx_case!(dirname(@__FILE__), Gurobi.Optimizer)
