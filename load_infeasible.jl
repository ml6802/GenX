using JuMP, Gurobi

#m = read_from_file((@__DIR__)*"/subproblem__10.0.lp")

solver = optimizer_with_attributes(Gurobi.Optimizer, "QCPDual" => true, "ObjScale" => 1e8, "ScaleFlag" => 2)

set_optimizer(m, solver)
 
optimize!(m)