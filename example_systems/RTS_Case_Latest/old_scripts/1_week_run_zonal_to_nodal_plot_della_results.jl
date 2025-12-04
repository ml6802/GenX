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


# cpus_per_task = parse(Int, ENV["SLURM_CPUS_PER_TASK"]);
# addprocs(cpus_per_task)
# println("Adding processors")
# @everywhere begin
#     import Pkg
#     Pkg.activate("/home/ml6802/GenX")
# end

# println("Number of procs: ", nprocs())
# println("Number of workers: ", nworkers())
# for i in workers()
#     id, pid, host = fetch(@spawnat i (myid(), getpid(), gethostname()))
#     println(id, " " , pid, " ", host)
# end
# @everywhere include("/home/ml6802/GenX/src/GenX.jl")


benders_settings_path = GenX.get_settings_path(case, "benders_settings.yml")
mysetup_benders = GenX.configure_benders(benders_settings_path) 

genx_settings = GenX.get_settings_path(case, "genx_settings.yml") # Settings YAML file path
writeoutput_settings = GenX.get_settings_path(case, "output_settings.yml") # Write-output settings YAML file path
mysetup = GenX.configure_settings(genx_settings, writeoutput_settings) # mysetup dictionary stores settings and GenX-specific parameters

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
# myinputs["pTrans_Max"][[5,23,24,70,75]] .*= 1/2
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
myinputs["pMax_Line_Reinforcement"] = [myinputs["Line_Reinforcement_Cap_Size"][i] * myinputs["Max_Trans_Cap"][i] for i in 1:L_cand]
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

idx_to_keep = []
line_sizes = []
new_line_list_cand = []
for i in 1:length(line_list_cand)
    if line_list_cand[i] in new_line_list_cand
        old_idx = findfirst(x -> x == line_list_cand[i], new_line_list_cand)
        line_sizes[old_idx] += myinputs["pTrans_Max"][i]
    else
        push!(idx_to_keep, i)
        push!(line_sizes, myinputs["pTrans_Max"][i])
        push!(new_line_list_cand, line_list_cand[i])
    end
end


myinputs["pNet_Map_cand"] = myinputs["pNet_Map_cand"][idx_to_keep, :]
myinputs["L_cand"] = length(idx_to_keep)
L_cand = myinputs["L_cand"]
myinputs["pDC_OPF_coeff_cand"] = myinputs["pDC_OPF_coeff_cand"][idx_to_keep]
myinputs["Line_Angle_Limit_cand"] = myinputs["Line_Angle_Limit_cand"][idx_to_keep]
myinputs["Line_Reinforcement_Cap_Size"] = myinputs["Line_Reinforcement_Cap_Size"][idx_to_keep]
myinputs["Max_Trans_Cap"] = myinputs["Max_Trans_Cap"][idx_to_keep]
myinputs["pMax_Line_Reinforcement"] = myinputs["pMax_Line_Reinforcement"][idx_to_keep]
myinputs["pTrans_Max_Possible"] = myinputs["pTrans_Max_Possible"][idx_to_keep]
EXPANSION_LEVELS = Dict{Int, Vector}()
for i in 1:L_cand
    EXPANSION_LEVELS[i] = (0:1:myinputs["Max_Trans_Cap"][i])
end
myinputs["EXPANSION_LEVELS"] = EXPANSION_LEVELS
myinputs["EXPANSION_LINES"] = [i for i in 1:myinputs["L_cand"]]
myinputs["pC_Line_Reinforcement"] = myinputs["pC_Line_Reinforcement"][idx_to_keep]



GenX.build_expansion_information!(myinputs)

mysetup["bilinear"] = 0
optimizer = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 200, "MIPGap" => 5e-3)


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

solver = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 60, "MIPGap" => 1e-2)
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

optimizer = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 60, "MIPGap" => 5e-3)

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
# solve nodal models
m1 = GenX.generate_model(nodal_setup, n_inputs[1], optimizer)

optimize!(m1)

println("vcap in zone 1: ", sum(value.(m1[:vCAP])))
println("new transmission in zone 1: ", sum(value.(m1[:vNEW_TRANS_CAP_DECISION_INT])))

println("RUNNING MODEL 2")

m2 = GenX.generate_model(nodal_setup, n_inputs[2], optimizer)

optimize!(m2)

