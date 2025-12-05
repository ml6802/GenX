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
p.internal.ext["Timesteps_per_Rep_Period"] = 168
p.internal.ext["hours_per_subperiod"] = 168
p.internal.ext["sub_weights"] = [8784 for i in 1:p.internal.ext["Rep_Periods"]] 
add_om_costs(p)

techs = collect(get_technologies(SupplyTechnology, p))
# for (i, t) in enumerate(techs)
#     # if isa(t.operation_costs.variable, FuelCurve)
#     #     if t.operation_costs.fixed > 0#vom_cost.function_data.proportional_term == 0
#     #         #println(t.operation_costs.fixed, "   ", has_supplemental_attributes(ExistingCapacity, t))
#     #     end
#     # else 
#     #     if !has_supplemental_attributes(ExistingCapacity, t)
#     #         println(i, "  ", t.name)
#     #     end
#     # end
#     if !has_supplemental_attributes(ExistingCapacity, t)
#             println(i, "  ", t.name)
#         end
# end


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

optimizer = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 300, "MIPGap" => 1e-3)

# Add expected candidate line data
# also scales demands up by 4x
load_candidates_base(myinputs, 8784)

GenX.expand_new_cap_resources_to_nodal!(myinputs, mysetup, p, "")

# Set additional inputs so it only solves for one week
myinputs["hours_per_subperiod"] = 168
myinputs["INTERIOR_SUBPERIODS"] = [i for i in 2:myinputs["hours_per_subperiod"]]
myinputs["T"] = 168


# myinputs["pD"] = myinputs["pD"][2000:end, :]
# myinputs["pP_Max"] = myinputs["pP_Max"][:, 2000:end]
# Portfolio contains no capacity or unit sizes
# For new capacity, set it to be 100 MW increments
if haskey(mysetup, "IntegerInvestments")
    if mysetup["IntegerInvestments"] == 1
        for i in myinputs["NEW_CAP"]
            resource = myinputs["RESOURCES"][i]
            parent(resource)[:cap_size] = 200
        end
    end
end


# Build zonal inputs (this is a downscaling step)
z_inputs = build_zonal_inputs(myinputs, zone_map, 3)

###### ZONAL ######
zonal_setup = deepcopy(mysetup)
###### ZONAL ######
zonal_setup["unfix_slacks"] = 0
zonal_setup["NetworkExpansion"] = 1
zonal_setup["IntegerInvestments"] = 1
zonal_setup["DC_OPF"] = 0

# Solve zonal model
mz = run_zonal_model!(z_inputs, zonal_setup, optimizer)

new_vre = [0.]
new_thermal = [0.]
for i in z_inputs["NEW_CAP"]
    resource = z_inputs["RESOURCES"][i]
    # if isa(resource, GenX.Vre)
    #     println(i)
    # end
    val = value(mz[:vCAP][i])
    if isa(resource, GenX.Thermal)
        new_thermal[1] += val
    elseif isa(resource, GenX.Vre)
        new_vre[1] += val
    else
        println("RESOURCES IS OF TYPE $(typeof(resource))")
    end
end

println("TOTAL NEW THERMAL = ", new_thermal[1])
println("TOTAL NEW VRE = ", new_vre[1])


GenX.save_zonal_capacity_results!(mz, myinputs, z_inputs)

if haskey(mysetup, "IntegerInvestments")
    if mysetup["IntegerInvestments"] == 1
        for i in myinputs["NEW_CAP"]
            resource = myinputs["RESOURCES"][i]
            parent(resource)[:cap_size] = 200
        end
    end
end

n2z_map = zone_map
num_zones = 3
# build the nodal inputs
n_inputs = build_nodal_inputs(myinputs, n2z_map, num_zones)

nodal_setup = deepcopy(mysetup)
nodal_setup["DC_OPF"] = 1
nodal_setup["bilinear"] = 0
nodal_setup["unfix_slacks"] = 0
nodal_setup["NetworkExpansion"] = 1
nodal_setup["IntegerInvestments"] = 1

# add to the nodal inputs the interzonal transmission time series
add_interzonal_data!(z_inputs, n_inputs)

println("RUNNING MODEL 1")
nodal_setup["bilinear"] = 0
nodal_setup["unfix_slacks"] = 0
nodal_setup["ptdf"] = 0
# solve nodal models
# m1 = GenX.generate_model(nodal_setup, n_inputs[1], optimizer)
m1 = build_nodal_resolution_model(nodal_setup, n_inputs[1], optimizer)

