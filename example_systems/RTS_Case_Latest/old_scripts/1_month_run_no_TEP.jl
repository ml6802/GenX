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
using Distributed, ClusterManagers, Suppressor

# Pkg.activate("/home/ml6802/GenX")
# include("/home/ml6802/GenX/src/GenX.jl")

# @suppress begin
include((@__DIR__)*"/load_portfolio.jl")
include((@__DIR__)*"/../convert_input_dict_reconductoring.jl")

p.internal.ext["Rep_Periods"] = 1
p.internal.ext["Timesteps_per_Rep_Period"] = 672
p.internal.ext["hours_per_subperiod"] = 672
p.internal.ext["sub_weights"] = [8784/12 for i in 1:1]
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
#myinputs["pD"] .*= 1
# myinputs["Voll"] .*= 10
myinputs["pTrans_Max"] .*= 1
#myinputs["pTrans_Max"][[5,23,24,70,75]] .*= 1/70
L = myinputs["L"]
L_exist = L
L_cand = L
myinputs["L_cand"] = L_cand
myinputs["L_exist"] = L_exist
myinputs["L"] = L * 2
myinputs["LINES"] = [i for i in 1:myinputs["L"]]
myinputs["Z_cand"] = myinputs["Z"]
myinputs["pNet_Map"] = vcat(myinputs["pNet_Map"], myinputs["pNet_Map"])
myinputs["pDC_OPF_coeff"] = vcat(myinputs["pDC_OPF_coeff"], myinputs["pDC_OPF_coeff"])
myinputs["Line_Angle_Limit"] = [6.282 for i in 1:myinputs["L"]]
myinputs["Line_Reinforcement_Cap_Size"] = vcat([0 for i in 1:L_exist], [i for i in myinputs["pTrans_Max"]])
myinputs["Max_Trans_Cap"] = vcat([0 for i in 1:L_exist], [1 for i in myinputs["pTrans_Max"]])
myinputs["pTrans_Max"] = vcat([i for i in myinputs["pTrans_Max"]], [0 for i in 1:L_cand])



EXPANSION_LEVELS = Dict{Int, Vector}()
for i in (L_exist + 1):(L_exist + L_cand)
    EXPANSION_LEVELS[i] = (0:1:myinputs["Max_Trans_Cap"][i])
end
EXPANSION_LINES = [i for i in (L_exist + 1):(L_exist + L_cand)]
myinputs["EXPANSION_LINES"] = EXPANSION_LINES
myinputs["CANDIDATE_LINES"] = copy(EXPANSION_LINES)
myinputs["EXISTING_LINES"] = [i for i in 1:L_exist]
myinputs["pPercent_Loss"] = vcat(myinputs["pPercent_Loss"], myinputs["pPercent_Loss"])

lines = collect(get_technologies(TransmissionTechnology, p));
myinputs["pC_Line_Reinforcement"] = zeros(myinputs["L"])
myinputs["pC_Line_Reconductor_High"] = zeros(myinputs["L"])
myinputs["pC_Line_Reconductor_Low"] = zeros(myinputs["L"])

scale_factor = mysetup["ParameterScale"] == 1 ? GenX.ModelScalingFactor : 1

CAN_RETIRE_LINES = Int[]
CANNOT_RETIRE_LINES = Int[]
RECONDUCTOR_LINES = Int[]
existing_to_cand_map = Dict()

using Random
Random.seed!(1)
for i in 1:length(lines)
    #check for reconductoring; 

    distance = 60 * rand()
    cap_val = distance * 1200
    cost = cap_val * (0.044) / (1 - (1 + 0.044)^(-60))
    myinputs["pC_Line_Reinforcement"][i + L_exist] = cost

    if get_existing_capacity_mw(p, lines[i]) > 200
        push!(CANNOT_RETIRE_LINES, i)
        push!(RECONDUCTOR_LINES, i)
        myinputs["pC_Line_Reconductor_Low"][i] = cost .* 0.3
        myinputs["pC_Line_Reconductor_High"][i] = cost .* 0.7
        myinputs["Line_Reinforcement_Cap_Size"][L_exist + i] *= 1.5
        myinputs["pDC_OPF_coeff"][L_exist + i] *= 1.5
    else
        push!(CAN_RETIRE_LINES, i)
        existing_to_cand_map[i] = L_exist + i
        myinputs["Line_Reinforcement_Cap_Size"][L_exist + i] *= 2.5
        #myinputs["pDC_OPF_coeff"][L_exist + i] *= 2.5
    end
