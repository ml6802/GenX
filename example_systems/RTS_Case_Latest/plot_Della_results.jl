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

optimizer = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 7200, "MIPGap" => 1e-3)

# Add expected candidate line data
# also scales demands up by 4x
load_candidates_base(myinputs, 8784)

GenX.expand_new_cap_resources_to_nodal!(myinputs, mysetup, p, "")
GenX.load_generators_variability!(mysetup, p, myinputs)

# Set additional inputs so it only solves for one week
myinputs["hours_per_subperiod"] = 672
myinputs["INTERIOR_SUBPERIODS"] = [i for i in 2:myinputs["hours_per_subperiod"]]
myinputs["T"] = 672


# myinputs["pD"] = myinputs["pD"][2000:end, :]
# myinputs["pP_Max"] = myinputs["pP_Max"][:, 2000:end]
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

df_lines = CSV.read((@__DIR__)*"/transmission_downscaling_results.csv", DataFrame)
df_gens = CSV.read((@__DIR__)*"/new_cap_downscaling_resultsb.csv", DataFrame)


# plot results
using PlasmoData, PlasmoDataPlots
fadjlist = build_network_adjacency_list(myinputs["pNet_Map"])

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
    add_node_data!(dg, i, "grey", "nodecolor")
    add_node_data!(dg, i, "grey", "nodecolor_type")
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



for k in 1:size(df_lines, 1)
    if df_lines[k, "NEW_LINES"] == 1
        add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "red", "new_build")
        add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], 5, "linewidth")
        add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "red", "status")
        add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], 5, "linewidth_status")
    elseif df_lines[k, "RECONDUCTOR_LOW"] > 0.1
        add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "teal", "status")
        add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], 5, "linewidth_status")
    end
end


max_cap = maximum(df_gens[!, "NEW_CAP"])

pv_names = ["CSP", "PV", "WIND"]
for i in 1:size(df_gens, 1)
    val = df_gens[i, "NEW_CAP"]
    if val >=1
        node = df_gens[i, "NODE_NUMBER"]
        name = df_gens[i, "NAME"]
        add_node_data!(dg, node, "black", "color")
        add_node_data!(dg, node, "black", "nodecolor")
        add_node_data!(dg, node, 5 + 7 * (val / max_cap), "nodesize")
        if any(i -> occursin(i, name), pv_names)
            add_node_data!(dg, node, "blue", "nodecolor_type")
        elseif get_node_data(dg, node, "nodecolor_type") == "blue"
            println("UHOH")
        else
            add_node_data!(dg, node, "red", "nodecolor_type")
        end
    end
end

# pd_vals = sum(myinputs["pD"][1:672, :], dims = 1)[:]
# for i in 1:73
#     if pd_vals[i] > 100000 && get_node_data(dg, i, "nodecolor") != "black"
#         add_node_data!(dg, i, "orange", "nodecolor")
#     end
# end




plot_graph(dg, nodecolor = get_node_data(dg, "nodecolor"), nodesize = get_node_data(dg, "nodesize"), xdim = 500, ydim = 500, linewidth = get_edge_data(dg, "linewidth_status"), linecolor = get_edge_data(dg, "status"), save_fig = false, fig_name = (@__DIR__)*"/zonal_nodal_builds_RTS_repweek_benders.png")

plot_graph(dg, nodecolor = get_node_data(dg, "nodecolor"), nodesize = 6, xdim = 500, ydim = 500, linewidth = get_edge_data(dg, "linewidth_status"), linecolor = get_edge_data(dg, "status"), save_fig = false, fig_name = (@__DIR__)*"/zonal_nodal_builds_RTS_repweek_benders.png")
