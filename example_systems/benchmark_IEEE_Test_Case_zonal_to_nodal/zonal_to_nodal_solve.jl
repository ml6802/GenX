a = 1
using Revise

using GenX
using Gurobi, JuMP
include((@__DIR__)*"/../convert_input_dict.jl")
case = dirname(@__FILE__)

# if you want to run the monolithic problem, uncomment the following line:
m, inputs, setup = run_genx_case!(case, Gurobi.Optimizer, tight_bigM = true);
genx_settings = GenX.get_settings_path(case, "genx_settings.yml")
writeoutput_settings = GenX.get_settings_path(case, "output_settings.yml")
setup = configure_settings(genx_settings, writeoutput_settings)

# make sure all necessary keys are present in the setup dictionary
if !(haskey(setup, "ptdf"))
    setup["ptdf"] = 0
end
if !(haskey(setup, "disaggregate"))
    setup["disaggregate"] = 0
end
if !(haskey(setup, "bilinear"))
    setup["bilinear"] = 0
end
if !(haskey(setup, "SOS1"))
    setup["SOS1"] = 0
end
if !(haskey(setup, "unfix_slacks"))
    setup["unfix_slacks"] = 0
end

inputs = load_inputs(mysetup, case)

# define node to zone mapping
n2z_map = Dict{Int, Int}()
for i in 1:49
    if i <= 14
        n2z_map[i] = 1
    elseif i <= 44
        n2z_map[i] = 2
    else
        n2z_map[i] = 3
    end 
end

optimizer = optimizer_with_attributes(Gurobi.Optimizer, "OutputFlag" => 1)

# set unfix_slacks to one to run waterflow model; otherwise it runs DCOPF
setup["unfix_slacks"] = 0
zonal_setup = deepcopy(setup)
#zonal_setup["DC_OPF"] = 0
#zonal_setup["IntegerInvestments"] = 1
zonal_setup["unfix_slacks"] = 1

num_zones = 3
# get zonal inputs
z_inputs = build_zonal_inputs(inputs, n2z_map, num_zones)

# solve teh zonal model and update teh zonal_inputs dictionary
mz = run_zonal_model!(z_inputs, zonal_setup, optimizer)

# build the nodal inputs
n_inputs = build_nodal_inputs(inputs, n2z_map, num_zones)

# add to the nodal inputs the interzonal transmission time series
add_interzonal_data!(z_inputs, n_inputs)


# solve nodal models
m1 = GenX.generate_model(setup, n_inputs[1], optimizer)

optimize!(m1)

m2 = GenX.generate_model(setup, n_inputs[2], optimizer)

optimize!(m2)

m3 = GenX.generate_model(setup, n_inputs[3], optimizer)

optimize!(m3)


# plot results
using PlasmoData, PlasmoDataPlots
fadjlist = z_inputs["adj_list"]
dg = DataGraph{Int, Any, Any, Any, Matrix{Any}, Matrix{Any}}()
for i in 1:49
    add_node!(dg, i)
    if i <= 14
        add_node_data!(dg, i, 1, "partition")
        add_node_data!(dg, i, "red", "color")
    elseif i <= 44
        add_node_data!(dg, i, 2, "partition")
        add_node_data!(dg, i, "orange", "color")
    else
        add_node_data!(dg, i, 3, "partition")
        add_node_data!(dg, i, "blue", "color")
    end
end
for (src, dst) in fadjlist
    add_edge!(dg, src, dst)
    add_edge_data!(dg, src, dst, "black", "new_build")
    add_edge_data!(dg, src, dst, 2, "linewidth")
    add_edge_data!(dg, src, dst, "black", "new_build_monolithic")
    add_edge_data!(dg, src, dst, 2, "linewidth_monolithic")
    add_edge_data!(dg, src, dst, "black", "zonal_line")
end

plot_graph(dg, nodecolor = get_node_data(dg, "color"), nodesize = 6, xdim = 500, ydim = 500, save_fig = true, linewidth=2, linecolor = "black", fig_name = (@__DIR__)*"/zonal_system.png")

l2z_map = z_inputs["l2z_map_cand"]
for k in keys(l2z_map)
    new_line = l2z_map[k]
    add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "white", "zonal_line")
    if value(mz[:vNEW_TRANS_CAP_DECISION_INT][new_line, 1]) == 1
        add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "red", "new_build")
        add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], 5, "linewidth")
    end
end


