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
p.internal.ext["Timesteps_per_Rep_Period"] = 2184
p.internal.ext["sub_weights"] = [8784/4 for i in 1:1]
p.internal.ext["hours_per_subperiod"] = 2184
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


myinputs["hours_per_subperiod"] = 2184
myinputs["INTERIOR_SUBPERIODS"] = [i for i in 2:myinputs["hours_per_subperiod"]]
myinputs["T"] = 2184

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
optimizer = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 10800, "MIPGap" => 1e-3)
#m = GenX.generate_model(mysetup, myinputs, optimizer)

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

solver = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 7200, "MIPGap" => 1e-3)
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

optimizer = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 600, "MIPGap" => 1e-3)

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


# println("vcap in zone 1: ", sum(value.(m1[:vCAP])))
# println("new transmission in zone 1: ", sum(value.(m1[:vNEW_TRANS_CAP_DECISION_INT])))

println("RUNNING MODEL 2")

m2 = GenX.generate_model(nodal_setup, n_inputs[2], optimizer)

optimize!(m2)

# println("vcap in zone 2: ", sum(value.(m2[:vCAP])))
# println("new transmission in zone 2: ", sum(value.(m2[:vNEW_TRANS_CAP_DECISION_INT])))

println("RUNNING MODEL 3")

m3 = GenX.generate_model(nodal_setup, n_inputs[3], optimizer)

optimize!(m3)

# println("vcap in zone 3: ", sum(value.(m3[:vCAP])))
# println("new transmission in zone 3: ", sum(value.(m3[:vNEW_TRANS_CAP_DECISION_INT])))

# println("Zonal objective is : ", objective_value(mz))
# println("Nodal objective is : ", objective_value(m1) + objective_value(m2) + objective_value(m3))




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
println("BENDERS SOLUTION 1: ", vals)
println("OBJECTIVE OF BENDERS WAS: ", UB_hist1[end])
println("OBJECTIVE OF NODAL MONOLITHIC WAS: ", objective_value(m1))

myinputs_decomp = GenX.separate_inputs_subperiods(n_inputs[2]);
# nodal_setup_Benders = deepcopy(nodal_setup)
# nodal_setup_Benders["Benders"] = 1
benders_inputs = GenX.generate_benders_inputs(mysetup,n_inputs[2],myinputs_decomp)
planning_problem2, planning_sol2, operational_sol2, LB_hist,UB_hist2, cpu_time,feasibility_hist2, build_decisions2  = GenX.benders(benders_inputs,mysetup,n_inputs[2]);


vals = [0.]
for k in keys(planning_sol2.values)
    if occursin("vNEW_TRANS_CAP", k)
        vals[1] += planning_sol2.values[k]
    end
end
println("BENDERS SOLUTION 2: ", vals)
println("OBJECTIVE OF BENDERS WAS: ", UB_hist2[end])
println("OBJECTIVE OF NODAL MONOLITHIC WAS: ", objective_value(m2))


myinputs_decomp = GenX.separate_inputs_subperiods(n_inputs[3]);
# nodal_setup_Benders = deepcopy(nodal_setup)
# nodal_setup_Benders["Benders"] = 1
benders_inputs = GenX.generate_benders_inputs(mysetup,n_inputs[3],myinputs_decomp)
planning_problem3, planning_sol3, operational_sol3, LB_hist,UB_hist3, cpu_time,feasibility_hist3, build_decisions3  = GenX.benders(benders_inputs,mysetup,n_inputs[3]);

vals = [0.]
for k in keys(planning_sol3.values)
    if occursin("vNEW_TRANS_CAP", k)
        vals[1] += planning_sol3.values[k]
    end
end
println("BENDERS SOLUTION 3: ", vals)
println("OBJECTIVE OF BENDERS WAS: ", UB_hist3[end])
println("OBJECTIVE OF NODAL MONOLITHIC WAS: ", objective_value(m3))


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
        val1 = planning_sol2.values["vNEW_TRANS_CAP_DECISION_INT[$new_line,1]"]
        fix(m2[:vNEW_TRANS_CAP_DECISION_INT][new_line, 1], val1, force = true)
        val2 = planning_sol2.values["vNEW_TRANS_CAP_DECISION_INT[$new_line,2]"]
        fix(m2[:vNEW_TRANS_CAP_DECISION_INT][new_line, 2], val2, force = true)
    end
    optimize!(m2)
end
if UB_hist3[end] < objective_value(m3)
    l2l_map = n_inputs[3]["l2l_map_cand"]
    for k in keys(l2l_map)
        old_line = k
        new_line = l2l_map[k]
        val1 = planning_sol3.values["vNEW_TRANS_CAP_DECISION_INT[$new_line,1]"]
        fix(m3[:vNEW_TRANS_CAP_DECISION_INT][new_line, 1], val1, force = true)
        val2 = planning_sol3.values["vNEW_TRANS_CAP_DECISION_INT[$new_line,2]"]
        fix(m3[:vNEW_TRANS_CAP_DECISION_INT][new_line, 2], val2, force = true)
    end
    optimize!(m3)
end

println("Zonal objective is : ", objective_value(mz))
println("Nodal objective is : ", objective_value(m1) + objective_value(m2) + objective_value(m3))

total_vNSE = sum(value.(m1[:vNSE])) + sum(value.(m2[:vNSE])) + sum(value.(m3[:vNSE]))

println("TOTAL vNSE NODAL = ", total_vNSE)
println("TOTAL vNSE ZONAL = ", sum(value.(mz[:vNSE])))

total_overproduction = sum(value.(m1[:vOverProduction])) + sum(value.(m2[:vOverProduction])) + sum(value.(m3[:vOverProduction]))

println("TOTAL overproduction NODAL = ", total_overproduction)
println("TOTAL overproduction ZONAL = ", sum(value.(mz[:vOverProduction])))


total_vCAP = sum(value.(m1[:vCAP])) + sum(value.(m2[:vCAP])) + sum(value.(m3[:vCAP]))

aggregated_vCAP = sum(value.(mz[:vCAP]))

println("TOTAL vCAP NODAL = ", total_vCAP)
println("TOTAL vCAP ZONAL = ", aggregated_vCAP)

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

println(vP_by_zone_nodal)
println(vP_by_zone_zonal)


println("MODEL 1")
for (i, v) in enumerate(m1[:vNEW_TRANS_CAP_DECISION_INT])
    if value(v) > 0
        println(i, "   ", v, "   ", value(v))
    end
end
for (i, v) in enumerate(m1[:vCAP])
    if value(v) > 0
        println(i, "   ", v, "   ", value(v))
    end
end
println()
println("MODEL 2")
for (i, v) in enumerate(m2[:vNEW_TRANS_CAP_DECISION_INT])
    if value(v) > 0
        println(i, "   ", v, "   ", value(v))
    end
end
for (i, v) in enumerate(m2[:vCAP])
    if value(v) > 0
        println(i, "   ", v, "   ", value(v))
    end
end
println()
println("MODEL 3")
for (i, v) in enumerate(m3[:vNEW_TRANS_CAP_DECISION_INT])
    if value(v) > 0
        println(i, "   ", v, "   ", value(v))
    end
end
for (i, v) in enumerate(m3[:vCAP])
    if value(v) > 0
        println(i, "   ", v, "   ", value(v))
    end
end