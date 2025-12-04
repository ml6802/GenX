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

# Pkg.activate("/home/ml6802/GenX")
# include("/home/ml6802/GenX/src/GenX.jl")

include((@__DIR__)*"/load_portfolio.jl")
include((@__DIR__)*"/../convert_input_dict.jl")

p.internal.ext["Rep_Periods"] = 1
p.internal.ext["Timesteps_per_Rep_Period"] = 168
p.internal.ext["hours_per_subperiod"] = 168
p.internal.ext["sub_weights"] = [8784/52 for i in 1:1]
#p.internal.ext["sub_weights"] = [8784/2190 for i in 1:1]
# p.internal.ext["Timesteps_per_Rep_Period"] = 3528
# p.internal.ext["hours_per_subperiod"] = 3528
# p.internal.ext["sub_weights"] = [8784/2 for i in 1:1]
# p.internal.ext["sub_weights"] = [8784/2 for i in 1:1]
# p.internal.ext["sub_weights"] = [8784/2 for i in 1:1]

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

using Graphs, Metis
g = SimpleGraph(length(buses))
sys = p.base_system
arcs = collect(get_components(Arc, sys))
bus_to_idx_map = Dict(buses[i] => i for i in 1:length(buses))
buses1 = [buses[i] for i in 1:length(buses) if buses[i].area.name == "area1"]
buses2 = [buses[i] for i in 1:length(buses) if buses[i].area.name == "area2"]
buses3 = [buses[i] for i in 1:length(buses) if buses[i].area.name == "area3"]

g1 = SimpleGraph(length(buses1))
g2 = SimpleGraph(length(buses2))
g3 = SimpleGraph(length(buses3))
bus_map1 = Dict()
bus_map2 = Dict()
bus_map3 = Dict()
for i in 1:length(buses)
    if buses[i].area.name == "area1"
        bus_map1[i] = length(bus_map1) + 1
    elseif buses[i].area.name == "area2"
        bus_map2[i] = length(bus_map2) + 1
    else
        bus_map3[i] = length(bus_map3) + 1
    end
end
bus_map1_rev = Dict(bus_map1[key] => key for key in keys(bus_map1))
bus_map2_rev = Dict(bus_map2[key] => key for key in keys(bus_map2))
bus_map3_rev = Dict(bus_map3[key] => key for key in keys(bus_map3))

for i in 1:length(arcs)
    bus_from = bus_to_idx_map[arcs[i].from]
    bus_to = bus_to_idx_map[arcs[i].to]
    add_edge!(g, bus_from, bus_to)
    if arcs[i].from.area.name == "area1" && arcs[i].to.area.name == "area1"
        add_edge!(g1, bus_map1[bus_from], bus_map1[bus_to])
    elseif arcs[i].from.area.name == "area2" && arcs[i].to.area.name == "area2"
        add_edge!(g2, bus_map2[bus_from], bus_map2[bus_to])
    elseif arcs[i].from.area.name == "area3" && arcs[i].to.area.name == "area3"
        add_edge!(g3, bus_map3[bus_from], bus_map3[bus_to])
    end
end

part9 = Metis.partition(g, 9, alg = :RECURSIVE)
part3_1 = Metis.partition(g1, 3, alg = :RECURSIVE)
part3_2 = Metis.partition(g2, 3, alg = :RECURSIVE)
part3_3 = Metis.partition(g3, 3, alg = :RECURSIVE)
part3_3[16] = 2
part9_subareas = zeros(Int, length(part9))
for i in 1:length(part3_1)
    part9_subareas[bus_map1_rev[i]] = part3_1[i]
end
for i in 1:length(part3_2)
    part9_subareas[bus_map2_rev[i]] = part3_2[i] + 3
end
for i in 1:length(part3_3)
    part9_subareas[bus_map3_rev[i]] = part3_3[i] + 6
end

using Colors
my_colors = distinguishable_colors(9)