println("vcap in zone 2: ", sum(value.(m2[:vCAP])))
println("new transmission in zone 2: ", sum(value.(m2[:vNEW_TRANS_CAP_DECISION_INT])))

println("RUNNING MODEL 3")

m3 = GenX.generate_model(nodal_setup, n_inputs[3], optimizer)

optimize!(m3)

println("vcap in zone 3: ", sum(value.(m3[:vCAP])))
println("new transmission in zone 3: ", sum(value.(m3[:vNEW_TRANS_CAP_DECISION_INT])))

println("Zonal objective is : ", objective_value(mz))
println("Nodal objective is : ", objective_value(m1) + objective_value(m2) + objective_value(m3))

# Solutions from Della 1 month solve
line_set1 = [2,23,24,25,32,33]
line_set2 = [1,7,8,9,18,19,30]
line_set3 = [1,5,6,7,18,19,27]
vcap_set1 = [53, 55]
vcap_set2 = [16, 28]
vcap_set3 = [47, 55]

line_set_single_build1 = [24,33]
line_set_double_build1 = [2,23,25,32]
line_set_single_build2 = [8,]
line_set_double_build2 = [1,7,9,18,19,30]
line_set_single_build3 = [7,27]
line_set_double_build3 = [1,5,6,18,19]
obj_sum = [0.]
line_sets_single_build = [line_set_single_build1, line_set_single_build2, line_set_single_build3]
line_sets_double_build = [line_set_double_build1, line_set_double_build2, line_set_double_build3]


# Solutions from Della 3 month solve
line_set1 = [2,16,17,21,23,25,27,32,33]
line_set2 = [1,8,9,18,19,31]
line_set3 = [5,6,7,18,27]
vcap_set1 = [53, 55]
vcap_set2 = [16, 28]
vcap_set3 = [47, 55]

line_set_single_build1 = [27]
line_set_double_build1 = [2,16,17,21,23,25,32,33]
line_set_single_build2 = [31]
line_set_double_build2 = [1,8,9,18,19]
line_set_single_build3 = [6,7,18,27]
line_set_double_build3 = [5]
obj_sum = [0.]
line_sets_single_build = [line_set_single_build1, line_set_single_build2, line_set_single_build3]
line_sets_double_build = [line_set_double_build1, line_set_double_build2, line_set_double_build3]

# models = [m1, m2, m3]

# for i in 1:num_zones
#     obj_func = objective_function(models[i])
#     vars = models[i][:vNEW_TRANS_CAP_DECISION_INT]
#     for j in line_sets_single_build[i]
#         obj_sum[1] += obj_func.terms[vars[j, 1]]
#     end
#     for j in line_sets_double_build[i]
#         obj_sum[1] += obj_func.terms[vars[j,1]] * 2
#     end
# end


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


line_sets = [line_set1, line_set2, line_set3]

for i in 1:num_zones
    n_input = n_inputs[i]
    l2l_map = n_input["l2l_map_cand"]
    l2l_map_back = Dict()
    for k in keys(l2l_map)
        l2l_map_back[l2l_map[k]] = k
    end
    ls = line_sets[i]
    for line in ls
        old_line = l2l_map_back[line]
        add_edge_data!(dg, fadjlist[old_line][1], fadjlist[old_line][2], "red", "new_build")
        add_edge_data!(dg, fadjlist[old_line][1], fadjlist[old_line][2], 5, "linewidth")
    end
end

vcap_sets = [vcap_set1, vcap_set2, vcap_set3]

for i in 1:num_zones
    n_input = n_inputs[i]
    n2n_map = n_input["n2n_map"]
    n2n_map_back = Dict()
    for j in keys(n2n_map)
        n2n_map_back[n2n_map[j]] = j
    end
    for vs in vcap_sets[i]
        resource = n_input["RESOURCES"][vs]
        println(parent(resource)[:resource])
        genx_zone = parent(resource)[:zone]
        node = n2n_map_back[genx_zone]
        add_node_data!(dg, node, "black", "color")
        add_node_data!(dg, node, 10, "nodesize")
    end
end

plot_graph(dg, nodecolor = get_node_data(dg, "color"), nodesize = get_node_data(dg, "nodesize"), xdim = 500, ydim = 500, linewidth = get_edge_data(dg, "linewidth"), linecolor = get_edge_data(dg, "new_build"), save_fig = false, fig_name = (@__DIR__)*"/zonal_nodal_builds_RTS_3_month_benders.png")
    