set_nodal_capacity_builds(n_inputs[1], m1)

optimize!(m1)
println(objective_value(m1))
for v in m1[:vNEW_TRANS_CAP_DECISION_INT]
    if value(v) > 0
        println(v, "   ", value(v))
    end
end

for v in m1[:vCAP]
    if value(v) > 0
        println(v, "  ", value(v))
    end
end

for i in n_inputs[1]["CAN_RETIRE_LINES"]
    println(n_inputs[1]["existing_to_cand_map"][i])
end

nodal_setup["ptdf"] = 1
# solve nodal models
# m1 = GenX.generate_model(nodal_setup, n_inputs[1], optimizer)
m1pb = build_nodal_resolution_model(nodal_setup, n_inputs[1], optimizer)

for i in n_inputs[1]["NEW_CAP"]
    fix(m1p[:vCAP][i], value(m1[:vCAP][i]), force = true)
end

for i in n_inputs[1]["CANDIDATE_LINES"]
    fix(m1p[:vNEW_TRANS_CAP_DECISION_INT][i], value(m1[:vNEW_TRANS_CAP_DECISION_INT][i]), force = true)
end
for i in 1:86
    for j in 1:168
        fix(m1p[:vP][i, j], value(m1[:vP][i, j]), force = true)
    end
end

set_nodal_capacity_builds(n_inputs[1], m1p)

optimize!(m1p)
println(objective_value(m1p))
for v in m1p[:vNEW_TRANS_CAP_DECISION_INT]
    if value(v) > 0
        println(v, "   ", value(v))
    end
end

for v in m1p[:vCAP]
    if value(v) > 0
        println(v, "  ", value(v))
    end
end

nodal_setup["bilinear"] = 1
m1pb = build_nodal_resolution_model(nodal_setup, n_inputs[1], optimizer)

for i in n_inputs[1]["NEW_CAP"]
    fix(m1pb[:vCAP][i], value(m1[:vCAP][i]), force = true)
end

for i in n_inputs[1]["CANDIDATE_LINES"]
    fix(m1pb[:vNEW_TRANS_CAP_DECISION_INT][i], value(m1[:vNEW_TRANS_CAP_DECISION_INT][i]), force = true)
end

optimize!(m1pb)

benders_settings_path = GenX.get_settings_path(case, "benders_settings.yml")
mysetup_benders = GenX.configure_benders(benders_settings_path) 
nodal_setup = merge(mysetup_benders, nodal_setup)

nodal_setup["Benders"] = 1
nodal_setup["bilinear"] = 1
nodal_setup["ptdf"] = 1
myinputs_decomp = GenX.separate_inputs_subperiods(n_inputs[1]);
benders_inputs = GenX.generate_benders_inputs(nodal_setup,n_inputs[1],myinputs_decomp)
planning_problem1, planning_sol1, operational_sol1, LB_hist1,UB_hist1, cpu_time,feasibility_hist1, build_decisions1  = GenX.benders(benders_inputs,nodal_setup,myinputs);


mysetup["bilinear"] = 1
optimizer = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 300, "MIPGap" => 1e-4)
mb = GenX.generate_model(mysetup, myinputs, optimizer)





m2 = build_nodal_resolution_model(nodal_setup, n_inputs[2], optimizer)

set_nodal_capacity_builds(n_inputs[2], m2)

optimize!(m2)

m3 = build_nodal_resolution_model(nodal_setup, n_inputs[3], optimizer)

set_nodal_capacity_builds(n_inputs[3], m3)

optimize!(m3)

zonal_objective = objective_value(mz)
nodal_objective = objective_value(m1) + objective_value(m2) + objective_value(m3)
println("ZONAL OBJECTIVE = ", zonal_objective)
println("NODAL OBJECTIVE = ", nodal_objective)

println("Number new builds = ", sum(value.(m1[:vNEW_TRANS_CAP_DECISION_INT])) + sum(value.(m2[:vNEW_TRANS_CAP_DECISION_INT])) + sum(value.(m3[:vNEW_TRANS_CAP_DECISION_INT])))







# Save transmisison line info
new_transmission_builds_df = DataFrame()
new_transmission_builds_df[!, "LINES"] = [i for i in 1:myinputs["L"]]
reconductor_lines_low = zeros(myinputs["L"])
reconductor_lines_high = zeros(myinputs["L"])
new_lines = zeros(myinputs["L"])

