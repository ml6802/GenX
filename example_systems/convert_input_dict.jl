function map_generator_to_node(inputs::Dict, node_to_zone_map::Dict, num_zones::Int)
    # node_to_zone_map is a node index to zone index
    resources = inputs["RESOURCES"]
    zone_to_generator_map = Dict{Int, Vector{Int}}()
    generator_to_zone_map = Dict{Int, Int}()
    generator_to_node_map = Dict{Int, Int}()
    for i in 1:num_zones
        zone_to_generator_map[i] = Int[]
    end
    for r in resources
        r_dict = parent(r)
        zone = node_to_zone_map[r_dict[:zone]]
        push!(zone_to_generator_map[zone], r_dict[:id])
        generator_to_zone_map[r_dict[:id]] = zone
        generator_to_node_map[r_dict[:id]] = r_dict[:zone]
    end

    return generator_to_zone_map, zone_to_generator_map, generator_to_node_map
end

function build_network_adjacency_list(adj_mat::Matrix)
    adj_list = Vector{Vector{Int}}()
    num_lines = size(adj_mat, 1)

    for i in 1:num_lines
        src = findfirst(x -> x == -1, adj_mat[i, :])
        dst = findfirst(x -> x == 1, adj_mat[i, :])
        push!(adj_list, [src, dst])
    end

    return adj_list
end

function build_zonal_adjacency_matrix(adj_mat::Matrix, node_to_zone_map::Dict, num_zones::Int) #TODO: map internal lines to zones
    adj_list = build_network_adjacency_list(adj_mat)

    new_adj_list = Vector{Vector{Int}}()
    line_to_zone_map = Dict{Int, Int}()
    zone_to_line_map = Dict{Int, Int}()
    internal_zone_map = Dict{Int, Vector{Int}}()
    for i in 1:num_zones
        internal_zone_map[i] = Int[]
    end

    for (i, edge) in enumerate(adj_list)
        src, dst = edge
        src_zone = node_to_zone_map[src]
        dst_zone = node_to_zone_map[dst]

        if src_zone != dst_zone
            new_edge = [src_zone, dst_zone]
            push!(new_adj_list, new_edge)
            line_to_zone_map[i] = length(new_adj_list)
            zone_to_line_map[length(new_adj_list)] = i
        else
            push!(internal_zone_map[src_zone], i)
        end
    end

    new_adj_mat = zeros(Int, length(new_adj_list), num_zones)
    for (i, edge) in enumerate(new_adj_list)
        new_adj_mat[i, edge[1]] = -1
        new_adj_mat[i, edge[2]] = 1
    end

    return adj_list, new_adj_mat, new_adj_list, line_to_zone_map, zone_to_line_map, internal_zone_map
end