# # plot results
# using PlasmoData, PlasmoDataPlots
# fadjlist = z_inputs["adj_list_cand"]
# dg = DataGraph{Int, Any, Any, Any, Matrix{Any}, Matrix{Any}}()
# for i in 1:73
#     add_node!(dg, i)
#     if zone_map[i] == 1
#         add_node_data!(dg, i, 1, "partition")
#         add_node_data!(dg, i, "red", "color")
#     elseif zone_map[i] == 2
#         add_node_data!(dg, i, 2, "partition")
#         add_node_data!(dg, i, "orange", "color")
#     else
#         add_node_data!(dg, i, 3, "partition")
#         add_node_data!(dg, i, "blue", "color")
#     end
#     add_node_data!(dg, i, part9[i], "partition_metis")
#     add_node_data!(dg, i, my_colors[part9[i]], "color")
#     add_node_data!(dg, i, part9_subareas[i], "partition_metis_subareas")
#     add_node_data!(dg, i, my_colors[part9_subareas[i]], "color_subareas")
#     add_node_data!(dg, i, 6, "nodesize")
# end
# for (src, dst) in fadjlist
#     add_edge!(dg, src, dst)
#     add_edge_data!(dg, src, dst, "black", "new_build")
#     add_edge_data!(dg, src, dst, 2, "linewidth")
#     add_edge_data!(dg, src, dst, "black", "new_build_monolithic")
#     add_edge_data!(dg, src, dst, 2, "linewidth_monolithic")
#     add_edge_data!(dg, src, dst, "black", "zonal_line")
# end



# plot_graph(dg, nodecolor = get_node_data(dg, "color"), nodesize = 6, xdim = 500, ydim = 500, save_fig = false, linewidth=2, linecolor = "black", fig_name = (@__DIR__)*"/zonal_system.png")
# add_node_data!(dg, 13, -0.52, "x_positions")
# add_node_data!(dg, 13, 0.16, "y_positions")
# plot_graph(dg, nodecolor = get_node_data(dg, "color_subareas"), nodesize = 6, xdim = 500, ydim = 500, save_fig = false, linewidth=2, linecolor = "black", fig_name = (@__DIR__)*"/zonal_system.png")

# zone_map_metis = Dict{Int, Int}()
# for i in 1:length(buses)
#     zone_map_metis[i] = part9_subareas[i]
# end







benders_settings_path = GenX.get_settings_path(case, "benders_settings.yml")
mysetup_benders = GenX.configure_benders(benders_settings_path) 

genx_settings = GenX.get_settings_path(case, "genx_settings.yml") # Settings YAML file path
writeoutput_settings = GenX.get_settings_path(case, "output_settings.yml") # Write-output settings YAML file path
mysetup = GenX.configure_settings(genx_settings, writeoutput_settings) # mysetup dictionary stores settings and GenX-specific parameters
mysetup["ParameterScale"] = 0

mysetup["DC_OPF"] = 1
myinputs = GenX.load_inputs(mysetup, case, p)
mysetup["ptdf"] = 0
mysetup["bilinear"] = 0
mysetup["disaggregate"] = 0
mysetup["unfix_slacks"] = 0
mysetup["SOS1"] = 0
mysetup = merge(mysetup,mysetup_benders);

settings_path = GenX.get_settings_path(case)    
mysetup["settings_path"] = settings_path;

# myinputs["pTrans_Max"] .*= 2
myinputs["pTrans_Max"][[5,23,24,70,75]] .*= 1/50
#myinputs["pD"] .*= 1
# myinputs["Voll"] .*= 10

L = myinputs["L"]
L_cand = myinputs["L"]
myinputs["L_cand"] = L_cand
myinputs["Z_cand"] = myinputs["Z"]
myinputs["pNet_Map_cand"] = copy(myinputs["pNet_Map"])
myinputs["pDC_OPF_coeff_cand"] = copy(myinputs["pDC_OPF_coeff"]) .* 2
myinputs["Line_Angle_Limit"] = [6.282 for i in 1:L]
myinputs["Line_Angle_Limit_cand"] = myinputs["Line_Angle_Limit"]

# one level of expansion for each line
# equal to half of existing capacity for any given line pTrans_Max
myinputs["Line_Reinforcement_Cap_Size"] = [i for i in myinputs["pTrans_Max"]] .* 1.5
myinputs["Max_Trans_Cap"] = [2 for i in myinputs["pTrans_Max"]]
myinputs["pMax_Line_Reinforcement"] = [myinputs["Line_Reinforcement_Cap_Size"][i] * myinputs["Max_Trans_Cap"][i] for i in 1:L]
myinputs["pTrans_Max_Possible"] = myinputs["pTrans_Max"] .+ myinputs["pMax_Line_Reinforcement"]

