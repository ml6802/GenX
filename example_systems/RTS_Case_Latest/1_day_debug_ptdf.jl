ENV["GENX_PRECOMPILE"] = "false"

using Revise
using JuMP
using GenX
using PowerSystemsInvestmentsPortfolios
using Gurobi
using TimeSeries
using CSV
using DataFrames
using Dates
using InfrastructureSystems
using PowerSystems
const PSIP = PowerSystemsInvestmentsPortfolios
const IS = InfrastructureSystems
const PSY = PowerSystems
using Plots
import Pkg
using Distributed, ClusterManagers
using Random

# Load in portfolio
include((@__DIR__)*"/load_portfolio.jl")
# Load in functions for downscaling
include((@__DIR__)*"/../convert_input_dict_reconductoring.jl")
# Load in functions for adding candidate lines
include((@__DIR__)*"/load_candidate_line_functions.jl")

# Set internal portfolio data for use in GenX
p.internal.ext["Rep_Periods"] = 1
p.internal.ext["Timesteps_per_Rep_Period"] = 6
p.internal.ext["hours_per_subperiod"] = 6
p.internal.ext["sub_weights"] = [8784 for i in 1:p.internal.ext["Rep_Periods"]] 
add_om_costs(p)

# Build map of buses to zones; used in downscaling
buses = collect(get_components(Bus, p.base_system))
zones = []
zone_map = Dict{Int, Int}()
for i in 1:length(buses)
    if buses[i].area.name == "area1"
        push!(zones, 1)
        zone_map[i] = 1
    elseif buses[i].area.name == "area2"
        push!(zones, 2)
        zone_map[i] = 2
    elseif buses[i].area.name == "area3"
        push!(zones, 3)
        zone_map[i] = 3
    else
        error()
    end
end

# Load in settings
genx_settings = GenX.get_settings_path(case, "genx_settings.yml") # Settings YAML file path
writeoutput_settings = GenX.get_settings_path(case, "output_settings.yml") # Write-output settings YAML file path
mysetup = GenX.configure_settings(genx_settings, writeoutput_settings) # mysetup dictionary stores settings and GenX-specific parameters

# Make sure certain parameters are set
mysetup["ParameterScale"] = 0
mysetup["DC_OPF"] = 1
mysetup["ptdf"] = 0
mysetup["bilinear"] = 0
mysetup["disaggregate"] = 0
mysetup["unfix_slacks"] = 0
mysetup["SOS1"] = 0
settings_path = GenX.get_settings_path(case)    
mysetup["settings_path"] = settings_path;
mysetup["NetworkExpansion"] = 1
mysetup["Benders"] = 0

node_names = ["Carew", "Chase", "Carrel", "Carter", "Cabot", "Bajer", "Baker", "Baffin", "Cabell", "Caine", "Camus", "Bach", "Bain", "Barlow", "Banks", "Balch", "Alger", "Alber", "Alder", "Avery", "Aiken"]

# Split node names by initial letter (A, B, C)
a_node_names = filter(n -> startswith(n, "A"), node_names)
b_node_names = filter(n -> startswith(n, "B"), node_names)
c_node_names = filter(n -> startswith(n, "C"), node_names)

# Set a reproducible seed (outside the function)
function sample_four(names::AbstractVector{<:AbstractString})
    @assert length(names) >= 3 "Need at least 4 names (got $(length(names)))"
    idxs = sort(randperm(length(names))[1:4])
    return collect(names[idxs])
end
node_name_dict = Dict('A' => a_node_names, 'B' => b_node_names, 'C' => c_node_names)
techs = collect(get_technologies(ResourceTechnology, p))

Random.seed!(1234)
for i in 1:length(techs)
    t = techs[i]
    if length(t.region) > 1
        old_region_list = t.region
        new_region_list = PSIP.RegionTopology[]
        key = t.region[1].name[1]
        node_name_vector = node_name_dict[key]
        new_nodes = sample_four(node_name_vector)
        for name in new_nodes
            for n in old_region_list
                if n.name == name
                    push!(new_region_list, n)
                    break
                end 
            end
        end
        @assert length(new_region_list) >=1
        t.region = new_region_list
    end
end

myinputs = GenX.load_inputs(mysetup, case, p)

optimizer = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 7200, "MIPGap" => 1e-6)

# Add expected candidate line data
# also scales demands up by 4x
load_candidates_base(myinputs, 8784, demand_scale = 4)

GenX.expand_new_cap_resources_to_nodal!(myinputs, mysetup, p, "")
GenX.load_generators_variability!(mysetup, p, myinputs)

# Set additional inputs so it only solves for one week
myinputs["hours_per_subperiod"] = 6
myinputs["INTERIOR_SUBPERIODS"] = [i for i in 2:myinputs["hours_per_subperiod"]]
myinputs["T"] = 6


# myinputs["pD"] = myinputs["pD"][2000:end, :]
# myinputs["pP_Max"] = myinputs["pP_Max"][:, 2000:end]
# Portfolio contains no capacity or unit sizes
# For new capacity, set it to be 100 MW increments
# if haskey(mysetup, "IntegerInvestments")
#     if mysetup["IntegerInvestments"] == 1
#         for i in myinputs["NEW_CAP"]
#             resource = myinputs["RESOURCES"][i]
#             parent(resource)[:cap_size] = 200
#         end
#     end
# end
myinputs["IntegerInvestments"] = 1
mysetup["ptdf"] = 0
optimizer = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 180, "MIPGap" => 1e-4)
m = GenX.generate_model(mysetup, myinputs, optimizer)