for l in z_inputs["CANDIDATE_LINES"]
    z2l_map = z_inputs["z2l_map"]
    if value(mz[:vNEW_TRANS_LINES][l]) == 1
        new_lines[z2l_map[l]] = 1
    end
end
models = [m1, m2, m3]
for i in 1:num_zones
    n_input = n_inputs[i]
    l2l_map = n_input["l2l_map_rev"]
    for l in n_input["CANDIDATE_LINES"]
        if value(models[i][:vNEW_TRANS_CAP_DECISION_INT][l]) == 1
            new_lines[l2l_map[l]] = 1
        end
    end
    for l in n_input["RECONDUCTOR_LINES"]
        if value(models[i][:vRECONDUCTOR_SLACK_LOW][l]) > 1e-4
            reconductor_lines_low[l2l_map[l]] = 1
        end
        if value(models[i][:vRECONDUCTOR_SLACK_HIGH][l]) > 1e-4
            reconductor_lines_high[l2l_map[l]] = 1
        end
    end
end
new_transmission_builds_df[!, "NEW_LINES"] = new_lines
new_transmission_builds_df[!, "RECONDUCTOR_LOW"] = reconductor_lines_low
new_transmission_builds_df[!, "RECONDUCTOR_HIGH"] = reconductor_lines_high

CSV.write((@__DIR__)*"/transmission_downscaling_results.csv", new_transmission_builds_df)



new_gen_cap_df = DataFrame()
new_gen_cap_df[!, "Generators"] = [i for i in 1:myinputs["G"]]
generator_names = []
generator_nodes = []
generator_node_idx = []

region_to_index = myinputs["region_to_index"]
for i in 1:length(myinputs["RESOURCES"])
    r = myinputs["RESOURCES"][i]
    name = GenX.resource_name(r)
    region = GenX.region(r)
    node_name = region.name
    region_idx = region.id
    bus_idx = region_to_index[region_idx]
    push!(generator_names, name)
    push!(generator_nodes, node_name)
    push!(generator_node_idx, bus_idx)
end
new_gen_cap_df[!, "NAME"] = generator_names
new_gen_cap_df[!, "NODE"] = generator_nodes
new_gen_cap_df[!, "NODE_NUMBER"] = generator_node_idx
new_cap_results = zeros(myinputs["G"])

for i in 1:num_zones
    n_input = n_inputs[i]
    n2g_map = n_input["n2g_map"]
    for j in n_input["NEW_CAP"]
        if value(models[i][:vCAP][j]) > 0 
            new_cap_results[n2g_map[j]] = value(models[i][:vCAP][j]) * GenX.cap_size(n_input["RESOURCES"][j])
        end
    end
end
new_gen_cap_df[!, "NEW_CAP"] = new_cap_results

CSV.write((@__DIR__)*"/new_cap_downscaling_results.csv", new_transmission_builds_df)


# Save new build capacities





# plot results
using PlasmoData, PlasmoDataPlots
fadjlist = z_inputs["adj_list"]
dg = DataGraph{Int, Any, Any, Any, Matrix{Any}, Matrix{Any}}()
for i in 1:73
    add_node!(dg, i)
    if zone_map[i] == 1
        add_node_data!(dg, i, 1, "partition")
        add_node_data!(dg, i, "red", "color")
    elseif zone_map[i] == 2
        add_node_data!(dg, i, 2, "partition")
        add_node_data!(dg, i, "orange", "color")
    else
        add_node_data!(dg, i, 3, "partition")
        add_node_data!(dg, i, "blue", "color")
    end
    #add_node_data!(dg, i, part9[i], "partition_metis")
    #add_node_data!(dg, i, my_colors[part9[i]], "color")
    add_node_data!(dg, i, 6, "nodesize")
end
for (src, dst) in fadjlist
    add_edge!(dg, src, dst)
    add_edge_data!(dg, src, dst, "black", "new_build")
    add_edge_data!(dg, src, dst, 2, "linewidth_new_build")
    add_edge_data!(dg, src, dst, "black", "retirement")
    add_edge_data!(dg, src, dst, 2, "linewidth_retirement")
    add_edge_data!(dg, src, dst, "black", "reconductored")
    add_edge_data!(dg, src, dst, 2, "linewidth_reconductor")
    add_edge_data!(dg, src, dst, "black", "status")
    add_edge_data!(dg, src, dst, 2, "linewidth_status")
end