EXPANSION_LEVELS = Dict{Int, Vector}()
for i in 1:L_cand
    EXPANSION_LEVELS[i] = (0:1:myinputs["Max_Trans_Cap"][i])
end
#EXPANSION_LEVELS = [[1] for i in 1:L_cand] # needs to be a dictionary
EXPANSION_LINES = [i for i in 1:L_cand]

myinputs["EXPANSION_LINES"] = EXPANSION_LINES
myinputs["EXPANSION_LEVELS"] = EXPANSION_LEVELS

lines = collect(get_technologies(TransmissionTechnology, p));
myinputs["pC_Line_Reinforcement"] = zeros(length(lines))

scale_factor = mysetup["ParameterScale"] == 1 ? GenX.ModelScalingFactor : 1

using Random
Random.seed!(1)
for i in 1:length(lines)
    distance = 60 * rand()
    cap_val = distance * 1200
    myinputs["pC_Line_Reinforcement"][i] = cap_val * (0.044) / (1 - (1 + 0.044)^(-60))
end
myinputs["hours_per_subperiod"] = 168
myinputs["INTERIOR_SUBPERIODS"] = [i for i in 2:myinputs["hours_per_subperiod"]]
myinputs["T"] = 168


mysetup["NetworkExpansion"] = 1
mysetup["Benders"] = 0

# go through candidate lines and remove duplicates
line_list_cand = Vector{Tuple}()
pNet_Map_cand = myinputs["pNet_Map_cand"]
for i in 1:size(pNet_Map_cand)[1]
    from_bus = findfirst(x -> x == 1, pNet_Map_cand[i, :])
    to_bus = findfirst(x -> x == -1, pNet_Map_cand[i, :])
    push!(line_list_cand, (from_bus, to_bus))
end

#zone_map = zone_map_metis
idx_to_keep = []
line_sizes = []
new_line_list_cand = []
for i in 1:length(line_list_cand)
    if line_list_cand[i] in new_line_list_cand
        if zone_map[line_list_cand[i][1]] != zone_map[line_list_cand[i][2]]
            println(myinputs["pTrans_Max"][i])
            println(i)
        end
        old_idx = findfirst(x -> x == line_list_cand[i], new_line_list_cand)
        line_sizes[old_idx] += myinputs["pTrans_Max"][i]
    elseif (line_list_cand[i][1], line_list_cand[i][2]) in new_line_list_cand
        @warn "Reverse Lines exist on the same corridor"
    else
        push!(idx_to_keep, i)
        if zone_map[line_list_cand[i][1]] != zone_map[line_list_cand[i][2]]
            println(myinputs["pTrans_Max"][i])
            println(i)
        end
        push!(line_sizes, myinputs["pTrans_Max"][i])
        push!(new_line_list_cand, line_list_cand[i])
    end
end


myinputs["pNet_Map_cand"] = myinputs["pNet_Map_cand"][idx_to_keep, :]
myinputs["L_cand"] = length(idx_to_keep)
L_cand = myinputs["L_cand"]
myinputs["pDC_OPF_coeff_cand"] = myinputs["pDC_OPF_coeff_cand"][idx_to_keep]
myinputs["Line_Angle_Limit_cand"] = myinputs["Line_Angle_Limit_cand"][idx_to_keep]
myinputs["Line_Reinforcement_Cap_Size"] = line_sizes .* 1.5#myinputs["Line_Reinforcement_Cap_Size"][idx_to_keep]
myinputs["Max_Trans_Cap"] = myinputs["Max_Trans_Cap"][idx_to_keep]
myinputs["pMax_Line_Reinforcement"] = myinputs["pMax_Line_Reinforcement"][idx_to_keep]
myinputs["pTrans_Max_Possible"] = myinputs["pTrans_Max_Possible"][idx_to_keep]
EXPANSION_LEVELS = Dict{Int, Vector}()
for i in 1:L_cand
    EXPANSION_LEVELS[i] = (0:1:myinputs["Max_Trans_Cap"][i])
end
myinputs["EXPANSION_LEVELS"] = EXPANSION_LEVELS
myinputs["EXPANSION_LINES"] = [i for i in 1:myinputs["L_cand"]]
#myinputs["pC_Line_Reinforcement"] = myinputs["pC_Line_Reinforcement"][idx_to_keep]