end

#myinputs["pDC_OPF_coeff"] .*= 2000 #2000
# myinputs["pDC_OPF_coeff"] .*= 100 #2000

myinputs["CAN_RETIRE_LINES"] = CAN_RETIRE_LINES
myinputs["CANNOT_RETIRE_LINES"] = CANNOT_RETIRE_LINES
myinputs["RECONDUCTOR_LINES"] = RECONDUCTOR_LINES
myinputs["existing_to_cand_map"] = existing_to_cand_map

myinputs["hours_per_subperiod"] = 672
myinputs["INTERIOR_SUBPERIODS"] = [i for i in 2:myinputs["hours_per_subperiod"]]
myinputs["T"] = 672


mysetup["NetworkExpansion"] = 1
mysetup["Benders"] = 0



#optimize!(m)


# myinputs["L_cand"] = 10
# myinputs["L"] = myinputs["L_exist"]
# myinputs["pNet_Map"] = myinputs["pNet_Map"][1:130, :]
# myinputs["CANDIDATE_LINES"] = [i for i in 121:130]
# myinputs["CAN_RETIRE_LINES"] = [i for i in 1:10]
# myinputs["CANNOT_RETIRE_LINES"] = [i for i in 11:120]
# myinputs["RECONDUCTOR_LINES"] = [i for i in 11:120]

# for i in 1:10
#     myinputs["existing_to_cand_map"][i] = 120 + i
# end
# end


# myinputs["L"] = L_exist
# myinputs["CANDIDATE_LINES"] = []
# myinputs["CANNOT_RETIRE_LINES"] = [i for i in 1:120]
# myinputs["RECONDUCTOR_LINES"] = []
# myinputs["CAN_RETIRE_LINES"] = []
mysetup["bilinear"] = 0
mysetup["ptdf"] = 0
mysetup["NetworkExpansion"] = 1
mysetup["DC_OPF"] = 1
mysetup["unfix_slacks"] = 0
myinputs["pTrans_Max"] .*= 1
myinputs["pD_original"] = deepcopy(myinputs["pD"])
myinputs["pD"] .*= 4

myinputs["NetworkExpansion"] = 0
myinputs["DC_OPF"] = 0
optimizer = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 120, "MIPGap" => 1e-3)

rs = myinputs["RESOURCES"]
new_cap_zones = [parent(rs[i])[:zone] for i in myinputs["NEW_CAP"]]

tts = collect(get_technologies(SupplyTechnology, p))

nodes = []
for (j, i) in enumerate(tts)
    if !(IS.has_supplemental_attributes(ExistingCapacity, i))
        if length(i.region) > 1
            #println(i.region)
            println(j)
        end
        push!(nodes, i.region[1])
    end
end

# m = GenX.generate_model(mysetup, myinputs, optimizer)
# # for i in 121:240
# #     fix(m[:vNEW_TRANS_CAP_DECISION_INT][i, 1], 0)
# # end
# optimize!(m)

# mysetup["ptdf"] = 0
# mbtheta = GenX.generate_model(mysetup, myinputs, optimizer)

# for i in 121:240
#     fix(mbtheta[:vNEW_TRANS_CAP_DECISION_INT][i], value(m[:vNEW_TRANS_CAP_DECISION_INT][i]), force = true)
# end

# optimize!(mbtheta)


myinputs["NetworkExpansion"] = 0
myinputs["Z"] = 1
myinputs["DC_OPF"] = 0
myinputs["pD"] = sum(myinputs["pD"], dims = 2)

rs = myinputs["RESOURCES"]
for (i, r) in enumerate(rs)
    parent(r)[:zone] = 1
end

optimizer = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 120, "MIPGap" => 1e-3)
mz = GenX.generate_model(mysetup, myinputs, optimizer)
# for i in 121:240
#     fix(m[:vNEW_TRANS_CAP_DECISION_INT][i, 1], 0)
# end
optimize!(mz)

rs = myinputs["RESOURCES"];

