a=1

using Revise

using GenX
using Gurobi
using JuMP

# True solution in all cases is 17000
# There are three different cases with different network structures
# Each case starts with virtually no transmission. Case 1 has four possible line
# corridors with 3-6 lines per corridor. Case 2 has six possible line corridors 
# with each corridor having 6 possible lines constructed on that corridor (each line 
# having a size of 50 MW). Case 3 is the same as case 2, but with 12 candidate lines
# and each line have a sze of 25 MW

# I also played with the big M value to see if it helped convergence. I cannot say it
# improved convergence, but it can be set using the `tight_bigM` key word argument
# passed to the `run_genx_case` function
a=1

m, inputs, setup = run_genx_case!((@__DIR__)*"/Simple_four_bus_DC_OPF_v10/", Gurobi.Optimizer)

optimizer = optimizer_with_attributes(Gurobi.Optimizer, "OutputFlag" => 1)

n2z_map = Dict(1 => 1, 2 => 1, 3 => 2, 4 => 2)

num_zones = 2

z_inputs = build_zonal_inputs(inputs, n2z_map, num_zones)

mz = GenX.generate_model(setup, z_inputs, optimizer)

run_zonal_model!(z_inputs, setup, optimizer)

n_inputs = build_nodal_inputs(inputs, n2z_map, num_zones)

add_interzonal_data!(z_inputs, n_inputs)

m1 = GenX.generate_model(setup, n_inputs[1], optimizer)

optimize!(m1)

m2 = GenX.generate_model(setup, n_inputs[2], optimizer)

optimize!(m2)




########### Case 1: 4 candidate line corridors, 3-6 lines per corridor ############
#m, inputs = run_genx_case!((@__DIR__)*"/Simple_four_bus_DC_OPF_v10/partitioned_systems/zone_2", Gurobi.Optimizer)
ma, inputsa, settingsa = run_genx_case!((@__DIR__)*"/Simple_four_bus_DC_OPF_v10/partitioned_systems/aggregated/", Gurobi.Optimizer)

# add to corresponding loads in each zone
# add generators to connecting areas

m1, inputs1, settings1 = run_genx_case!((@__DIR__)*"/Simple_four_bus_DC_OPF_v10/partitioned_systems/zone_1/", Gurobi.Optimizer)
m2, inputs2, settings2 = run_genx_case!((@__DIR__)*"/Simple_four_bus_DC_OPF_v10/partitioned_systems/zone_2/", Gurobi.Optimizer)
obj_func = objective_function(m2)
vstart = m2[:vStartFuel]
vP = m2[:vP]
vp2_fix = [85, 85, 100,100]
#vp2_fix = [85,85,95,95]
vp3_fix = [100, 100, 100, 100]
#vp3_fix = [100, 100, 100, 100]

for i in 2:3
    for j in 1:4
        obj_func.terms[vstart[i, j]] = 0.
    end
end

for j in 1:4
    JuMP.fix(vP[2, j], vp2_fix[j], force = true)
    JuMP.fix(vP[3, j], vp3_fix[j], force = true)
end

optimize!(m2)

println("OBJECTIVE VALUE, Case 1, no Benders = ", objective_value(m)) #REACHES TRUE SOLUTION