optimize!(m)


mysetup["ptdf"] = 1
mptdf = GenX.generate_model(mysetup, myinputs, optimizer)


# for i in myinputs["NEW_CAP"]
#     fix(mptdf[:vCAP][i], value(m[:vCAP][i]), force = true)
# end

# # for i in myinputs["CANDIDATE_LINES"]
# #     fix(mptdf[:vNEW_TRANS_CAP_DECISION_INT][i], value(m[:vNEW_TRANS_CAP_DECISION_INT][i]), force = true)
# # end
# for i in 1:258
#     for j in 1:6
#         fix(mptdf[:vP][i, j], value(m[:vP][i, j]), force = true)
#     end
# end


optimize!(mptdf)





# test_inputs = Dict()
# pnet_map = [1 -1 0; 1 -1 0; 0 1 -1; 0 1 -1]
# bvals = [10, 20, 20, 30]

# test_inputs["pNet_Map"] = pnet_map
# test_inputs["pDC_OPF_coeff"] = bvals
# test_inputs["L"] = 4
# test_inputs["GenBus"] = [1, 2]
# test_inputs["pD"] = [0, 0, 150]


# function solve_btheta(inputs)
#     pnet_map = inputs["pNet_Map"]
#     bvals = inputs["pDC_OPF_coeff"]
#     L = inputs["L"]
#     pD = inputs["pD"]
#     B = size(pnet_map, 2)
#     gen_buses = inputs["GenBus"]
#     m = Model(Gurobi.Optimizer)

#     @variable(m, vFLOW[1:L])
#     @variable(m, vANGLE[1:B])
#     @variable(m, 100 >= vP[i in gen_buses]>=0)
#     @variable(m, slack[1:B] >=0)

#     @expression(m, einject[i in 1:B], 0 * slack[i])
#     for i in gen_buses
#         add_to_expression!(einject[i], vP[i])
#     end

#     for i in 1:B
#         add_to_expression!(einject[i], sum(inputs["pNet_Map"][l, i] * m[:vFLOW][l] for l in 1:L))
#     end

#     @constraint(m, [i in 1:B], slack[i] + einject[i] - pD[i] == 0)
#     @constraint(m, [l in 1:L], vFLOW[l] == bvals[l] * (sum(pnet_map[l, i] * vANGLE[i] for i in 1:B)))
#     @objective(m, Min, sum(slack) * 100 + 1 * sum(vP))

#     return m
# end

# function build_injections(inputs, m)
#     pnet_map = inputs["pNet_Map"]
#     bvals = inputs["pDC_OPF_coeff"]
#     L = inputs["L"]
#     pD = inputs["pD"]
#     B = size(pnet_map, 2)
#     gen_buses = inputs["GenBus"]
    
#     injections = -1 .* pD
#     for i in gen_buses
#         injections[i] += value(m[:vP][i])
#     end
#     return injections
# end

# function compute_flows(inputs, injections)
#     ptdf_test = GenX.calculate_ptdf_matrices(test_inputs, 1)
#     flows = zeros(inputs["L"])
#     pnet_map = inputs["pNet_Map"]
#     B = size(pnet_map, 2)
#     for l in 1:inputs["L"]
#         flows[l] = - sum(ptdf_test.data[i, l] * injections[i] for i in 1:B)
#     end
#     return flows
# end


# test_inputs = Dict()
# pnet_map = [1 -1 0; 1 -1 0; 0 1 -1; 0 1 -1]
# bvals = [10, 20, 20, 30]

# test_inputs["pNet_Map"] = pnet_map
# test_inputs["pDC_OPF_coeff"] = bvals
# test_inputs["L"] = 4
# test_inputs["GenBus"] = [1, 2]
# test_inputs["pD"] = [0, 0, 150]

# mtest = solve_btheta(test_inputs)
# optimize!(mtest)

# injections = build_injections(test_inputs, mtest)
# ptdf_flows = compute_flows(test_inputs, injections)
# flow_sols = value.(mtest[:vFLOW])



# test_inputs = Dict()
# pnet_map = [1 -1 0 0; 1 -1 0 0; 0 1 -1 0; 1 -1 0 0; 0 0 1 -1; 0 0 1 -1]
# bvals = [10, 20, 20, 30, 30,  20]

# test_inputs["pNet_Map"] = pnet_map
# test_inputs["pDC_OPF_coeff"] = bvals
# test_inputs["L"] = 6
# test_inputs["GenBus"] = [1, 2, 3]
# test_inputs["pD"] = [50, 0, 150, 100]


# mtest = solve_btheta(test_inputs)
# optimize!(mtest)

# injections = build_injections(test_inputs, mtest)
# ptdf_flows = compute_flows(test_inputs, injections)
# flow_sols = value.(mtest[:vFLOW])




# test_inputs = deepcopy(myinputs)
# test_inputs["pDC_OPF_coeff"] ./= 100

# injections = value.(m[:eGenerationByZone][:, 1]) .- myinputs["pD"][1, :]
# ptdf_flows = compute_flows(test_inputs, injections)



# mtest = solve_btheta(test_inputs)
# optimize!(mtest)

# injections = build_injections(test_inputs, mtest)
# ptdf_flows = compute_flows(test_inputs, injections)
# flow_sols = value.(mtest[:vFLOW])

