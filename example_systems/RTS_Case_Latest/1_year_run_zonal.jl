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
mysetup["bilinear"] = 1
mysetup["disaggregate"] = 0
mysetup["unfix_slacks"] = 0
mysetup["SOS1"] = 0
mysetup = merge(mysetup,mysetup_benders);

settings_path = GenX.get_settings_path(case)    
mysetup["settings_path"] = settings_path;

# myinputs["pTrans_Max"] .*= 2
# myinputs["pTrans_Max"][[5,23,24,70,75]] .*= 0.5
#myinputs["pD"] .*= 1
# myinputs["Voll"] .*= 10

L_cand = myinputs["L"]
myinputs["L_cand"] = L_cand
myinputs["Z_cand"] = myinputs["Z"]
myinputs["pNet_Map_cand"] = copy(myinputs["pNet_Map"])
myinputs["pDC_OPF_coeff_cand"] = copy(myinputs["pDC_OPF_coeff"])
myinputs["LineAngle_Limit"] = [6.282 for i in 1:L_cand]
myinputs["Line_Angle_Limit_cand"] = myinputs["Line_Angle_Limit"]

# one level of expansion for each line
# equal to half of existing capacity for any given line pTrans_Max
myinputs["Line_Reinforcement_Cap_Size"] = [i for i in myinputs["pTrans_Max"]]
myinputs["Max_Trans_Cap"] = [1 for i in myinputs["pTrans_Max"]]
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

solver = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 86400, "MIPGap" => 1e-2)
###### ZONAL ######
zonal_setup = deepcopy(mysetup)
zonal_setup["unfix_slacks"] = 1
zonal_setup["NetworkExpansion"] = 1
zonal_setup["DC_OPF"] = 1

optimizer = solver
###### ZONAL ######
zonal_setup["unfix_slacks"] = 1
zonal_setup["NetworkExpansion"] = 1
zonal_setup["IntegerInvestment"] = 1
zonal_setup["DC_OPF"] = 1


mz = run_zonal_model!(z_inputs, zonal_setup, optimizer)

println("VNSE = ", sum(value.(mz[:vNSE])))
println("Num builds = ", sum(value.(mz[:vNEW_TRANS_CAP_DECISION_INT])))
println("vCAP = ", sum(value.(mz[:vCAP])))
println("voverproduction = ", sum(value.(mz[:vOverProduction])))

optimizer = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 120, "MIPGap" => 5e-3)

n2z_map = zone_map
num_zones = 3
# build the nodal inputs
n_inputs = build_nodal_inputs(myinputs, n2z_map, num_zones)

nodal_setup = deepcopy(mysetup)
nodal_setup["DC_OPF"] = 1
nodal_setup["unfix_slacks"] = 0
nodal_setup["NetworkExpansion"] = 1
nodal_setup["IntegerInvestment"] = 1

# add to the nodal inputs the interzonal transmission time series
add_interzonal_data!(z_inputs, n_inputs)

println("RUNNING MODEL 1")
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


l2z_map = z_inputs["l2z_map_cand"]
for k in keys(l2z_map)
    new_line = l2z_map[k]
    add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "white", "zonal_line")
    if value(mz[:vNEW_TRANS_CAP_DECISION_INT][new_line, 1]) == 1
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


plot_graph(dg, nodecolor = get_node_data(dg, "color"), nodesize = 6, xdim = 500, ydim = 500, linewidth = get_edge_data(dg, "linewidth"), linecolor = get_edge_data(dg, "new_build"), save_fig = false, fig_name = (@__DIR__)*"/zonal_nodal_builds_RTS_repweek.png")

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

# get the capacity 


# 5,23,24,70,75
# #7,43
# #72,13
# #17,71
# #9,56
# #34,50



# benders_settings_path = GenX.get_settings_path(case, "benders_settings.yml")
# mysetup_benders = GenX.configure_benders(benders_settings_path) 

# genx_settings = GenX.get_settings_path(case, "genx_settings.yml") # Settings YAML file path
# writeoutput_settings = GenX.get_settings_path(case, "output_settings.yml") # Write-output settings YAML file path
# mysetup = GenX.configure_settings(genx_settings, writeoutput_settings) # mysetup dictionary stores settings and GenX-specific parameters

# mysetup["DC_OPF"] = 1
# mysetup["ptdf"] = 0
# mysetup["bilinear"] = 1
# mysetup["disaggregate"] = 0
# mysetup["unfix_slacks"] = 0
# mysetup["SOS1"] = 0
# mysetup = merge(mysetup,mysetup_benders);

# settings_path = GenX.get_settings_path(case)    
# mysetup["settings_path"] = settings_path;
# mysetup["NetworkExpansion"] = 1
# mysetup["Benders"] = 1


# myinputs_decomp = GenX.separate_inputs_subperiods(n_inputs[1]);
# # nodal_setup_Benders = deepcopy(nodal_setup)
# # nodal_setup_Benders["Benders"] = 1
# benders_inputs = GenX.generate_benders_inputs(mysetup,n_inputs[1],myinputs_decomp)
# planning_problem1, planning_sol1, operational_sol1, LB_hist,UB_hist1, cpu_time,feasibility_hist1, build_decisions1  = GenX.benders(benders_inputs,mysetup,n_inputs[1]);

# myinputs_decomp = GenX.separate_inputs_subperiods(n_inputs[2]);
# # nodal_setup_Benders = deepcopy(nodal_setup)
# # nodal_setup_Benders["Benders"] = 1
# benders_inputs = GenX.generate_benders_inputs(mysetup,n_inputs[2],myinputs_decomp)
# planning_problem2, planning_sol2, operational_sol2, LB_hist,UB_hist2, cpu_time,feasibility_hist2, build_decisions2  = GenX.benders(benders_inputs,mysetup,n_inputs[2]);