myinputs["pC_Line_Reinforcement"] = zeros(L_cand)

scale_factor = mysetup["ParameterScale"] == 1 ? GenX.ModelScalingFactor : 1

using Random
Random.seed!(1)
for i in 1:L_cand
    distance = 60 * rand()
    cap_val = distance * 1200
    myinputs["pC_Line_Reinforcement"][i] = cap_val * (0.044) / (1 - (1 + 0.044)^(-60))
end

GenX.build_expansion_information!(myinputs)

mysetup["bilinear"] = 0
optimizer = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 60, "MIPGap" => 5e-3)
m = GenX.generate_model(mysetup, myinputs, optimizer)

#optimize!(m)


mysetup["bilinear"] = 0
mysetup["zonal"] = "waterflow" # set for waterflow or dcopf
mysetup["nodal"] = "dcopf" # set for waterflow or dcopf
## stuff from zonal_to_nodal_solve.jl
if !(haskey(mysetup, "ptdf"))
    mysetup["ptdf"] = 0
end
if !(haskey(mysetup, "disaggregate"))
    mysetup["disaggregate"] = 0
end
if !(haskey(mysetup, "bilinear"))
    mysetup["bilinear"] = 0
end
if !(haskey(mysetup, "SOS1"))
    mysetup["SOS1"] = 0
end
if !(haskey(mysetup, "unfix_slacks"))
    mysetup["unfix_slacks"] = 0
end
if !(haskey(mysetup, "tight_bigM"))
    mysetup["tight_bigM"] = false
end
z_inputs = build_zonal_inputs(myinputs, zone_map, 3)

solver = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 400, "MIPGap" => 1e-4)
###### ZONAL ######
zonal_setup = deepcopy(mysetup)
#zonal_setup["unfix_slacks"] = 1
#zonal_setup["DC_OPF"] = 1

optimizer = solver
###### ZONAL ######
zonal_setup["unfix_slacks"] = 0
zonal_setup["NetworkExpansion"] = 1
zonal_setup["IntegerInvestments"] = 1
zonal_setup["DC_OPF"] = 0


mz = run_zonal_model!(z_inputs, zonal_setup, optimizer)

println("VNSE = ", sum(value.(mz[:vNSE])))
println("Num builds = ", sum(value.(mz[:vNEW_TRANS_LINES])))
println("vCAP = ", sum(value.(mz[:vCAP])))
println("voverproduction = ", sum(value.(mz[:vOverProduction])))


optimizer = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 180, "MIPGap" => 5e-3)

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
# solve nodal models
m1 = GenX.generate_model(nodal_setup, n_inputs[1], optimizer)

# optimize!(m1)







benders_settings_path = GenX.get_settings_path(case, "benders_settings.yml")
mysetup_benders = GenX.configure_benders(benders_settings_path) 

genx_settings = GenX.get_settings_path(case, "genx_settings.yml") # Settings YAML file path
writeoutput_settings = GenX.get_settings_path(case, "output_settings.yml") # Write-output settings YAML file path
mysetup = GenX.configure_settings(genx_settings, writeoutput_settings) # mysetup dictionary stores settings and GenX-specific parameters

mysetup["DC_OPF"] = 1
mysetup["ptdf"] = 0
mysetup["bilinear"] = 1
mysetup["disaggregate"] = 0
mysetup["unfix_slacks"] = 0
mysetup["SOS1"] = 0
mysetup = merge(mysetup,mysetup_benders);

settings_path = GenX.get_settings_path(case)    
mysetup["settings_path"] = settings_path;
mysetup["NetworkExpansion"] = 1
mysetup["Benders"] = 1
#mysetup["BD_integer_routine"] = 1
#mysetup["BD_warmstart_bilinear"] = 1

# mysetup["BD_Stab_Method"] = "int_level_set"


myinputs_decomp = GenX.separate_inputs_subperiods(n_inputs[1]);
# nodal_setup_Benders = deepcopy(nodal_setup)
# nodal_setup_Benders["Benders"] = 1
benders_inputs = GenX.generate_benders_inputs(mysetup,n_inputs[1],myinputs_decomp)




# 
planning_problem1, planning_sol1, operational_sol1, LB_hist1,UB_hist1, cpu_time,feasibility_hist1, build_decisions1  = GenX.benders(benders_inputs,mysetup,n_inputs[1]);

