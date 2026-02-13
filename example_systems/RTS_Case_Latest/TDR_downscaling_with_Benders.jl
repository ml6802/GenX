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
techs = collect(get_technologies(SupplyTechnology, p))


cpus_per_task = parse(Int, ENV["SLURM_CPUS_PER_TASK"]);
addprocs(cpus_per_task)
println("Adding processors")
@everywhere begin
    import Pkg
    Pkg.activate("/scratch/gpfs/JENKINS/dc0173/git/forked/reconductoring/GenX")
end

println("Number of procs: ", nprocs())
println("Number of workers: ", nworkers())
for i in workers()
    id, pid, host = fetch(@spawnat i (myid(), getpid(), gethostname()))
    println(id, " " , pid, " ", host)
end
@everywhere using GenX, Distributed


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

node_names = ["Alder", "Alger", "Ali", "Archer", "Austen", "Bach", "Bailey", "Bain", "Bajer", "Baker", "Balch", "Bardeen", "Barkla", "Barlow", "Caine", "Calvin", "Camus", "Carew", "Carrel", "Carter", "Caxton", "Comte"]

# Split node names by initial letter (A, B, C)
a_node_names = filter(n -> startswith(n, "A"), node_names)
b_node_names = filter(n -> startswith(n, "B"), node_names)
c_node_names = filter(n -> startswith(n, "C"), node_names)

# Set a reproducible seed (outside the function)
function sample_four(names::AbstractVector{<:AbstractString})
    @assert length(names) >= 3 "Need at least 3 names (got $(length(names)))"
    idxs = sort(randperm(length(names))[1:3])
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

optimizer = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 3600, "MIPGap" => 1e-3)

load_candidates_base(myinputs, 8784, add_new_corridors = true)
update_fuel_and_investment_costs(myinputs)


GenX.expand_new_cap_resources_to_nodal!(myinputs, mysetup, p, "")


mysetup["IntegerInvestments"] = 1
mysetup["DC_OPF"] = 1
mysetup["NetworkExpansion"] = 1

if haskey(mysetup, "IntegerInvestments")
    if mysetup["IntegerInvestments"] == 1
        for i in myinputs["NEW_CAP"]
            resource = myinputs["RESOURCES"][i]
            parent(resource)[:cap_size] = 200
        end
    end
end

# Run TDR
TDR_params = Dict("MinPeriods" => 16, "MaxPeriods" => 16, "UseExtremePeriods" => 1)
cluster_inputs(case, settings_path, mysetup; inputs = myinputs, TDR_params = TDR_params, random = false)

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
flush(stdout)

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
# solve nodal models
# m1 = GenX.generate_model(nodal_setup, n_inputs[1], optimizer)
m1 = build_nodal_resolution_model(nodal_setup, n_inputs[1], optimizer)

set_nodal_capacity_builds(n_inputs[1], m1)

#optimize!(m1)

m2 = build_nodal_resolution_model(nodal_setup, n_inputs[2], optimizer)

set_nodal_capacity_builds(n_inputs[2], m2)

#optimize!(m2)

m3 = build_nodal_resolution_model(nodal_setup, n_inputs[3], optimizer)

set_nodal_capacity_builds(n_inputs[3], m3)

#optimize!(m3)


# Run Benders
benders_settings_path = GenX.get_settings_path(case, "benders_settings.yml")
mysetup_benders = GenX.configure_benders(benders_settings_path) 

mysetup["DC_OPF"] = 1
mysetup["ptdf"] = 0
mysetup["bilinear"] = 0
mysetup["disaggregate"] = 0
mysetup["unfix_slacks"] = 1
mysetup["BD_post_warmstart_integer_routine"] = 1
mysetup["SOS1"] = 0
mysetup["BD_regularization_switch"] = 1
mysetup["BD_Stab_Method"] = "int_level_set"
mysetup = merge(mysetup,mysetup_benders);

settings_path = GenX.get_settings_path(case)    
mysetup["settings_path"] = settings_path;
mysetup["NetworkExpansion"] = 1
mysetup["Benders"] = 1
mysetup["BD_integer_routine"] = 1
mysetup["BD_MaxCpuTime"] = 12600