plot_graph(dg, nodecolor = get_node_data(dg, "color"), nodesize = 6, xdim = 500, ydim = 500, linewidth = 2, linecolor = get_edge_data(dg, "zonal_line"), save_fig = false, fig_name = (@__DIR__)*"/interzonal_no_lines.png")


plot_graph(dg, nodecolor = get_node_data(dg, "color"), nodesize = 6, xdim = 500, ydim = 500, linewidth = get_edge_data(dg, "linewidth"), linecolor = get_edge_data(dg, "new_build"), save_fig = false, fig_name = (@__DIR__)*"/interzonal_builds_nodcopf.png")


for i in 1:76
    if value(m[:vNEW_TRANS_CAP_DECISION_INT][i, 1]) == 1
        add_edge_data!(dg, fadjlist[i][1], fadjlist[i][2], "red", "new_build_monolithic")
        add_edge_data!(dg, fadjlist[i][1], fadjlist[i][2], 5, "linewidth_monolithic")
    end
end

plot_graph(dg, nodecolor = get_node_data(dg, "color"), nodesize = 6, xdim = 500, ydim = 500, linewidth = get_edge_data(dg, "linewidth_monolithic"), linecolor = get_edge_data(dg, "new_build_monolithic"), save_fig = false, fig_name = (@__DIR__)*"/monolithic_builds.png")


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

plot_graph(dg, nodecolor = get_node_data(dg, "color"), nodesize = 6, xdim = 500, ydim = 500, linewidth = get_edge_data(dg, "linewidth"), linecolor = get_edge_data(dg, "new_build"), save_fig = false, fig_name = (@__DIR__)*"/zonal_nodal_builds_nodcopf.png")


vP_by_zone_monolithic = zeros(3)
vP_by_zone_zonal = zeros(3)
vP_by_zone_nodal = zeros(3)

g2z_map = z_inputs["g2z_map"]

for k in keys(g2z_map)
    vP_by_zone_monolithic[g2z_map[k]] += sum(value.(m[:vP][k, :]))
    vP_by_zone_zonal[g2z_map[k]] += sum(value.(mz[:vP][k, :]))
end

vP_by_zone_nodal[1] = sum(value.(m1[:vP]))
vP_by_zone_nodal[2] = sum(value.(m2[:vP]))
vP_by_zone_nodal[3] = sum(value.(m3[:vP]))

zonal_obj_portion = 0.
zonal_obj_function = objective_function(mz)
for i in mz[:vNEW_TRANS_CAP_DECISION_INT]
    if value(i) == 1
        zonal_obj_portion += zonal_obj_function.terms[i]
    end
end

length(findall(x -> x == "red", get_edge_data(dg, "new_build")))

zonal_nodal_obj_total = zonal_obj_portion + objective_value(m1) + objective_value(m2) + objective_value(m3)

zonal_obj_total = objective_value(mz)

monolithic_total = objective_value(m)

gap = (zonal_nodal_obj_total - zonal_obj_total) / zonal_nodal_obj_total

# get flows across each line:
z2l_map = z_inputs["z2l_map"]
adj_list = z_inputs["new_adj_list"]
lines = sort(collect(keys(z2l_map)))
flows = zeros(3, 24)

for l in lines
    edge = adj_list[l]
    flow_sols = value.(mz[:vFLOW][l, :])
    if haskey(mz, :vCANDFLOW)
        cand_flow_sols = [value(mz[:vCANDFLOW][l, t, 1]) for t in 1:24]
    else
        cand_flow_sols = zeros(24)
    end
    if edge == [1, 2]
        flows[1, :] .+= flow_sols .+ cand_flow_sols
    elseif edge == [2, 3]
        flows[2, :] .+= flow_sols .+ cand_flow_sols
    elseif edge == [1, 3]
        flows[3, :] .+= flow_sols .+ cand_flow_sols
    elseif edge == [2, 1]
        flows[1, :] .-= flow_sols .+ cand_flow_sols
    elseif edge == [3, 2]
        flows[2, :] .-= flow_sols .+ cand_flow_sols
    elseif edge == [3, 1]
        flows[3, :] .-= flow_sols .+ cand_flow_sols
    end
end

# figure out why the none DCOPF doesn't work
# run non-DCOPF on zonal for comparison
# write a test for these problems? what hsould it test? Run through resources and make sure IDs are reset? zones are reset? make sure number of generators are right? check #pD; check resource types? At least check "pD"
# put results in ATO channel? 
# push results to branch on Mike's
# load inputs directly