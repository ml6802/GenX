using Revise

using GenX
using Gurobi
using JuMP

# True solution in call cases is 17000
# There are three different cases with different network structures
# Each case starts with virtually no transmission. Case 1 has four possible line
# corridors with 3-6 lines per corridor. Case 2 has six possible line corridors 
# with each corridor having 6 possible lines constructed on that corridor (each line 
# having a size of 50 MW). Case 3 is the same as case 2, but with 12 candidate lines
# and each line have a sze of 25 MW

# I also played with the big M value to see if it helped convergence. I cannot say it
# improved convergence, but it can be set using the `tight_bigM` key word argument
# passed to the `run_genx_case` function


########### Case 1: 4 candidate line corridors, 3-6 lines per corridor ############
m, inputs = run_genx_case!((@__DIR__)*"/Simple_four_bus_DC_OPF_v1/", Gurobi.Optimizer)
println("OBJECTIVE VALUE, Case 1, no Benders = ", objective_value(m)) #REACHES TRUE SOLUTION

inputs, UB_hist = run_genx_case!((@__DIR__)*"/Simple_four_bus_DC_OPF_v1_Benders/", Gurobi.Optimizer)
println("OBJECTIVE VALUE, Case 1, with Benders = ", minimum(UB_hist)) #REACHES TRUE SOLUTION

# try different big M value
m, inputs = run_genx_case!((@__DIR__)*"/Simple_four_bus_DC_OPF_v1/", Gurobi.Optimizer, tight_bigM = true)
println("OBJECTIVE VALUE, Case 1, no Benders = ", objective_value(m)) #REACHES TRUE SOLUTION

inputs, UB_hist = run_genx_case!((@__DIR__)*"/Simple_four_bus_DC_OPF_v1_Benders/", Gurobi.Optimizer, tight_bigM = true)
println("OBJECTIVE VALUE, Case 1, with Benders = ", minimum(UB_hist)) #REACHES TRUE SOLUTION


########### Case 2: 6 candidate line corridors, 6 lines per corridor ###########
m, inputs = run_genx_case!((@__DIR__)*"/Simple_four_bus_DC_OPF_v2/", Gurobi.Optimizer)
println("OBJECTIVE VALUE, Case 1, no Benders = ", objective_value(m)) #REACHES TRUE SOLUTION

inputs, UB_hist = run_genx_case!((@__DIR__)*"/Simple_four_bus_DC_OPF_v2_Benders/", Gurobi.Optimizer)
println("OBJECTIVE VALUE, Case 1, with Benders = ", minimum(UB_hist)) #FEASIBILITY ISSUE AFTER 70 ITERATIONS

# Case 1: 4 candidate line corridors, 3-6 lines per corridor
m, inputs = run_genx_case!((@__DIR__)*"/Simple_four_bus_DC_OPF_v2/", Gurobi.Optimizer, tight_bigM = true)
println("OBJECTIVE VALUE, Case 1, no Benders = ", objective_value(m)) #REACHES TRUE SOLUTION

inputs, UB_hist = run_genx_case!((@__DIR__)*"/Simple_four_bus_DC_OPF_v2_Benders/", Gurobi.Optimizer, tight_bigM = true)
println("OBJECTIVE VALUE, Case 1, with Benders = ", minimum(UB_hist)) # Reaches solution at 113 iterations of 17500
# NOTE: Benders is set up to run a relaxed version to generate initial cuts. This relaxed version
# does reach the solution of 17000, but when the variables are unrelaxed, the lower bound becomes
# invalid at some point and converges instead to 17500


########### Case 3: 6 candidate line corridors, 12 lines per corridor ###########
m, inputs = run_genx_case!((@__DIR__)*"/Simple_four_bus_DC_OPF_v3/", Gurobi.Optimizer)
println("OBJECTIVE VALUE, Case 1, no Benders = ", objective_value(m)) #REACHES TRUE SOLUTION

inputs, UB_hist = run_genx_case!((@__DIR__)*"/Simple_four_bus_DC_OPF_v3_Benders/", Gurobi.Optimizer)
println("OBJECTIVE VALUE, Case 1, with Benders = ", minimum(UB_hist)) #FEASIBILITY ISSUE AFTER 97 ITERATIONS

# Case 1: 4 candidate line corridors, 3-6 lines per corridor
m, inputs = run_genx_case!((@__DIR__)*"/Simple_four_bus_DC_OPF_v3/", Gurobi.Optimizer, tight_bigM = true)
println("OBJECTIVE VALUE, Case 1, no Benders = ", objective_value(m)) #REACHES TRUE SOLUTION

inputs, UB_hist = run_genx_case!((@__DIR__)*"/Simple_four_bus_DC_OPF_v3_Benders/", Gurobi.Optimizer, tight_bigM = true)
println("OBJECTIVE VALUE, Case 1, with Benders = ", minimum(UB_hist)) # Reaches solution at 450 iterations of 17147. LB at iteration 450 was 17250, while the LB at iteration 449 was 17147
# NOTE: Benders is set up to run a relaxed version to generate initial cuts. This relaxed version
# does reach the solution of 17000, but when the variables are unrelaxed, the lower bound becomes
# invalid at some point and converges instead to 17500
