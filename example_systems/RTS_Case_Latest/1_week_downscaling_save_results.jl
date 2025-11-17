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
p.internal.ext["Timesteps_per_Rep_Period"] = 48
p.internal.ext["hours_per_subperiod"] = 48
p.internal.ext["sub_weights"] = [8784 for i in 1:p.internal.ext["Rep_Periods"]] 

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

myinputs = GenX.load_inputs(mysetup, case, p)

optimizer = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 300, "MIPGap" => 1e-4)

# Add expected candidate line data
# also scales demands up by 4x
load_no_candidates(myinputs, 48)

# Set additional inputs so it only solves for one week
myinputs["hours_per_subperiod"] = 48
myinputs["INTERIOR_SUBPERIODS"] = [i for i in 2:myinputs["hours_per_subperiod"]]
myinputs["T"] = 48

# Portfolio contains no capacity or unit sizes
# For new capacity, set it to be 100 MW increments
if haskey(mysetup, "IntegerInvestments")
    if mysetup["IntegerInvestments"] == 1
        for i in myinputs["NEW_CAP"]
            resource = myinputs["RESOURCES"][i]
            parent(resource)[:cap_size] = 100
        end
    end
end

# Build zonal inputs (this is a downscaling step)
z_inputs = build_zonal_inputs(myinputs, zone_map, 3)

solver = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 900, "MIPGap" => 1e-3)
###### ZONAL ######
zonal_setup = deepcopy(mysetup)
optimizer = solver
###### ZONAL ######
zonal_setup["unfix_slacks"] = 0
zonal_setup["NetworkExpansion"] = 1
zonal_setup["IntegerInvestments"] = 1
zonal_setup["DC_OPF"] = 0

# Solve zonal model
mz = run_zonal_model!(z_inputs, zonal_setup, optimizer)

# Save investment solutions
# NOTE: These are at the zonal resolution, so each new technology doesn't belong to a node yet
investment_solutions = Dict()
techs = collect(get_technologies(ResourceTechnology, p))
index_to_technology = z_inputs["index_to_technology"]
function find_tech_type_by_id(id, techs) 
    for t in techs
        if PSIP.get_id(t) == id
            return typeof(t)
        end
    end
    return nothing
end
for i in z_inputs["NEW_CAP"]
    new_cap_val = value(mz[:vCAP][i])
    if new_cap_val > 0
        resource = z_inputs["RESOURCES"][i]
        name = parent(resource)[:resource]
        tech_id = index_to_technology[i]
        tech_type = find_tech_type_by_id(tech_id, techs)
        tuple_key = (tech_type, name)
        investment_solutions[tuple_key] = new_cap_val * GenX.cap_size(resource)
    end
end

# Add new resources, one for every node
# Append data to the inputs dictionary for these new resource copies
GenX.expand_new_cap_resources_to_nodal!(myinputs, mysetup, p, "")
GenX.load_generators_variability!(mysetup, p, myinputs)
mysetup["DC_OPF"] = 0
mysetup["NetworkExpansion"] = 0

# Portfolio contains no capacity or unit sizes
# For new capacity, set it to be 100 MW increments
if haskey(mysetup, "IntegerInvestments")
    if mysetup["IntegerInvestments"] == 1
        for i in myinputs["NEW_CAP"]
            resource = myinputs["RESOURCES"][i]
            parent(resource)[:cap_size] = 100
        end
    end
end

# Build a monolithic model of nodal system with DCOPF constraints (no network expansion)
m = GenX.generate_model(mysetup, myinputs, optimizer)

# Solve model
optimize!(m)

# Save solutions
investment_solutions_nodal = Dict()
techs = collect(get_technologies(ResourceTechnology, p))
index_to_technology = myinputs["index_to_technology"]
for i in myinputs["NEW_CAP"]
    new_cap_val = value(m[:vCAP][i])
    if new_cap_val > 0
        resource = myinputs["RESOURCES"][i]
        name = parent(resource)[:resource]
        region = parent(resource)[:region]
        tech_id = index_to_technology[i]
        tech_type = find_tech_type_by_id(tech_id, techs)
        tuple_key = (tech_type, region, name)
        investment_solutions_nodal[tuple_key] = new_cap_val * GenX.cap_size(resource)
    end
end

