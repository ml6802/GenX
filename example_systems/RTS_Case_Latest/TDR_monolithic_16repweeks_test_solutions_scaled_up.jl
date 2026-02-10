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

optimizer = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 64800, "MIPGap" => 5e-3)

load_candidates_base(myinputs, 8784, add_new_corridors = true)
update_fuel_and_investment_costs(myinputs)

# Run TDR
TDR_params = Dict("MinPeriods" => 16, "MaxPeriods" => 16, "UseExtremePeriods" => 1)
cluster_inputs(case, settings_path, mysetup; inputs = myinputs, TDR_params = TDR_params)

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

m = GenX.generate_model(mysetup, myinputs, optimizer)


# DCOPF Full solution
println("SOLVING WITH FULL DCOPF SOLUTION")

new_cap = [178,90,18,30,56,172,181,192,204,100,201,171,207,202,5,87]
new_cap_sizes = [1,1,1,1,2,2,1,1,1,1,2,1,2,3,1,2,]
new_reconductor = [82, 5, 75, 80, 19, 106]
new_lines = [212,209,143,205,223,233,169,231]
r_low = [5,84,75,45,]
r_high = [5 ]
r_low_sizes = [50,40,50,40,]
r_high_sizes = [58.3769]

for i in myinputs["NEW_CAP"]
    if !(i in new_cap)
        fix(m[:vCAP][i], 0, force = true)
    end
end

for (i, idx) in enumerate(new_cap)
    fix(m[:vCAP][idx], new_cap_sizes[i], force = true)
end

for var in m[:vRECONDUCTOR_SLACK_LOW]
    fix(var, 0, force = true)
end
for var in m[:vRECONDUCTOR_SLACK_HIGH]
    fix(var, 0, force = true)
end

for (i, idx) in enumerate(r_low)
    fix(m[:vRECONDUCTOR_SLACK_LOW][idx], r_low_sizes[i], force = true)
end

for (i, idx) in enumerate(r_high)
    fix(m[:vRECONDUCTOR_SLACK_HIGH][idx], r_high_sizes[i], force = true)
end

for i in myinputs["CANDIDATE_LINES"]
    if i in new_lines
        fix(m[:vNEW_TRANS_CAP_DECISION_INT][i], 1, force=true)
    else
        fix(m[:vNEW_TRANS_CAP_DECISION_INT][i], 0, force=true)
    end
end

optimize!(m)

println("OBJECTIVE VALUE IS ", objective_value(m))
println("TOTAL UNSERVED ENERGY IS ", sum(value.(m[:vNSE])))
flush(stdout)

# Waterflow full solution
println("SOLVING WITH LP Solution of BD")

# new_cap = [90,30,204,189,222,187,202,174,221]
# new_cap_sizes = [2,1,7,2,1,1,2,3,4]
# new_reconductor = [45,84,19]
# new_lines = [212,201,204,165]
# r_low = [84,45,19]
# r_high = [45,84,]
# r_low_sizes = [40,40,5.908]
# r_high_sizes = [60,60]

new_cap = [90,18,191,56,172,181,204,201,171,207,217,202,5]
new_cap_sizes = [1,2,1,2,2,1,1,5,1,2,1,2,2]
new_lines = [212,134,197,167,209,143,122,223]
r_low = [85,5,84,75,57,45,]
r_high = [85]
r_low_sizes = [50,50,40,50,50,40,]
r_high_sizes = [50.290474]

for i in myinputs["NEW_CAP"]
    if !(i in new_cap)
        fix(m[:vCAP][i], 0, force = true)
    end
end

for (i, idx) in enumerate(new_cap)
    fix(m[:vCAP][idx], new_cap_sizes[i], force = true)
end

for var in m[:vRECONDUCTOR_SLACK_LOW]
    fix(var, 0, force = true)
end
for var in m[:vRECONDUCTOR_SLACK_HIGH]
    fix(var, 0, force = true)
end

for (i, idx) in enumerate(r_low)
    fix(m[:vRECONDUCTOR_SLACK_LOW][idx], r_low_sizes[i], force = true)
end

