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

include((@__DIR__)*"/load_portfolio.jl")
include((@__DIR__)*"/../convert_input_dict.jl")

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

#using JLD2

#JLD2.save((@__DIR__)*"/inputs_and_settings.jld2", "inputs", myinputs, "setup", mysetup)



# rs = myinputs["RESOURCES"]
# for (i, r) in enumerate(rs)
#     println(i, "   ", GenX.cap_size(r))
# end

# add candidate data

myinputs["pTrans_Max"] .*= 0.3
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
using Random
Random.seed!(1)
for i in 1:length(lines)
    distance = 60 * rand()
    size_mw = myinputs["Line_Reinforcement_Cap_Size"][i]
    myinputs["pC_Line_Reinforcement"][i] = distance * size_mw * 2#000
end


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
n_times = 168
myinputs["T"] = n_times
myinputs["hours_per_subperiod"] = n_times
myinputs["INTERIOR_SUBPERIODS"] = [i for i in 2:myinputs["hours_per_subperiod"]]
z_inputs = build_zonal_inputs(myinputs, zone_map, 3)

solver = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 120, "MIPGap" => 1e-2)
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


plot_graph(dg, nodecolor = get_node_data(dg, "color"), nodesize = 6, xdim = 500, ydim = 500, linewidth = get_edge_data(dg, "linewidth"), linecolor = get_edge_data(dg, "new_build"), save_fig = false, fig_name = (@__DIR__)*"/zonal_nodal_builds_nodcopf.png")

vP_by_zone_zonal = zeros(3)
vP_by_zone_nodal = zeros(3)
vP_by_zone_monolithic = zeros(3)

g2z_map = z_inputs["g2z_map"]

for k in keys(g2z_map)
    vP_by_zone_zonal[g2z_map[k]] += sum(value.(mz[:vP][k, :]))
    #vP_by_zone_monolithic[g2z_map[k]] += sum(value.(m[:vP][k, :]))
end

vP_by_zone_nodal[1] = sum(value.(m1[:vP]))
vP_by_zone_nodal[2] = sum(value.(m2[:vP]))
vP_by_zone_nodal[3] = sum(value.(m3[:vP]))


# solver_monolithic = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 600, "MIPGap" => 2e-2)

# m = GenX.generate_model(nodal_setup, myinputs, solver_monolithic)

# optimize!(m)

# get set of new trans cap variables; 

#nodal_setup, n_inputs[3], optimizer

# benders_settings_path = GenX.get_settings_path(case, "benders_settings.yml")
# mysetup_benders = GenX.configure_benders(benders_settings_path) 

# genx_settings = GenX.get_settings_path(case, "genx_settings.yml") # Settings YAML file path
# writeoutput_settings = GenX.get_settings_path(case, "output_settings.yml") # Write-output settings YAML file path
# mysetup = GenX.configure_settings(genx_settings, writeoutput_settings) # mysetup dictionary stores settings and GenX-specific parameters

# mysetup["DC_OPF"] = 1
# myinputs = GenX.load_inputs(mysetup, case, p)
# mysetup["ptdf"] = 0
# mysetup["bilinear"] = 1
# mysetup["disaggregate"] = 0
# mysetup["unfix_slacks"] = 0
# mysetup["SOS1"] = 0
# mysetup = merge(mysetup,mysetup_benders);

# settings_path = GenX.get_settings_path(case)    
# mysetup["settings_path"] = settings_path;
# mysetup["Benders"] = 1

# myinputs_decomp = GenX.separate_inputs_subperiods(n_inputs[3]);
# # nodal_setup_Benders = deepcopy(nodal_setup)
# # nodal_setup_Benders["Benders"] = 1
# benders_inputs = GenX.generate_benders_inputs(mysetup,n_inputs[3],myinputs_decomp)

# planning_problem, planning_sol, operational_sol, LB_hist,UB_hist, cpu_time,feasibility_hist, build_decisions  = GenX.benders(benders_inputs,mysetup,n_inputs[3]);