thermals = [0.]
vres = [0.]
for i in 1:length(rs)
    if typeof(rs[i]) == GenX.Thermal{Symbol, Any}
        thermals[1] += parent(rs[i])[:existing_cap_mw]
    elseif typeof(rs[i]) == GenX.Vre{Symbol, Any} #|| typeof(rs[i]) == GenX.MustRun{Symbol, Any}
        vres[1] += parent(rs[i])[:existing_cap_mw]
    else
        println(typeof(rs[i]))
    end
end

nc = myinputs["NEW_CAP"]
new_vre = [0.]
new_thermal = [0.]
for i in nc
    if value(mz[:vCAP][i]) > 0
        if typeof(rs[i]) == GenX.Thermal{Symbol, Any}
            new_thermal[1] += value(mz[:vCAP][i])
        elseif typeof(rs[i]) == GenX.Vre{Symbol, Any}
            new_vre[1] += value(mz[:vCAP][i])
        else
            println(typeof(rs[i]))
        end
    end
end


a=1



# compute_conflict!(m)

# list_of_conflicting_constraints = ConstraintRef[];
# for (F, S) in list_of_constraint_types(m)
# 	for con in all_constraints(m, F, S)
# 		if get_attribute(con, MOI.ConstraintConflictStatus()) == MOI.IN_CONFLICT
# 			push!(list_of_conflicting_constraints, con)
# 		end
# 	end
# end
# display(list_of_conflicting_constraints)


# r137 = myinputs["RESOURCES"][137]
# sts = union(collect(get_technologies(SupplyTechnology, p)), collect(get_technologies(StorageTechnology, p)));

# sts_id_map = Dict(sts[i].id => i for i in 1:length(sts))
# tech_to_id = myinputs["technology_to_index"]


# gen_names = get_existing_technologies(IS.get_supplemental_attributes(ExistingCapacity, sts[168])[1])
# comp = PSY.get_component.(GenX.get_parameter_type(sts[168]), Ref(p.base_system), gen_names)
# sum(get_storage_capacity(t) for t in comp)






mysetup["bilinear"] = 0
mysetup["ptdf"] = 1
optimizer = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 100, "MIPGap" => 1e-3)
mptdf = GenX.generate_model(mysetup, myinputs, optimizer)
# for i in 121:240
#     fix(m[:vNEW_TRANS_CAP_DECISION_INT][i, 1], 0)
# end
optimize!(mptdf)



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
# #mysetup["BD_integer_routine"] = 1
# # mysetup["BD_Stab_Method"] = "int_level_set"

# myinputs_decomp = GenX.separate_inputs_subperiods(myinputs);
# # nodal_setup_Benders = deepcopy(nodal_setup)
# # nodal_setup_Benders["Benders"] = 1
# benders_inputs = GenX.generate_benders_inputs(mysetup,myinputs,myinputs_decomp)
# planning_problem1, planning_sol1, operational_sol1, LB_hist1,UB_hist1, cpu_time,feasibility_hist1, build_decisions1  = GenX.benders(benders_inputs,mysetup,myinputs);


# mysetup["bilinear"] = 1
# optimizer = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 300, "MIPGap" => 1e-4)
# mb = GenX.generate_model(mysetup, myinputs, optimizer)

# for i in 121:240
#     fix(m[:vNEW_TRANS_CAP_DECISION_INT][i, 1], 0)
# end
# optimize!(mb)


# vflows = value.(m[:vFLOW])
# for i in 1:120
#     line_flows = vflows[i, :]
#     if maximum(line_flows) == myinputs["pTrans_Max"][i] || (-minimum(line_flows) == myinputs["pTrans_Max"][i])
#         println(maximum(line_flows), "   ", minimum(line_flows))
#         println(i)
#     end
# end



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

vCAP_sizes = [1301.1189,425.529167,1301.1189,425.529167,411.947196,411.947196]
vCAP_names = ["CT36", "CT35", "CC33", "CC32", "CT34", "CC31"]
vCAP_builds = [47, 60, 72, 98, 129, 132]

for (i, v) in enumerate(vCAP_sizes)
    for (j, r) in enumerate(myinputs["RESOURCES"])
        if parent(r)[:resource] == vCAP_names[i]
            fix(mz[:vCAP][j], vCAP_sizes[i], force = true)
            println(j)
            break
        end
    end