for (i, idx) in enumerate(r_high)
    fix(m[:vRECONDUCTOR_SLACK_HIGH][idx], r_high_sizes[i], force = true)
end

for i in myinputs["CANDIDATE_LINES"]
    if i in new_lines
        fix(m[:vNEW_TRANS_CAP_DECISION_INT][i], 1, force=true)
    else
        fix(m[:vNEW_TRANS_CAP_DECISION_INT][i], 0, force=true)
    end
end

optimize!(m)

println("OBJECTIVE VALUE IS ", objective_value(m))
println("TOTAL UNSERVED ENERGY IS ", sum(value.(m[:vNSE])))

flush(stdout)

#=

# DCOPF Sampled Lines 1

new_cap = [90,18,188,56,172,182,181,219,204,189,222,228,183,174,5,87]
new_cap_sizes = [1,1,1,1,1,2,1,3,1,1,1,2,2,1,1,2]
new_reconductor = [5,57]
new_lines = []
r_low = [5,57]
r_high = [57]
r_low_sizes = [50,50]
r_high_sizes = [26.956]
println("SOLVING WITH DCOPF SAMPLED SET 1 SOLUTION")
for i in myinputs["NEW_CAP"]
    if !(i in new_cap)
        fix(m[:vCAP][i], 0, force = true)
    end
end

for (i, idx) in enumerate(new_cap)
    fix(m[:vCAP][idx], new_cap_sizes[i], force = true)
end

for var in m[:vRECONDUCTOR_SLACK_LOW]
    fix(var, 0, force = true)
end
for var in m[:vRECONDUCTOR_SLACK_HIGH]
    fix(var, 0, force = true)
end

for (i, idx) in enumerate(r_low)
    fix(m[:vRECONDUCTOR_SLACK_LOW][idx], r_low_sizes[i], force = true)
end

for (i, idx) in enumerate(r_high)
    fix(m[:vRECONDUCTOR_SLACK_HIGH][idx], r_high_sizes[i], force = true)
end

for i in myinputs["CANDIDATE_LINES"]
    if i in new_lines
        fix(m[:vNEW_TRANS_CAP_DECISION_INT][i], 1, force=true)
    else
        fix(m[:vNEW_TRANS_CAP_DECISION_INT][i], 0, force=true)
    end
end

optimize!(m)

println("OBJECTIVE VALUE IS ", objective_value(m))
println("TOTAL UNSERVED ENERGY IS ", sum(value.(m[:vNSE])))
println("TOTAL OVERPRODUCTION IS ", sum(value.(m[:vOverProduction])))

flush(stdout)

# Waterflow Sampled Lines 1
new_cap = [18,255,117,56,172,219,203,222,183,174,5,87]
new_cap_sizes = [1,2,2,2,2,4,2,1,2,2,2,1]
new_reconductor = [5,57]
new_lines = [164]#[134]
r_low = [5,57]
r_high = []
r_low_sizes = [50,50]
r_high_sizes = []

println("SOLVING WITH WATERFLOW SAMPLED SET 1 SOLUTION")

for i in myinputs["NEW_CAP"]
    if !(i in new_cap)
        fix(m[:vCAP][i], 0, force = true)
    end
end

for (i, idx) in enumerate(new_cap)
    fix(m[:vCAP][idx], new_cap_sizes[i], force = true)
end


for var in m[:vRECONDUCTOR_SLACK_LOW]
    fix(var, 0, force = true)
end
for var in m[:vRECONDUCTOR_SLACK_HIGH]
    fix(var, 0, force = true)
end

for (i, idx) in enumerate(r_low)
    fix(m[:vRECONDUCTOR_SLACK_LOW][idx], r_low_sizes[i], force = true)
end

for (i, idx) in enumerate(r_high)
    fix(m[:vRECONDUCTOR_SLACK_HIGH][idx], r_high_sizes[i], force = true)
end

for i in myinputs["CANDIDATE_LINES"]
    if i in new_lines
        fix(m[:vNEW_TRANS_CAP_DECISION_INT][i], 1, force=true)
    else
        fix(m[:vNEW_TRANS_CAP_DECISION_INT][i], 0, force=true)
    end
