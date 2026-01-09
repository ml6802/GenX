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

function find_tech_type_by_id(id, techs) 
    for t in techs
        if PSIP.get_id(t) == id
            return typeof(t)
        end
    end
    return nothing
end
function find_tech_by_id(id, techs) 
    for t in techs
        if PSIP.get_id(t) == id
            return t
        end
    end
    return nothing
end
function find_component_by_id(id, techs) 
    for t in techs
        if PSY.get_number(t) == id
            return t
        end
    end
    return nothing
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

###################### SOLUTIONS WITH TRANSMISSION ######################
mysetup["DC_OPF"] = 1
myinputs = GenX.load_inputs(mysetup, case, p)

optimizer = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 300, "MIPGap" => 1e-3)

# Add expected candidate line data
# also scales demands up by 4x
load_candidates_base(myinputs, 48)

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
            parent(resource)[:cap_size] = 200
        end
    end
end

mysetup["DC_OPF"] = 0
mysetup["NetworkExpansion"] = 1

# Build zonal inputs (this is a downscaling step)
z_inputs = build_zonal_inputs(myinputs, zone_map, 3)

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
# No new transmission lines occur, so we add a constraint to force building; objective value is very similar as without this constraint
@constraint(mz, sum(mz[:vNEW_TRANS_LINES]) >= 1)
optimize!(mz)

# Save investment solutions
# NOTE: These are at the zonal resolution, so each new technology doesn't belong to a node yet
investment_solutions = Dict()
techs = collect(get_technologies(ResourceTechnology, p))
index_to_technology = z_inputs["index_to_technology"]
#NOTE: SOLUTIONS ARE IN MW
for i in z_inputs["NEW_CAP"]
    new_cap_val = value(mz[:vCAP][i])
    if new_cap_val > 0
        resource = z_inputs["RESOURCES"][i]
        name = GenX.resource_name(resource)
        tech_id = index_to_technology[i]
        tech_type = find_tech_type_by_id(tech_id, techs)
        tuple_key = (tech_type, name)
        investment_solutions[tuple_key] = new_cap_val * GenX.cap_size(resource)
    end
end


# Build dictionary of candidate line solutions
# for the zonal problem, the tuple includes the type of line, the name of the line,
# and the from/to AREA (not nodes). 
transmission_solutions = Dict()
buses = collect(get_components(Bus, p.base_system))
lines = collect(get_technologies(TransmissionTechnology, p))
lines = [l for l in lines if !(occursin("new", l.name))]
for i in z_inputs["CANDIDATE_LINES"]
    new_line_val = value(mz[:vNEW_TRANS_LINES][i])
    if new_line_val > 0
        from_area = "area"*string(Int(findfirst(x -> x == 1, z_inputs["pNet_Map"][i, :])))
        to_area = "area"*string(Int(findfirst(x -> x == -1, z_inputs["pNet_Map"][i, :])))

        index = z_inputs["z2l_map"][i]

        tech_id = index_to_line[index - 120]
        line = find_tech_by_id(tech_id, lines)
        #start_node_name = get_start_node(line)
        #end_node_name = get_end_node(line)
        line_name = line.name * "_new"
        tuple_key = (typeof(line), line_name, from_area, to_area)
        transmission_solutions[tuple_key] = z_inputs["Line_Reinforcement_Cap_Size"][i]
    end
end

# Add new resources, one for every node
# Append data to the inputs dictionary for these new resource copies
GenX.expand_new_cap_resources_to_nodal!(myinputs, mysetup, p, "")
GenX.load_generators_variability!(mysetup, p, myinputs)

# Portfolio contains no capacity or unit sizes
# For new capacity, set it to be 100 MW increments
if haskey(mysetup, "IntegerInvestments")
    if mysetup["IntegerInvestments"] == 1
        for i in myinputs["NEW_CAP"]
            resource = myinputs["RESOURCES"][i]
            parent(resource)[:cap_size] = 200
        end
    end
end

# Build a monolithic model of nodal system with DCOPF constraints (no network expansion)
m = GenX.generate_model(mysetup, myinputs, optimizer)
# No new transmission lines occur, so we add a constraint to force building; objective value is very similar as without this constraint
@constraint(m, sum(m[:vNEW_TRANS_LINES]) >= 5)
# Solve model
optimize!(m)

# Save solutions
investment_solutions_nodal = Dict()
techs = collect(get_technologies(ResourceTechnology, p))
index_to_technology = myinputs["index_to_technology"] #maps GenX's index to Technology index
#NOTE: SOLUTIONS ARE IN MW
for i in myinputs["NEW_CAP"]
    new_cap_val = value(m[:vCAP][i])
    if new_cap_val > 1e-4
        resource = myinputs["RESOURCES"][i]
        name = GenX.resource_name(resource)
        region = GenX.region(resource)
        tech_id = index_to_technology[i]
        tech_type = find_tech_type_by_id(tech_id, techs)
        region_name = PSIP.get_name(region)
        unit_name = "$(region_name)_$(name)"
        tuple_key = (tech_type, region, name, unit_name)
        investment_solutions_nodal[tuple_key] = new_cap_val * GenX.cap_size(resource)
    end
end

# Build dictionary of candidate line solutions
# for the nodal problem, the tuple includes the type of line, the name of the line,
# and the from/to node/bus names
transmission_solutions_nodal = Dict()
index_to_region = myinputs["index_to_region"] # maps from GenX zone id to PSY bus ID
region_to_area = myinputs["region_to_area"] # maps from PSY bus ID to PSY area
index_to_line = myinputs["index_to_line"]
buses = collect(get_components(Bus, p.base_system))
lines = collect(get_technologies(TransmissionTechnology, p))
lines = [l for l in lines if !(occursin("new", l.name))]
pNet_Map = myinputs["pNet_Map"]
for i in myinputs["CANDIDATE_LINES"]
    new_line_val = value(m[:vNEW_TRANS_LINES][i])
    if new_line_val > 0
        tech_id = index_to_line[i - 120]
        line = find_tech_by_id(tech_id, lines)
        start_node_name = get_start_node(line)
        end_node_name = get_end_node(line)
        line_name = line.name * "_new"
        tuple_key = (typeof(line),line_name, start_node_name, end_node_name)
        transmission_solutions_nodal[tuple_key] = myinputs["Line_Reinforcement_Cap_Size"][i]
    end
end