end

# for i in 6:10
#     fix(mz[:vNEW_TRANS_LINES][i, 1], 0, force = true)
# end

optimize!(mz)

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

# for (key, value) in z_inputs["interzonal_node_flows"]
#     z_inputs["interzonal_node_flows"][key] = zeros(168)
# end

# add to the nodal inputs the interzonal transmission time series
nts = get_interzonal_node_time_series(z_inputs, mz)
cap_decisions = get_capacity_solutions(z_inputs, mz)
z_inputs["interzonal_node_flows"] = nts
z_inputs["capacity_decisions"] = cap_decisions

add_interzonal_data!(z_inputs, n_inputs)


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
nodal_setup["unfix_slacks"] = 0
# solve nodal models
# m1 = GenX.generate_model(nodal_setup, n_inputs[1], optimizer)
m1 = build_nodal_resolution_model(nodal_setup, n_inputs[1], optimizer)

optimize!(m1)

# obj_func_a = objective_function(m1)
# obj_func_b = objective_function(m1b)
# for i in 1:length(n_inputs[1]["l2l_map_cand"])
#     vara = m1[:vNEW_TRANS_CAP_DECISION_INT][i,1]
#     varb = m1b[:vNEW_TRANS_CAP_DECISION_INT][i, 1]
#     value_a = value(m1[:vNEW_TRANS_CAP_DECISION_INT][i, 1])
#     value_b = value(m1b[:vNEW_TRANS_CAP_DECISION_INT][i, 1])
    

#     if value_a == value_b
#         vcand_flow_a = [value(m1[:vCANDFLOW][i, k, 1]) for k in 1:myinputs["T"]]
#         vcand_flow_b = [value(m1b[:vCANDFLOW][i, k, 1]) for k in 1:myinputs["T"]]
#         println("max a = ", maximum(vcand_flow_a), "  max b = ", maximum(vcand_flow_b))
#     end
# end


println("vcap in zone 1: ", sum(value.(m1[:vCAP])))
println("new transmission in zone 1: ", sum(value.(m1[:vNEW_TRANS_CAP_DECISION_INT])))

println("RUNNING MODEL 2")
# m2 = GenX.generate_model(nodal_setup, n_inputs[2], optimizer)
m2 = build_nodal_resolution_model(nodal_setup, n_inputs[2], optimizer)
optimize!(m2)

println("vcap in zone 2: ", sum(value.(m2[:vCAP])))
println("new transmission in zone 2: ", sum(value.(m2[:vNEW_TRANS_CAP_DECISION_INT])))

# obj_func = objective_function(m2)
# obj_val = [0.]
# for v in keys(obj_func.terms)
#     if value(v) != 0 && !occursin("Fuel", name(v))
#         println(v, "   ", value(v), "  ", obj_func.terms[v])
#         obj_val[1] += value(v) * obj_func.terms[v]
#     end
# end




println("RUNNING MODEL 3")

# m3 = GenX.generate_model(nodal_setup, n_inputs[3], optimizer)
m3 = build_nodal_resolution_model(nodal_setup, n_inputs[3], optimizer)

optimize!(m3)

println("vcap in zone 3: ", sum(value.(m3[:vCAP])))
println("new transmission in zone 3: ", sum(value.(m3[:vNEW_TRANS_CAP_DECISION_INT])))

println("Zonal objective is : ", objective_value(mz))
println("Nodal objective is : ", objective_value(m1) + objective_value(m2) + objective_value(m3))
println("Zonal NSE is : ", sum(value(mz[:vNSE])))
println("Nodal NSE is : ", sum(value(m1[:vNSE])) + sum(value(m2[:vNSE])) + sum(value(m3[:vNSE])))

println("Zonal Builds: ", sum(value(mz[:vNEW_TRANS_LINES])))
println("Nodal Builds: ", sum(value(m1[:vNEW_TRANS_CAP_DECISION_INT])) + sum(value(m2[:vNEW_TRANS_CAP_DECISION_INT])) + sum(value(m3[:vNEW_TRANS_CAP_DECISION_INT])))





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