end

optimize!(m)

println("OBJECTIVE VALUE IS ", objective_value(m))
println("TOTAL UNSERVED ENERGY IS ", sum(value.(m[:vNSE])))
println("TOTAL OVERPRODUCTION IS ", sum(value.(m[:vOverProduction])))

flush(stdout)



# DCOPF Sampled Lines 2
new_cap = [18,117,56,181,219,204,203,189,228,183,217,173,187,202,174,5,87,221]
new_cap_sizes = [1,1,1,2,2,1,1,1,1,1,2,1,1,1,1,1,2,1]
new_reconductor = [85,5,75,19]
new_lines = [134]# [124]
r_low = [85,5,75,19]
r_high = [85]
r_low_sizes = [50,50,50,3.2453]
r_high_sizes = [75]


println("SOLVING WITH DCOPF SAMPLED SET 2 SOLUTION")

for i in myinputs["NEW_CAP"]
    if !(i in new_cap)
        fix(m[:vCAP][i], 0, force = true)
    end
end

for (i, idx) in enumerate(new_cap)
    fix(m[:vCAP][idx], new_cap_sizes[i], force = true)
end


for var in m[:vRECONDUCTOR_SLACK_LOW]
    fix(var, 0, force = true)
end
for var in m[:vRECONDUCTOR_SLACK_HIGH]
    fix(var, 0, force = true)
end

for (i, idx) in enumerate(r_low)
    fix(m[:vRECONDUCTOR_SLACK_LOW][idx], r_low_sizes[i], force = true)
end

for (i, idx) in enumerate(r_high)
    fix(m[:vRECONDUCTOR_SLACK_HIGH][idx], r_high_sizes[i], force = true)
end

for i in myinputs["CANDIDATE_LINES"]
    if i in new_lines
        fix(m[:vNEW_TRANS_CAP_DECISION_INT][i], 1, force=true)
    else
        fix(m[:vNEW_TRANS_CAP_DECISION_INT][i], 0, force=true)
    end
end

optimize!(m)

println("OBJECTIVE VALUE IS ", objective_value(m))
println("TOTAL UNSERVED ENERGY IS ", sum(value.(m[:vNSE])))
println("TOTAL OVERPRODUCTION IS ", sum(value.(m[:vOverProduction])))

flush(stdout)

# Waterflow Sampled Lines 2
new_cap = [18,188,172,181,219,203,189,228,217,5]
new_cap_sizes = [1,2,2,6,4,3,1,1,1,1,]
new_reconductor = [75,85,49,5,116]
new_lines = [151,210]#[132,151]
r_low = [85,49,5,75,116,]
r_high = [75,5,85,49]
r_low_sizes = [50,40,50,50,40,]
r_high_sizes = [75,34.884,75,60]


println("SOLVING WITH WATERFLOW SAMPLED SET 2 SOLUTION")

for i in myinputs["NEW_CAP"]
    if !(i in new_cap)
        fix(m[:vCAP][i], 0, force = true)
    end
end

for (i, idx) in enumerate(new_cap)
    fix(m[:vCAP][idx], new_cap_sizes[i], force = true)
end


for var in m[:vRECONDUCTOR_SLACK_LOW]
    fix(var, 0, force = true)
end
for var in m[:vRECONDUCTOR_SLACK_HIGH]
    fix(var, 0, force = true)
end

for (i, idx) in enumerate(r_low)
    fix(m[:vRECONDUCTOR_SLACK_LOW][idx], r_low_sizes[i], force = true)
end

for (i, idx) in enumerate(r_high)
    fix(m[:vRECONDUCTOR_SLACK_HIGH][idx], r_high_sizes[i], force = true)
end

for i in myinputs["CANDIDATE_LINES"]
    if i in new_lines
        fix(m[:vNEW_TRANS_CAP_DECISION_INT][i], 1, force=true)
    else
        fix(m[:vNEW_TRANS_CAP_DECISION_INT][i], 0, force=true)
    end
end

optimize!(m)