function build_zonal_inputs(inputs::Dict, node_to_zone_map::Dict, num_zones::Int)
    @assert maximum(collect(values(node_to_zone_map))) == num_zones

    g2z_map, z2g_map, g2n_map = map_generator_to_node(inputs, node_to_zone_map, num_zones)

    zonal_inputs = deepcopy(inputs)
    zonal_inputs["Z"] = num_zones
    zonal_inputs["g2z_map"] = g2z_map
    zonal_inputs["z2g_map"] = z2g_map
    zonal_inputs["g2n_map"] = g2n_map
    G = inputs["G"]
    zonal_inputs["RESOURCE_NAMES"] = Vector{String}()
    for (i, r) in enumerate(zonal_inputs["RESOURCES"])
        r_dict = parent(r)
        r_dict[:zone] = node_to_zone_map[r_dict[:zone]]
        push!(zonal_inputs["RESOURCE_NAMES"], inputs["RESOURCE_NAMES"][i])
    end

    adj_mat = inputs["pNet_Map"]
    adj_list, new_adj_mat, new_adj_list, l2z_map, z2l_map, internal_zone_map = build_zonal_adjacency_matrix(adj_mat, node_to_zone_map, num_zones)

    zonal_inputs["pNet_Map"] = new_adj_mat
    zonal_inputs["new_adj_list"] = new_adj_list
    zonal_inputs["l2z_map"] = l2z_map
    zonal_inputs["z2l_map"] = z2l_map
    zonal_inputs["adj_list"] = adj_list
    zonal_inputs["internal_zone_map"] = internal_zone_map
    
    line_keys = [ "pPercent_Loss", "pTrans_Loss_Coeff", "pTrans_Max_Possible", "pTrans_Max", "pTrans_Max_Possible", "pDC_OPF_coeff", "Line_Angle_Limit"]

    for key in line_keys
        if haskey(inputs, key)
            new_data = Float64[]
            for i in 1:length(new_adj_list)
                original_line_idx = z2l_map[i]
                push!(new_data, inputs[key][original_line_idx])
            end
            zonal_inputs[key] = new_data
        end
    end
    zonal_inputs["L"] = length(new_adj_list)

    if haskey(zonal_inputs, "pNet_Map_cand")
        adj_mat_cand = zonal_inputs["pNet_Map_cand"]
        adj_list_cand, new_adj_mat_cand, new_adj_list_cand, l2z_map_cand, z2l_map_cand, internal_zone_map_cand = build_zonal_adjacency_matrix(adj_mat_cand, node_to_zone_map, num_zones)

        zonal_inputs["pNet_Map_cand"] = new_adj_mat_cand
        zonal_inputs["new_adj_list_cand"] = new_adj_list_cand
        zonal_inputs["l2z_map_cand"] = l2z_map_cand
        zonal_inputs["z2l_map_cand"] = z2l_map_cand
        zonal_inputs["adj_list_cand"] = adj_list_cand
        zonal_inputs["internal_zone_map_cand"] = internal_zone_map_cand

        zonal_inputs["L_cand"] = length(new_adj_list_cand)
        zonal_inputs["Z_cand"] = num_zones

        line_keys = ["pDC_OPF_coeff_cand", "Line_Angle_Limit_cand", "pMax_Line_Reinforcement", "Line_Reinforcement_Cap_Size", "pC_Line_Reinforcement"]

        for key in line_keys
            if haskey(inputs, key)
                new_data = Float64[]
                for i in 1:length(new_adj_list)
                    original_line_idx = z2l_map[i]
                    push!(new_data, inputs[key][original_line_idx])
                end
                zonal_inputs[key] = new_data
            end
        end

        if haskey(inputs, "EXPANSION_LINES")
            zonal_inputs["EXPANSION_LINES"] = [i for i in 1:length(new_adj_list_cand)]
        end
        if haskey(inputs, "EXPANSION_LEVELS")
            zonal_inputs["EXPANSION_LEVELS"] = Dict{Int, Vector{Float64}}()
            for key in keys(inputs["EXPANSION_LEVELS"])
                line_idx = key
                if haskey(l2z_map_cand, line_idx)
                    zonal_inputs["EXPANSION_LEVELS"][l2z_map_cand[line_idx]] = inputs["EXPANSION_LEVELS"][line_idx]
                end
            end
        end
    end

    pD = inputs["pD"]
    load_len = size(pD, 1)
    zonal_inputs["pD"] = zeros(Float64, load_len, num_zones)
    for i in 1:size(pD, 2)
        zone_idx = node_to_zone_map[i]
        zonal_inputs["pD"][:, zone_idx] .+= pD[:, i]
    end

    return zonal_inputs
end

function build_nodal_adjacency_matrix(adj_mat::Matrix, node_to_zone_map::Dict, node_to_node_map::Dict, zone::Int)
    adj_list = build_network_adjacency_list(adj_mat)

    #shortened_adj_list = Vector{Vector{Int}}()
    new_adj_list = Vector{Vector{Int}}()
    line_to_line_map = Dict{Int, Int}()
    line_list = Vector{Int}()

    for (i, edge) in enumerate(adj_list)
        src, dst = edge
        src_zone = node_to_zone_map[src]
        dst_zone = node_to_zone_map[dst]

        if src_zone == zone && dst_zone == zone
            #push!(shortened_adj_list, edge)
            new_edge = [node_to_node_map[src], node_to_node_map[dst]]
            push!(new_adj_list, new_edge)
            push!(line_list, i)
            line_to_line_map[i] = length(new_adj_list)
        end
    end

    new_adj_mat = zeros(Int, length(new_adj_list), length(node_to_node_map))
    for (i, edge) in enumerate(new_adj_list)
        new_adj_mat[i, edge[1]] = -1
        new_adj_mat[i, edge[2]] = 1
    end

    return new_adj_mat, new_adj_list, line_list, line_to_line_map