# myinputs_decomp = GenX.separate_inputs_subperiods(n_inputs[3]);
# # nodal_setup_Benders = deepcopy(nodal_setup)
# # nodal_setup_Benders["Benders"] = 1
# benders_inputs = GenX.generate_benders_inputs(mysetup,n_inputs[3],myinputs_decomp)
# planning_problem3, planning_sol3, operational_sol3, LB_hist,UB_hist3, cpu_time,feasibility_hist3, build_decisions3  = GenX.benders(benders_inputs,mysetup,n_inputs[3]);




# # plot results
# using PlasmoData, PlasmoDataPlots
# fadjlist = z_inputs["adj_list"]
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


# l2z_map = z_inputs["l2z_map_cand"]
# for k in keys(l2z_map)
#     new_line = l2z_map[k]
#     add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "white", "zonal_line")
#     if value(mz[:vNEW_TRANS_CAP_DECISION_INT][new_line, 1]) == 1
#         add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "red", "new_build")
#         add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], 5, "linewidth")
#     end
# end


# models = [m1, m2]
# for i in 1:2
#     n_input = n_inputs[i]
#     l2l_map = n_input["l2l_map_cand"]
#     model = models[i]
#     for k in keys(l2l_map)
#         old_line = k
#         new_line = l2l_map[k]
#         if value(models[i][:vNEW_TRANS_CAP_DECISION_INT][new_line, 1]) == 1
#             add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "red", "new_build")
#             add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], 5, "linewidth")
#         end
#     end
# end

# l2l_map3 = n_inputs[3]["l2l_map_cand"]
# for k in keys(l2l_map3)
#     old_line = k
#     new_line = l2l_map3[k]
#     val = planning_sol.values["vNEW_TRANS_CAP_DECISION_INT[$new_line]"]
#     if val == 1
#         add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "red", "new_build")
#         add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], 5, "linewidth")
#     end
# end

# plot_graph(dg, nodecolor = get_node_data(dg, "color"), nodesize = 6, xdim = 500, ydim = 500, linewidth = get_edge_data(dg, "linewidth"), linecolor = get_edge_data(dg, "new_build"), save_fig = true, fig_name = (@__DIR__)*"/zonal_to_nodal_build_1week.png")




# # vP_by_zone_zonal = zeros(3)
# # vP_by_zone_nodal = zeros(3)
# # vP_by_zone_monolithic = zeros(3)

# # g2z_map = z_inputs["g2z_map"]

# # for k in keys(g2z_map)
# #     vP_by_zone_zonal[g2z_map[k]] += sum(value.(mz[:vP][k, :]))
# #     #vP_by_zone_monolithic[g2z_map[k]] += sum(value.(m[:vP][k, :]))
# # end

# # vP_by_zone_nodal[1] = sum(value.(m1[:vP]))
# # vP_by_zone_nodal[2] = sum(value.(m2[:vP]))
# # vP_by_zone_nodal[3] = sum(value.(m3[:vP]))



benders_settings_path = GenX.get_settings_path(case, "benders_settings.yml")
mysetup_benders = GenX.configure_benders(benders_settings_path) 

genx_settings = GenX.get_settings_path(case, "genx_settings.yml") # Settings YAML file path
writeoutput_settings = GenX.get_settings_path(case, "output_settings.yml") # Write-output settings YAML file path
mysetup = GenX.configure_settings(genx_settings, writeoutput_settings) # mysetup dictionary stores settings and GenX-specific parameters

mysetup["DC_OPF"] = 1
# myinputs = GenX.load_inputs(mysetup, case, p)
mysetup["ptdf"] = 0
mysetup["bilinear"] = 1
mysetup["disaggregate"] = 0
mysetup["unfix_slacks"] = 0
mysetup["SOS1"] = 0
mysetup = merge(mysetup,mysetup_benders);

settings_path = GenX.get_settings_path(case)    
mysetup["settings_path"] = settings_path;
mysetup["Benders"] = 1

myinputs_decomp = GenX.separate_inputs_subperiods(myinputs);
# nodal_setup_Benders = deepcopy(nodal_setup)
# nodal_setup_Benders["Benders"] = 1
benders_inputs = GenX.generate_benders_inputs(mysetup,myinputs,myinputs_decomp)

planning_problem, planning_sol, operational_sol, LB_hist,UB_hist, cpu_time,feasibility_hist, build_decisions  = GenX.benders(benders_inputs,mysetup,myinputs);

for i in keys(planning_sol.values)
    if planning_sol.values[i] != 0
        println(i, " = ", planning_sol.values[i])
    end
end



for i in 1:length(avs)
    if is_fixed(avs[i]) && i > 1
        println(avs[i])
        println(dual(FixRef(avs[i])))
    end
end



new_model = JuMP.read_from_file((@__DIR__)*"/RC_ERROR.lp")
solver = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 600, "QCPDual" => 1, "ObjScale" => 100000, "ScaleFlag" => 2)

set_optimizer(new_model, solver)
optimize!(new_model)

avs = all_variables(new_model)

# for i in 1:length(avs)
#     if is_fixed(avs[i]) && i > 1
#         println(avs[i])
#         println(dual(FixRef(avs[i])))
#     end
# end

sols = value.(avs)

using Ipopt
set_optimizer(new_model, Ipopt.Optimizer)
set_optimizer_attribute(new_model, "max_cpu_time", 120.)
set_start_value.(avs, sols)
optimize!(new_model)

for i in 1:length(avs)
    if is_fixed(avs[i])
        println(avs[i])
        println(dual(FixRef(avs[i])))
    end
end