#CSV.write((@__DIR__)*"/1week_zone1_with_retirements_bilinear_only.csv", df)


df = DataFrame()
df[!, "UB"] = UB_hist1
df[!, "LB"] = LB_hist1
df[!, "TIME"] = cpu_time

#CSV.write((@__DIR__)*"/1week_zone1_with_retirements_bilinear_doublewarmstart.csv", df)



benders_settings_path = GenX.get_settings_path(case, "benders_settings.yml")
mysetup_benders = GenX.configure_benders(benders_settings_path) 

genx_settings = GenX.get_settings_path(case, "genx_settings.yml") # Settings YAML file path
writeoutput_settings = GenX.get_settings_path(case, "output_settings.yml") # Write-output settings YAML file path
mysetup = GenX.configure_settings(genx_settings, writeoutput_settings) # mysetup dictionary stores settings and GenX-specific parameters

mysetup["DC_OPF"] = 1
mysetup["ptdf"] = 0
mysetup["bilinear"] = 1
mysetup["disaggregate"] = 0
mysetup["unfix_slacks"] = 0
mysetup["SOS1"] = 0
mysetup = merge(mysetup,mysetup_benders);

settings_path = GenX.get_settings_path(case)    
mysetup["settings_path"] = settings_path;
mysetup["NetworkExpansion"] = 1
mysetup["Benders"] = 1
#mysetup["BD_integer_routine"] = 1
# mysetup["BD_Stab_Method"] = "int_level_set"


myinputs_decomp = GenX.separate_inputs_subperiods(n_inputs[1]);
# nodal_setup_Benders = deepcopy(nodal_setup)
# nodal_setup_Benders["Benders"] = 1
benders_inputs = GenX.generate_benders_inputs(mysetup,n_inputs[1],myinputs_decomp)
planning_problem1, planning_sol1, operational_sol1, LB_hist,UB_hist1, cpu_time,feasibility_hist1, build_decisions1  = GenX.benders(benders_inputs,mysetup,n_inputs[1]);

vals = [0.]
for k in keys(planning_sol1.values)
    if occursin("vNEW_TRANS_CAP", k)
        vals[1] += planning_sol1.values[k]
    end
end


myinputs_decomp = GenX.separate_inputs_subperiods(n_inputs[2]);
# nodal_setup_Benders = deepcopy(nodal_setup)
# nodal_setup_Benders["Benders"] = 1
benders_inputs = GenX.generate_benders_inputs(mysetup,n_inputs[2],myinputs_decomp)
planning_problem2, planning_sol2, operational_sol2, LB_hist,UB_hist2, cpu_time,feasibility_hist2, build_decisions2  = GenX.benders(benders_inputs,mysetup,n_inputs[2]);

myinputs_decomp = GenX.separate_inputs_subperiods(n_inputs[3]);
# nodal_setup_Benders = deepcopy(nodal_setup)
# nodal_setup_Benders["Benders"] = 1
benders_inputs = GenX.generate_benders_inputs(mysetup,n_inputs[3],myinputs_decomp)
planning_problem3, planning_sol3, operational_sol3, LB_hist,UB_hist3, cpu_time,feasibility_hist3, build_decisions3  = GenX.benders(benders_inputs,mysetup,n_inputs[3]);


if UB_hist1[end] < objective_value(m1)
    l2l_map = n_inputs[1]["l2l_map_cand"]
    for k in keys(l2l_map)
        old_line = k
        new_line = l2l_map[k]
        val1 = planning_sol1.values["vNEW_TRANS_CAP_DECISION_INT[$new_line,1]"]
        fix(m1[:vNEW_TRANS_CAP_DECISION_INT][new_line, 1], val1, force = true)
        val2 = planning_sol1.values["vNEW_TRANS_CAP_DECISION_INT[$new_line,2]"]
        fix(m1[:vNEW_TRANS_CAP_DECISION_INT][new_line, 2], val2, force = true)
        # end
    end
    optimize!(m1)
end
if UB_hist2[end] < objective_value(m2)
    l2l_map = n_inputs[2]["l2l_map_cand"]
    for k in keys(l2l_map)
        old_line = k
        new_line = l2l_map[k]
        val = planning_sol2.values["vNEW_TRANS_CAP_DECISION_INT[$new_line]"]
        fix(m2[:vNEW_TRANS_CAP_DECISION_INT][new_line, 1], val, force = true)
    end
    optimize!(m2)