end

function build_single_nodal_input(inputs::Dict, node_to_zone_map::Dict, zone::Int, zone_to_generator_map::Dict, node_to_node_map::Dict)
    nodal_inputs = deepcopy(inputs)
    nodes_in_zone = sort(collect(keys(node_to_node_map))) #index of original node numbers
    num_nodes = length(node_to_node_map)
    nodal_inputs["N"] = num_nodes
    nodal_inputs["nodes_in_zone"] = nodes_in_zone
    nodal_inputs["n2n_map"] = node_to_node_map

    resources = nodal_inputs["RESOURCES"]
    resource_names = nodal_inputs["RESOURCE_NAMES"]
    nodal_resources = Vector{GenX.AbstractResource}()
    gen_to_gen_map = Dict{Int, Int}() # maps original generator id to new generator id

    nodal_resource_names = Vector{String}()
    generator_list = zone_to_generator_map[zone]
    nodal_inputs["G"] = length(generator_list)
    pP_Max = inputs["pP_Max"]
    new_pP_Max_data = zeros(nodal_inputs["G"], size(pP_Max, 2))
    for (i, g_idx) in enumerate(generator_list)
        next_resource = resources[g_idx]
        resource_name = resource_names[g_idx]
        g_dict = parent(next_resource)
        original_node = g_dict[:zone]
        original_id = g_dict[:id]
        gen_to_gen_map[original_id] = i
        g_dict[:zone] = node_to_node_map[original_node]
        g_dict[:id] = i

        new_pP_Max_data[i, :] .= pP_Max[original_id, :]
 
        push!(nodal_resources, next_resource)
        push!(nodal_resource_names, resource_name)
    end

    nodal_inputs["RESOURCES"] = nodal_resources
    nodal_inputs["RESOURCE_NAMES"] = nodal_resource_names
    nodal_inputs["Z"] = num_nodes
    nodal_inputs["pP_Max"] = new_pP_Max_data
    old_generator_indices = sort(collect(keys(gen_to_gen_map)))

    # these keys are all vectors of generator indices
    generator_data_keys = [
        "THERM_NO_COMMIT",
        "COMMIT",
        "THERM_ALL",
        "THERM_COMMIT",
        "THERM_COMMIT_PWFU",
        "MUST_RUN",
        "HAS_FUEL",
        "MULTI_FUELS",
        "SINGLE_FUEL",
        "FLEX",
        "CCS",
        "STOR_ALL",
        "STOR_SHORT_DURATION",
        "STOR_LONG_DURATION",
        "STOR_SYMMETRIC",
        "STOR_ASYMMETRIC",
        "STOR_HYDRO_SHORT_DURATION",
        "STOR_HYDRO_LONG_DURATION",
        "HYDRO_RES",
        "VRE_STOR",
        "VRE",
        "ELECTROLYZER",
        "HYDRO_RES_KNOWN_CAP",
        "RETROFIT_CAP",
        "RET_CAP",
        "NEW_CAP",
        "NEW_CAP_ENERGY",
        "RET_CAP_ENERGY",
        "RET_CAP_CHARGE",
        "NEW_CAP_CHARGE"
    ]

    for key in generator_data_keys
        if haskey(inputs, key)
            generator_data = inputs[key]
            new_generator_data = Vector{Int}()
            for g in generator_data
                if g in keys(gen_to_gen_map)
                    push!(new_generator_data, gen_to_gen_map[g])
                end
            end
            nodal_inputs[key] = new_generator_data
        end
    end

    # these keys are matrices
    generator_matrix_keys = [
        "C_Start"
    ]

    for key in generator_matrix_keys
        if haskey(inputs, key)
            generator_matrix = inputs[key]

            new_generator_matrix = generator_matrix[old_generator_indices, :]
            nodal_inputs[key] = new_generator_matrix
        end
    end

    new_adj_mat, new_adj_list, line_list, l2l_map = build_nodal_adjacency_matrix(inputs["pNet_Map"], node_to_zone_map, node_to_node_map, zone)

    nodal_inputs["pNet_Map"] = new_adj_mat
    nodal_inputs["pNet_Adj_List"] = new_adj_list
    nodal_inputs["line_list"] = line_list
    nodal_inputs["l2l_map"] = l2l_map
    nodal_inputs["L"] = length(new_adj_list)
    
    line_keys = [ "pPercent_Loss", "pTrans_Loss_Coeff", "pTrans_Max_Possible", "pTrans_Max", "pTrans_Max_Possible", "pDC_OPF_coeff", "Line_Angle_Limit"]

    for key in line_keys
        if haskey(inputs, key)
            new_data = Float64[]
            for i in line_list
                push!(new_data, inputs[key][i])
            end
            nodal_inputs[key] = new_data
        end
    end

    if haskey(nodal_inputs, "pNet_Map_cand")
        new_adj_mat_cand, new_adj_list_cand, line_list_cand, l2l_map_cand = build_nodal_adjacency_matrix(inputs["pNet_Map_cand"], node_to_zone_map, node_to_node_map, zone)

        nodal_inputs["pNet_Map_cand"] = new_adj_mat_cand
        nodal_inputs["pNet_Adj_List_cand"] = new_adj_list_cand
        nodal_inputs["line_list_cand"] = line_list_cand
        nodal_inputs["l2l_map_cand"] = l2l_map_cand
        nodal_inputs["L_cand"] = length(new_adj_list_cand)
        nodal_inputs["Z_cand"] = num_nodes

        line_keys = ["pDC_OPF_coeff_cand", "Line_Angle_Limit_cand", "pMax_Line_Reinforcement", "Line_Reinforcement_Cap_Size", "pC_Line_Reinforcement"]

        for key in line_keys
            if haskey(inputs, key)
                new_data = Float64[]
                for i in line_list_cand
                    push!(new_data, inputs[key][i])
                end
                 nodal_inputs[key] = new_data
            end
        end

        if haskey(inputs, "EXPANSION_LINES")
            nodal_inputs["EXPANSION_LINES"] = [i for i in 1:length(new_adj_list_cand)]
        end
        if haskey(inputs, "EXPANSION_LEVELS")
            nodal_inputs["EXPANSION_LEVELS"] = Dict{Int, Vector{Float64}}()
            for key in keys(inputs["EXPANSION_LEVELS"])
                line_idx = key
                if line_idx in line_list_cand
                    nodal_inputs["EXPANSION_LEVELS"][l2l_map_cand[line_idx]] = inputs["EXPANSION_LEVELS"][line_idx]
                end
            end
        end
    end

    nodal_inputs["pD"] = inputs["pD"][:, nodes_in_zone]

    return nodal_inputs
