ENV["GENX_PRECOMPILE"] = "false"

import Pkg

# Pkg.activate("/home/ml6802/GenX")
# include("/home/ml6802/GenX/src/GenX.jl")

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
using Distributed, ClusterManagers

include((@__DIR__)*"/load_portfolio.jl")
include((@__DIR__)*"/../convert_input_dict.jl")

rep_periods = 26
p.internal.ext["Rep_Periods"] = rep_periods
p.internal.ext["Timesteps_per_Rep_Period"] = 168
p.internal.ext["sub_weights"] = [8784/26 for i in 1:rep_periods]
p.internal.ext["hours_per_subperiod"] = 168

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


cpus_per_task = parse(Int, ENV["SLURM_CPUS_PER_TASK"]);
addprocs(cpus_per_task)
println("Adding processors")
@everywhere begin
    import Pkg
    Pkg.activate("/scratch/gpfs/dc0173/git/forked/Mike/reconductoring/GenX")
end

println("Number of procs: ", nprocs())
println("Number of workers: ", nworkers())
for i in workers()
    id, pid, host = fetch(@spawnat i (myid(), getpid(), gethostname()))
    println(id, " " , pid, " ", host)
end
@everywhere using GenX, Distributed


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

myinputs["pDC_OPF_coeff"] .*= 2000 #2000

myinputs["CAN_RETIRE_LINES"] = CAN_RETIRE_LINES
myinputs["CANNOT_RETIRE_LINES"] = CANNOT_RETIRE_LINES
myinputs["RECONDUCTOR_LINES"] = RECONDUCTOR_LINES
myinputs["existing_to_cand_map"] = existing_to_cand_map

myinputs["hours_per_subperiod"] = 168
myinputs["INTERIOR_SUBPERIODS"] = [i for i in 2:myinputs["hours_per_subperiod"]]
myinputs["T"] = 168


mysetup["NetworkExpansion"] = 1
mysetup["Benders"] = 1

myinputs_decomp = GenX.separate_inputs_subperiods(myinputs);
benders_inputs = GenX.generate_benders_inputs(mysetup,myinputs,myinputs_decomp)

planning_problem1, planning_sol1, operational_sol1, LB_hist1,UB_hist1, cpu_time1,feasibility_hist1, build_decisions1  = GenX.benders(benders_inputs,mysetup,myinputs);


println("RUNNING 1 Month")
# println(operational_sol1.summation_map)

for i in keys(planning_sol1.values)
    if planning_sol1.values[i] != 0
        println(i, " = ", planning_sol1.values[i])
    end
end