plot_graph(dg, nodecolor = get_node_data(dg, "color"), nodesize = get_node_data(dg, "nodesize"), xdim = 500, ydim = 500, linewidth = get_edge_data(dg, "linewidth_status"), linecolor = get_edge_data(dg, "status"), save_fig = false, fig_name = (@__DIR__)*"/zonal_nodal_builds_RTS_repweek_benders.png")














a=1





#=

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
planning_problem1, planning_sol1, operational_sol1, LB_hist1,UB_hist1, cpu_time,feasibility_hist1, build_decisions1  = GenX.benders(benders_inputs,mysetup,n_inputs[1]);

# vals = [0.]
# for k in keys(planning_sol1.values)
#     if occursin("vNEW_TRANS_CAP", k)
#         vals[1] += planning_sol1.values[k]
#     end
# end

# df = DataFrame()
# df[!, "UB"] = UB_hist2
# df[!, "LB"] = LB_hist
# df[!, "TIME"] = cpu_time

#CSV.write((@__DIR__)*"/1week_zone2_with_retirements_bilinear_only.csv", df)


myinputs_decomp = GenX.separate_inputs_subperiods(n_inputs[2]);
# nodal_setup_Benders = deepcopy(nodal_setup)
# nodal_setup_Benders["Benders"] = 1
benders_inputs = GenX.generate_benders_inputs(mysetup,n_inputs[2],myinputs_decomp)
planning_problem2, planning_sol2, operational_sol2, LB_hist2,UB_hist2, cpu_time,feasibility_hist2, build_decisions2  = GenX.benders(benders_inputs,mysetup,n_inputs[2]);

myinputs_decomp = GenX.separate_inputs_subperiods(n_inputs[3]);
# nodal_setup_Benders = deepcopy(nodal_setup)
# nodal_setup_Benders["Benders"] = 1
benders_inputs = GenX.generate_benders_inputs(mysetup,n_inputs[3],myinputs_decomp)
planning_problem3, planning_sol3, operational_sol3, LB_hist,UB_hist3, cpu_time,feasibility_hist3, build_decisions3  = GenX.benders(benders_inputs,mysetup,n_inputs[3]);


#if UB_hist1[end] < objective_value(m1)
    #l2l_map = n_inputs[1]["l2l_map_rev"]
    #for k in keys(l2l_map)
        #old_line = k
        #new_line = l2l_map[k]
        #if new_line in n_inputs[1]["CANDIDATE_LINES"]
        for new_line in n_inputs[1]["CANDIDATE_LINES"]
            println(new_line)
            val1 = planning_sol1.values["vNEW_TRANS_CAP_DECISION_INT[$new_line,1]"]
            fix(m1[:vNEW_TRANS_CAP_DECISION_INT][new_line, 1], val1, force = true)
            #val2 = planning_sol1.values["vNEW_TRANS_CAP_DECISION_INT[$new_line,2]"]
            #fix(m1[:vNEW_TRANS_CAP_DECISION_INT][new_line, 2], val2, force = true)
        end
    #end
    optimize!(m1)
#end
#if UB_hist2[end] < objective_value(m2)
#    l2l_map = n_inputs[2]["l2l_map"]
#    for k in keys(l2l_map)
    for new_line in n_inputs[2]["CANDIDATE_LINES"]
        val = planning_sol2.values["vNEW_TRANS_CAP_DECISION_INT[$new_line,1]"]
        fix(m2[:vNEW_TRANS_CAP_DECISION_INT][new_line, 1], val, force = true)
    end
    optimize!(m2)
#end
# if UB_hist3[end] < objective_value(m3)
#     l2l_map = n_inputs[3]["l2l_map_cand"]
#     for k in keys(l2l_map)
#         old_line = k
#         new_line = l2l_map[k]
    for new_line in n_inputs[3]["CANDIDATE_LINES"]
        val = planning_sol3.values["vNEW_TRANS_CAP_DECISION_INT[$new_line,1]"]
        fix(m3[:vNEW_TRANS_CAP_DECISION_INT][new_line, 1], val, force = true)
    end
    optimize!(m3)
# end

println("Zonal objective is : ", objective_value(mz))
println("Nodal objective is : ", objective_value(m1) + objective_value(m2) + objective_value(m3))

#=
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
=#
=#