end

function build_nodal_inputs(inputs::Dict, node_to_zone_map::Dict, num_zones::Int)
    g2z_map, z2g_map, g2n_map = map_generator_to_node(inputs, node_to_zone_map, num_zones)

    zone_to_node_map = Dict{Int, Vector{Int}}() # map each zone to the vector of its nodes
    node_to_node_map_by_zone = Dict{Int, Dict{Int, Int}}()
    for i in 1:num_zones
        zone_to_node_map[i] = Int[]
    end
    for (node, zone) in node_to_zone_map
        push!(zone_to_node_map[zone], node)
    end
    for zone in keys(zone_to_node_map)
        node_to_node_map = Dict{Int, Int}() # maps the original node index to the NEW node index
        z2n_vector = sort(zone_to_node_map[zone]) # sorted vector of nodes in the zone
        zone_to_node_map[zone] = z2n_vector # reset value to be sorted

        for (i, idx) in enumerate(z2n_vector)
            node_to_node_map[idx] = i
        end
        node_to_node_map_by_zone[zone] = node_to_node_map
    end
    nodal_inputs = Dict{Int, Dict}()

    for i in 1:num_zones
        nodal_inputs[i] = build_single_nodal_input(inputs, node_to_zone_map, i, z2g_map, node_to_node_map_by_zone[i])
    end

    return nodal_inputs