end
if UB_hist3[end] < objective_value(m3)
    l2l_map = n_inputs[3]["l2l_map_cand"]
    for k in keys(l2l_map)
        old_line = k
        new_line = l2l_map[k]
        val = planning_sol3.values["vNEW_TRANS_CAP_DECISION_INT[$new_line]"]
        fix(m3[:vNEW_TRANS_CAP_DECISION_INT][new_line, 1], val, force = true)
    end
    optimize!(m3)
end

println("Zonal objective is : ", objective_value(mz))
println("Nodal objective is : ", objective_value(m1) + objective_value(m2) + objective_value(m3))


for i in 1:length(n_inputs[1]["adj_list_cand"])
    #println(value(m1[:vNEW_TRANS_CAP_DECISION_INT][i, 1]), "    ", planning_sol1.values["vNEW_TRANS_CAP_DECISION_INT[$i,1]"])
    println(value(m1[:vNEW_TRANS_CAP_DECISION_INT][i, 2]), "    ", planning_sol1.values["vNEW_TRANS_CAP_DECISION_INT[$i,2]"])
end














# plot results
using PlasmoData, PlasmoDataPlots
fadjlist = z_inputs["adj_list_cand"]
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
    add_node_data!(dg, i, part9[i], "partition_metis")
    add_node_data!(dg, i, my_colors[part9[i]], "color")
    add_node_data!(dg, i, 6, "nodesize")
end
for (src, dst) in fadjlist
    add_edge!(dg, src, dst)
    add_edge_data!(dg, src, dst, "black", "new_build")
    add_edge_data!(dg, src, dst, 2, "linewidth")
    add_edge_data!(dg, src, dst, "black", "new_build_monolithic")
    add_edge_data!(dg, src, dst, 2, "linewidth_monolithic")
    add_edge_data!(dg, src, dst, "black", "zonal_line")
end



plot_graph(dg, nodecolor = get_node_data(dg, "color"), nodesize = 6, xdim = 500, ydim = 500, save_fig = false, linewidth=2, linecolor = "black", fig_name = (@__DIR__)*"/zonal_system.png")
add_node_data!(dg, 13, -0.52, "x_positions")
add_node_data!(dg, 13, 0.16, "y_positions")
plot_graph(dg, nodecolor = get_node_data(dg, "color"), nodesize = 6, xdim = 500, ydim = 500, save_fig = false, linewidth=2, linecolor = "black", fig_name = (@__DIR__)*"/zonal_system.png")

plot_graph(dg, nodecolor = "grey", nodesize = 6, xdim = 500, ydim = 500, save_fig = false, linewidth=2, linecolor = "black", fig_name = (@__DIR__)*"/zonal_system_plain.png")



l2z_map = z_inputs["l2z_map_cand"]
for k in keys(l2z_map)
    new_line = l2z_map[k]
    add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "white", "zonal_line")
    if value(mz[:vNEW_TRANS_LINES][new_line, 1]) == 1
        add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "red", "new_build")
        add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], 5, "linewidth")
    end
end


models = [m1, m2, m3]
for i in 1:num_zones
    n_input = n_inputs[i]
    l2l_map = n_input["l2l_map_cand"]
    model = models[i]
    for k in keys(l2l_map)
        old_line = k
        new_line = l2l_map[k]
        if value(models[i][:vNEW_TRANS_CAP_DECISION_INT][new_line, 1]) == 1
            add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "red", "new_build")
            add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], 5, "linewidth")
        end
    end
end

for i in 1:num_zones
    n_input = n_inputs[i]
    n2n_map = n_input["n2n_map"]
    n2n_map_back = Dict()
    for j in keys(n2n_map)
        n2n_map_back[n2n_map[j]] = j
    end
    vcap_nodes = models[i][:vCAP].axes[1]
    for j in vcap_nodes
        println(j)
        if value(models[i][:vCAP][j]) > 0
            resource = n_input["RESOURCES"][j]
            println(parent(resource)[:resource])
            genx_zone = parent(resource)[:zone]
            node = n2n_map_back[genx_zone]
            add_node_data!(dg, node, "black", "color")
            add_node_data!(dg, node, 10, "nodesize")
            println(node)
        end
    end
end