plot_graph(dg, nodecolor = get_node_data(dg, "color"), nodesize = 6, xdim = 500, ydim = 500, save_fig = false, linewidth=2, linecolor = "black", fig_name = (@__DIR__)*"/zonal_system.png")
add_node_data!(dg, 13, -0.52, "x_positions")
add_node_data!(dg, 13, 0.16, "y_positions")
plot_graph(dg, nodecolor = get_node_data(dg, "color"), nodesize = 6, xdim = 500, ydim = 500, save_fig = false, linewidth=2, linecolor = "black", fig_name = (@__DIR__)*"/zonal_system.png")

plot_graph(dg, nodecolor = "grey", nodesize = 6, xdim = 500, ydim = 500, save_fig = false, linewidth=2, linecolor = "black", fig_name = (@__DIR__)*"/zonal_system_plain.png")



l2z_map = z_inputs["l2z_map"]
retire_lines = [z_inputs["existing_to_cand_map"][j] for j in z_inputs["CAN_RETIRE_LINES"]]
for k in keys(l2z_map)
    new_line = l2z_map[k]
    #add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "white", "zonal_line")
    #add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "chartreuse", "new_build")
    #add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], 8, "linewidth")
    if new_line in z_inputs["CANDIDATE_LINES"]
        if value(mz[:vNEW_TRANS_LINES][new_line, 1]) == 1
            add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "red", "new_build")
            add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], 5, "linewidth")
            if new_line in retire_lines
                add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "orange", "status")
                add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], 5, "linewidth_status")
            else
                add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "red", "status")
                add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], 5, "linewidth_status")
            end
        end
    end
end


models = [m1, m2, m3]

all_cap_values = vcat([value(i) for i in m1[:vCAP] if value(i) >0], [value(i) for i in m2[:vCAP] if value(i) >0], [value(i) for i in m3[:vCAP] if value(i) >0])

max_cap = maximum(all_cap_values)

for i in 1:num_zones
    n_input = n_inputs[i]
    l2l_map = n_input["l2l_map"]
    model = models[i]
    retire_lines = [n_input["existing_to_cand_map"][j] for j in n_input["CAN_RETIRE_LINES"]]
    for k in keys(l2l_map)
        old_line = k
        new_line = l2l_map[k]
        if new_line in n_input["CANDIDATE_LINES"]
            if value(models[i][:vNEW_TRANS_CAP_DECISION_INT][new_line, 1]) == 1
                add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "red", "new_build")
                add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], 5, "linewidth")
                if new_line in retire_lines
                    add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "orange", "status")
                    add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], 5, "linewidth_status")
                else
                    add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "red", "status")
                    add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], 5, "linewidth_status")
                end
            end
        end
        if new_line in n_input["RECONDUCTOR_LINES"]
            if value(model[:vRECONDUCTOR_SLACK_LOW][new_line]) > 0
                if get_edge_data(dg, fadjlist[k][1], fadjlist[k][2], "status") == "red"
                    add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "purple", "status")
                    add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], 5, "linewidth_status")
                else
                    add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "teal", "status")
                    add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], 5, "linewidth_status")
                end
            end
        end
    end
end

new_vre = [0.]
new_thermal = [0.]
for i in 1:num_zones
    n_input = n_inputs[i]
    n2n_map = n_input["n2n_map"]
    n2n_map_back = Dict()
    for j in keys(n2n_map)
        n2n_map_back[n2n_map[j]] = j
    end
    vcap_nodes = models[i][:vCAP].axes[1]
    for j in vcap_nodes
        #println(j)
        if value(models[i][:vCAP][j]) >= 1

            val = value(models[i][:vCAP][j])
            resource = n_input["RESOURCES"][j]

            println(parent(resource)[:resource])
            genx_zone = parent(resource)[:zone]
            node = n2n_map_back[genx_zone]
            add_node_data!(dg, node, "black", "color")
            add_node_data!(dg, node, 1 + 9 * (val / max_cap), "nodesize")
            if isa(resource, GenX.Thermal)
                new_thermal[1] += val
            elseif isa(resource, GenX.Vre)
                new_vre[1] += val
            else
                println("RESOURCES IS OF TYPE $(typeof(resource))")
            end
        end
    end
end



plot_graph(dg, nodecolor = get_node_data(dg, "color"), nodesize = get_node_data(dg, "nodesize"), xdim = 500, ydim = 500, linewidth = get_edge_data(dg, "linewidth_status"), linecolor = get_edge_data(dg, "status"), save_fig = false, fig_name = (@__DIR__)*"/zonal_nodal_builds_RTS_repweek_benders.png")