myinputs_decomp = GenX.separate_inputs_subperiods(n_inputs[1]);
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
# println("OBJECTIVE OF NODAL MONOLITHIC WAS: ", objective_value(m1))

myinputs_decomp = GenX.separate_inputs_subperiods(n_inputs[2]);
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
# println("OBJECTIVE OF NODAL MONOLITHIC WAS: ", objective_value(m2))


myinputs_decomp = GenX.separate_inputs_subperiods(n_inputs[3]);
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
# println("OBJECTIVE OF NODAL MONOLITHIC WAS: ", objective_value(m3))

println("SETTING SOLUTION TO BENDERS ON MODEL 1")
for new_line in n_inputs[1]["CANDIDATE_LINES"]
    val1 = planning_sol1.values["vNEW_TRANS_CAP_DECISION_INT[$new_line]"]
    fix(m1[:vNEW_TRANS_CAP_DECISION_INT][new_line], val1, force = true)
end
for k in n_inputs[1]["NEW_CAP"]
    val1 = planning_sol1.values["vCAP[$k]"]
    fix(m1[:vCAP][k], val1, force = true)
end
optimize!(m1)

println("SETTING SOLUTION TO BENDERS ON MODEL 2")
for new_line in n_inputs[2]["CANDIDATE_LINES"]
    val = planning_sol2.values["vNEW_TRANS_CAP_DECISION_INT[$new_line]"]
    fix(m2[:vNEW_TRANS_CAP_DECISION_INT][new_line], val, force = true)
end
for k in n_inputs[2]["NEW_CAP"]
    val2 = planning_sol2.values["vCAP[$k]"]
    fix(m2[:vCAP][k], val2, force = true)
end
optimize!(m2)

println("SETTING SOLUTION TO BENDERS ON MODEL 3")
for new_line in n_inputs[3]["CANDIDATE_LINES"]
    val = planning_sol3.values["vNEW_TRANS_CAP_DECISION_INT[$new_line]"]
    fix(m3[:vNEW_TRANS_CAP_DECISION_INT][new_line], val, force = true)
end
for k in n_inputs[3]["NEW_CAP"]
    val3 = planning_sol3.values["vCAP[$k]"]
    fix(m3[:vCAP][k], val3, force = true)
end
optimize!(m3)

println()
println()
println("Objective of JuMP model 1 = ", objective_value(m1))
println("Objective of Benders = ", UB_hist1[end])
println("Objective of JuMP model 2 = ", objective_value(m2))
println("Objective of Benders = ", UB_hist2[end])
println("Objective of JuMP model 3 = ", objective_value(m3))
println("Objective of Benders = ", UB_hist3[end])
println()
println()
flush(stdout)

zonal_objective = objective_value(mz)
nodal_objective = objective_value(m1) + objective_value(m2) + objective_value(m3)
println("ZONAL OBJECTIVE = ", zonal_objective)
println("NODAL OBJECTIVE = ", nodal_objective)

println("Number new builds = ", sum(value.(m1[:vNEW_TRANS_CAP_DECISION_INT])) + sum(value.(m2[:vNEW_TRANS_CAP_DECISION_INT])) + sum(value.(m3[:vNEW_TRANS_CAP_DECISION_INT])))


for v in mz[:vCAP]
    println(v, "   ", value(v))
end
for v in mz[:vNEW_TRANS_LINES]
    println(v, "   ", value(v))
end
for v in m1[:vCAP]
    println(v, "   ", value(v))
end
for v in m1[:vNEW_TRANS_CAP_DECISION_INT]
    println(v, "   ", value(v))
end
for v in m2[:vCAP]
    println(v, "   ", value(v))
end
for v in m2[:vNEW_TRANS_CAP_DECISION_INT]
    println(v, "   ", value(v))
end
for v in m3[:vCAP]
    println(v, "   ", value(v))
end
for v in m3[:vNEW_TRANS_CAP_DECISION_INT]
    println(v, "   ", value(v))
end

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

CSV.write((@__DIR__)*"/transmission_downscaling_results_TDR_Benders.csv", new_transmission_builds_df)



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

CSV.write((@__DIR__)*"/new_cap_downscaling_results_TDR_Benders.csv", new_gen_cap_df)