plot_graph(dg, nodecolor = get_node_data(dg, "color"), nodesize = get_node_data(dg, "nodesize"), xdim = 500, ydim = 500, linewidth = get_edge_data(dg, "linewidth"), linecolor = get_edge_data(dg, "new_build"), save_fig = false, fig_name = (@__DIR__)*"/zonal_nodal_builds_RTS_repweek_benders.png")

total_vNSE = sum(value.(m1[:vNSE])) + sum(value.(m2[:vNSE])) + sum(value.(m3[:vNSE]))

total_overproduction = sum(value.(m1[:vOverProduction])) + sum(value.(m2[:vOverProduction])) + sum(value.(m3[:vOverProduction]))

total_vCAP = sum(value.(m1[:vCAP])) + sum(value.(m2[:vCAP])) + sum(value.(m3[:vCAP]))

aggregated_vCAP = sum(value.(mz[:vCAP]))


vP_by_zone_zonal = zeros(3)
vP_by_zone_nodal = zeros(3)
# vP_by_zone_monolithic = zeros(3)
vCAP_by_zone_nodal = zeros(3)
vCAP_by_zone_zonal = zeros(3)

g2z_map = z_inputs["g2z_map"]

for k in keys(g2z_map)
    vP_by_zone_zonal[g2z_map[k]] += sum(value.(mz[:vP][k, :]))
    if k in mz[:vCAP].axes[1]
        vCAP_by_zone_zonal[g2z_map[k]] += sum(value.(mz[:vCAP][k]))
    end
    #vP_by_zone_monolithic[g2z_map[k]] += sum(value.(m[:vP][k, :]))
end

vP_by_zone_nodal[1] = sum(value.(m1[:vP]))
vP_by_zone_nodal[2] = sum(value.(m2[:vP]))
vP_by_zone_nodal[3] = sum(value.(m3[:vP]))

vCAP_by_zone_nodal[1] = sum(value.(m1[:vCAP]))
vCAP_by_zone_nodal[2] = sum(value.(m2[:vCAP]))
vCAP_by_zone_nodal[3] = sum(value.(m3[:vCAP]))
a=1



# benders_settings_path = GenX.get_settings_path(case, "benders_settings.yml")
# mysetup_benders = GenX.configure_benders(benders_settings_path) 

# genx_settings = GenX.get_settings_path(case, "genx_settings.yml") # Settings YAML file path
# writeoutput_settings = GenX.get_settings_path(case, "output_settings.yml") # Write-output settings YAML file path
# mysetup = GenX.configure_settings(genx_settings, writeoutput_settings) # mysetup dictionary stores settings and GenX-specific parameters

# mysetup["DC_OPF"] = 1
# # myinputs = GenX.load_inputs(mysetup, case, p)
# mysetup["ptdf"] = 0
# mysetup["bilinear"] = 1
# mysetup["disaggregate"] = 0
# mysetup["unfix_slacks"] = 0
# mysetup["SOS1"] = 0
# mysetup = merge(mysetup,mysetup_benders);

# settings_path = GenX.get_settings_path(case)    
# mysetup["settings_path"] = settings_path;
# mysetup["Benders"] = 1

# myinputs_decomp = GenX.separate_inputs_subperiods(myinputs);
# # nodal_setup_Benders = deepcopy(nodal_setup)
# # nodal_setup_Benders["Benders"] = 1
# benders_inputs = GenX.generate_benders_inputs(mysetup,myinputs,myinputs_decomp)

# planning_problem, planning_sol, operational_sol, LB_hist,UB_hist, cpu_time,feasibility_hist, build_decisions  = GenX.benders(benders_inputs,mysetup,myinputs);

# for i in keys(planning_sol.values)
#     if planning_sol.values[i] != 0
#         println(i, " = ", planning_sol.values[i])
#     end
# end

# df = DataFrame()

# df[!, "UBs"] = UB_hist
# df[!, "LBs"] = LB_hist
# df[!, "cpu_time"] = cpu_time

# #CSV.write((@__DIR__)*"/zonal_to_nodal_benders_1week_RTS.csv", df)
# optimizer = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 3600, "MIPGap" => 1e-3)

# m = GenX.generate_model(mysetup, myinputs, optimizer)

# optimize!(m)
mtest = JuMP.read_from_file((@__DIR__)*"/../../../subproblem_1.0.lp")