end

function get_interzonal_node_time_series(z_inputs::Dict, m::Model)
    z2l_map = z_inputs["z2l_map"]
    adj_list = z_inputs["adj_list"]
    interzonal_lines = sort(collect(keys(z2l_map)))
    nodal_time_series = Dict{Int, Vector{Float64}}()
    T = z_inputs["T"]
    for (i, line) in enumerate(interzonal_lines)
        original_line = z2l_map[line]
        edge = adj_list[original_line]
        src_node = edge[1]
        dst_node = edge[2]
        
        flow_solution = value.(m[:vFLOW][line, :])

        if haskey(nodal_time_series, src_node)
            nodal_time_series[src_node] .+= flow_solution[:]
        else
            nodal_time_series[src_node] = flow_solution[:]
        end
        if haskey(nodal_time_series, dst_node)
            nodal_time_series[dst_node] .-= flow_solution[:]
        else
            nodal_time_series[dst_node] = -1 .* flow_solution[:]
        end
    end

    if haskey(m, :vCANDFLOW)
        z2l_map_cand = z_inputs["z2l_map_cand"]
        adj_list_cand = z_inputs["adj_list_cand"]
        interzonal_lines_cand = sort(collect(keys(z2l_map_cand)))

        for (i, line) in enumerate(interzonal_lines_cand)
            original_line = z2l_map_cand[line]
            edge = adj_list_cand[original_line]
            src_node = edge[1]
            dst_node = edge[2]

            candflow_vars = m[:vCANDFLOW]
            if isa(candflow_vars, Array)
                flow_solution = [value(m[:vCANDFLOW][line, t]) for t in 1:T]
            else
                flow_solution = [sum(value.(m[:vCANDFLOW][line, t, :])) for t in 1:T]
            end

            if haskey(nodal_time_series, src_node)
                nodal_time_series[src_node] .+= flow_solution[:]
            else
                nodal_time_series[src_node] = flow_solution[:]
            end
            if haskey(nodal_time_series, dst_node)
                nodal_time_series[dst_node] .-= flow_solution[:]
            else
                nodal_time_series[dst_node] = -1 .* flow_solution[:]
            end
        end
    end
    return nodal_time_series
end

function run_zonal_model!(z_inputs::Dict, setup::Dict, optimizer)
    mz = GenX.generate_model(setup, z_inputs, optimizer)
    optimize!(mz)
    nts = get_interzonal_node_time_series(z_inputs, mz)
    z_inputs["interzonal_node_flows"] = nts
    return mz
end

function add_interzonal_data!(z_inputs::Dict, n_inputs::Dict)
    zone_list = sort(collect(keys(n_inputs)))
    interzonal_node_flows = z_inputs["interzonal_node_flows"]
    for i in zone_list
        n_input = n_inputs[i]
        node_to_timeseries = Dict{Int, Vector{Float64}}()
        n2n_map = n_input["n2n_map"] # maps old index to new index
        nodes_in_zone = n_input["nodes_in_zone"]
        println(nodes_in_zone)
        for (j, node) in enumerate(nodes_in_zone)
            if haskey(interzonal_node_flows, node)
                node_to_timeseries[n2n_map[node]] = interzonal_node_flows[node]
            end
        end
        @assert length(node_to_timeseries) > 0 "No interzonal flows found for zone $i"
        n_input["node_to_timeseries"] = node_to_timeseries
    end
    # loop through each set of nodes
    # define a new time node - > time series map
    # get the set of nodes that belong to a given nodal input; 
    # get the mapping of original nodes to this nodes new idxs
    # loop through the set of nodes
        # if a node is also a key to interzonal_node_flows
            # save the time series data to the n_inputs
            # add a new THERMAL resource object
    return nothing
end

# n2z_map = Dict(1 => 1, 2 => 1, 3 => 2, 4 => 2)

# num_zones = 2

# z_inputs = build_zonal_inputs(inputs, n2z_map, num_zones)

# n_inputs = build_nodal_inputs(inputs, n2z_map, num_zones)