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

#myinputs["pTrans_Max"] .*= 0.3
myinputs["pD"] .*= 3
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
myinputs["hours_per_subperiod"] = 3528
myinputs["INTERIOR_SUBPERIODS"] = [i for i in 2:myinputs["hours_per_subperiod"]]
myinputs["T"] = 3528


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