println("OBJECTIVE VALUE IS ", objective_value(m))
println("TOTAL UNSERVED ENERGY IS ", sum(value.(m[:vNSE])))
println("TOTAL OVERPRODUCTION IS ", sum(value.(m[:vOverProduction])))

flush(stdout)



# DCOPF Sampled Lines 3
new_cap = [90,18,56,182,181,219,189,222,228,183,217,173,202,5,87,221]
new_cap_sizes = [1,1,1,1,1,1,1,1,2,3,2,2,1,1,1,2]
new_reconductor = [75,84,]
new_lines = [231]#[158]
r_low = [85,75]
r_high = [75]
r_low_sizes = [50,50]
r_high_sizes = [75]


println("SOLVING WITH DCOPF SAMPLED SET 3 SOLUTION")

for i in myinputs["NEW_CAP"]
    if !(i in new_cap)
        fix(m[:vCAP][i], 0, force = true)
    end
end

for (i, idx) in enumerate(new_cap)
    fix(m[:vCAP][idx], new_cap_sizes[i], force = true)
end


for var in m[:vRECONDUCTOR_SLACK_LOW]
    fix(var, 0, force = true)
end
for var in m[:vRECONDUCTOR_SLACK_HIGH]
    fix(var, 0, force = true)
end

for (i, idx) in enumerate(r_low)
    fix(m[:vRECONDUCTOR_SLACK_LOW][idx], r_low_sizes[i], force = true)
end

for (i, idx) in enumerate(r_high)
    fix(m[:vRECONDUCTOR_SLACK_HIGH][idx], r_high_sizes[i], force = true)
end

for i in myinputs["CANDIDATE_LINES"]
    if i in new_lines
        fix(m[:vNEW_TRANS_CAP_DECISION_INT][i], 1, force=true)
    else
        fix(m[:vNEW_TRANS_CAP_DECISION_INT][i], 0, force=true)
    end
end

optimize!(m)

println("OBJECTIVE VALUE IS ", objective_value(m))
println("TOTAL UNSERVED ENERGY IS ", sum(value.(m[:vNSE])))
println("TOTAL OVERPRODUCTION IS ", sum(value.(m[:vOverProduction])))

flush(stdout)

# Waterflow Sampled Lines 3
new_cap = [18,188,56,218,181,100,222,217,173,174,87]
new_cap_sizes = [1,1,3,1,3,1,3,3,1,1,4,]
new_reconductor = [75,85,26]
# new_lines = [158,139,162,152,122,128]
new_lines = [231, 183, 242, 219, 125, 162]
r_low = [85,75,26]
r_high = [75,85,26]
r_low_sizes = [50,50,72.2]
r_high_sizes = [75,75,37.025]


println("SOLVING WITH WATERFLOW SAMPLED SET 3 SOLUTION")

for i in myinputs["NEW_CAP"]
    if !(i in new_cap)
        fix(m[:vCAP][i], 0, force = true)
    end
end

for (i, idx) in enumerate(new_cap)
    fix(m[:vCAP][idx], new_cap_sizes[i], force = true)
end


for var in m[:vRECONDUCTOR_SLACK_LOW]
    fix(var, 0, force = true)
end
for var in m[:vRECONDUCTOR_SLACK_HIGH]
    fix(var, 0, force = true)
end

for (i, idx) in enumerate(r_low)
    fix(m[:vRECONDUCTOR_SLACK_LOW][idx], r_low_sizes[i], force = true)
end

for (i, idx) in enumerate(r_high)
    fix(m[:vRECONDUCTOR_SLACK_HIGH][idx], r_high_sizes[i], force = true)
end

for i in myinputs["CANDIDATE_LINES"]
    if i in new_lines
        fix(m[:vNEW_TRANS_CAP_DECISION_INT][i], 1, force=true)
    else
        fix(m[:vNEW_TRANS_CAP_DECISION_INT][i], 0, force=true)
    end
end

optimize!(m)

println("OBJECTIVE VALUE IS ", objective_value(m))
println("TOTAL UNSERVED ENERGY IS ", sum(value.(m[:vNSE])))
println("TOTAL OVERPRODUCTION IS ", sum(value.(m[:vOverProduction])))

flush(stdout)
=#