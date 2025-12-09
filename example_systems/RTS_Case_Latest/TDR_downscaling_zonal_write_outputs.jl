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
p.internal.ext["Timesteps_per_Rep_Period"] = 672
p.internal.ext["hours_per_subperiod"] = 672
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

node_names = ["Carew", "Chase", "Carrel", "Carter", "Cabot", "Bajer", "Baker", "Baffin", "Cabell", "Caine", "Camus", "Bach", "Bain", "Barlow", "Banks", "Balch", "Alger", "Alber", "Alder", "Avery", "Aiken"]

# Split node names by initial letter (A, B, C)
a_node_names = filter(n -> startswith(n, "A"), node_names)
b_node_names = filter(n -> startswith(n, "B"), node_names)
c_node_names = filter(n -> startswith(n, "C"), node_names)

# Set a reproducible seed (outside the function)
function sample_four(names::AbstractVector{<:AbstractString})
    @assert length(names) >= 3 "Need at least 4 names (got $(length(names)))"
    idxs = sort(randperm(length(names))[1:4])
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

optimizer = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 9600, "MIPGap" => 1e-3)

# Add expected candidate line data
# also scales demands up by 4x
load_candidates_base(myinputs, 8784)

# Run TDR
cluster_inputs(case, settings_path, mysetup; inputs = myinputs)

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
t = @elapsed mz = run_zonal_model!(z_inputs, zonal_setup, optimizer)
myinputs["solve_time"] = t
outputs_path = GenX.get_default_output_folder(case)
elapsed_time = @elapsed outputs_path = GenX.write_outputs(mz,
    outputs_path,
    mysetup,
    myinputs
)

new_vre = [0.]
new_thermal = [0.]
new_vre_cap = []
new_thermal_cap = []
for i in z_inputs["NEW_CAP"]
    resource = z_inputs["RESOURCES"][i]
    # if isa(resource, GenX.Vre)
    #     println(i)
    # end
    val = value(mz[:vCAP][i])
    if isa(resource, GenX.Thermal)
        new_thermal[1] += val
        push!(new_thermal_cap, i)
    elseif isa(resource, GenX.Vre)
        new_vre[1] += val
        push!(new_vre_cap, i)
    else
        println("RESOURCES IS OF TYPE $(typeof(resource))")
    end
end

#@constraint(mz, sum(mz[:vCAP][i] for i in new_vre_cap) >= sum(mz[:vCAP][i] for i in new_thermal_cap))

println("TOTAL NEW THERMAL = ", new_thermal[1])
println("TOTAL NEW VRE = ", new_vre[1])

optimize!(mz)

outputs_path = GenX.get_default_output_folder(case)
elapsed_time = @elapsed outputs_path = GenX.write_outputs(mz,
    outputs_path,
    mysetup,
    myinputs
)
println("outputs took $elapsed_time s to write")