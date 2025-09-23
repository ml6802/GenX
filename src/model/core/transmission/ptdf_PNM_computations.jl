function get_lines(matrix::Matrix)
    line_list = Vector{Tuple}()
    for i in 1:size(matrix)[1]
        from_bus = findfirst(x -> x == 1, matrix[i, :])
        to_bus = findfirst(x -> x == -1, matrix[i, :])
        push!(line_list, (from_bus, to_bus))
    end
    return line_list
end

function find_matching_index(a::Vector, b::Vector, x, y)
    for i in eachindex(a, b)
        if a[i] == x && b[i] == y
            return i
        end
    end
    return nothing 
end

function calculate_ptdf_matrices(inputs::Dict, slack_bus::Int=1; tol = eps())
    A_I = Int[]
    A_J = Int[]
    A_V = Int8[]

    BA_I = Int[]
    BA_J = Int[]
    BA_V = Float64[]

    net_map = inputs["pNet_Map"]
    net_map_cand = inputs["pNet_Map_cand"]
    net_line_list = get_lines(net_map)
    net_line_list_cand = get_lines(net_map_cand)

    B_net = inputs["pDC_OPF_coeff"]
    B_net_cand = inputs["pDC_OPF_coeff_cand"]
    B_num_lines = inputs["Max_Trans_Cap"]
    B_total = Dict() # total susceptance on a given corridor

    num_buses = size(net_map)[2]
    buses = 1:num_buses
    bus_map = Dict(i => i for i in buses)

    if length(unique(net_line_list)) != length(net_line_list)
        error("Duplicate lines exist in the existing network map")
    elseif length(unique(net_line_list_cand)) != length(net_line_list_cand)
        error("Duplicate lines exist in the candidate network map")
    end

    all_lines = union(net_line_list, net_line_list_cand)
    line_map = Dict(line => i for (i, line) in enumerate(all_lines))

    for (i, line) in enumerate(all_lines)
        from_bus, to_bus = line
        push!(A_I, line_map[line])
        push!(A_J, from_bus)
        push!(A_V, 1)

        push!(A_I, line_map[line])
        push!(A_J, to_bus)
        push!(A_V, -1)
    end

    for (i, line) in enumerate(net_line_list)
        from_bus, to_bus = line

        push!(BA_I, from_bus)
        push!(BA_J, line_map[line])
        push!(BA_V, B_net[i])

        push!(BA_I, to_bus)
        push!(BA_J, line_map[line])
        push!(BA_V, -B_net[i])
        if haskey(B_total, line)
            B_total[line] += B_net[i]
        else
            B_total[line] = B_net[i]
        end
    end

    for (i, line) in enumerate(net_line_list_cand)
        B_val = B_net_cand[i] * B_num_lines[i]
        from_bus, to_bus = line
        line_idx = line_map[line]
        if line in net_line_list
            idx1 = find_matching_index(BA_I, BA_J, from_bus, line_idx)
            idx2 = find_matching_index(BA_I, BA_J, to_bus, line_idx)
            if isnothing(idx1) || isnothing(idx2)
                error("Indices cannot be found in vectors")
            end
            BA_V[idx1] += B_val
            BA_V[idx2] -= B_val
        else
            push!(BA_I, from_bus)
            push!(BA_J, line_map[line])
            push!(BA_V, B_val)
            
            push!(BA_I, to_bus)
            push!(BA_J, line_map[line])
            push!(BA_V, -B_val)
        end
        if haskey(B_total, line)
            B_total[line] += B_val
        else
            B_total[line] = B_val
        end
    end

    A =  SparseArrays.sparse(A_I, A_J, A_V)
    BA = SparseArrays.sparse(BA_I, BA_J, BA_V)
    ref_bus_position = Set([slack_bus])
    subnetworks= Dict{Int, Set{Int}}(slack_bus => Set([i for i in buses]))

    ptdf_mat = PowerNetworkMatrices._calculate_PTDF_matrix_KLU(A, BA, Set([slack_bus]), Float64[])# [1.0 for i in 1:num_buses])

    ptdf_data = PTDF(PNM.sparsify(ptdf_mat, tol), (buses, all_lines), (bus_map, line_map), subnetworks, ref_bus_position, Base.RefValue(tol), RadialNetworkReduction())

    # need to build ptdf for each line; 
    # Need to build a 3 entry tuple I think with the third dim being cand line num
    # Existing lines can be indexed by 0 maybe? 
    # Need to compute the susceptance for this single line
    # Need to build a new PTDF matrix for lines

    total_lines = length(B_net) + sum(B_num_lines) # number of existing lines + total number of possible new lines

    ptdf_by_line = zeros(num_buses, total_lines)
    ind_line_map = Dict()
    all_ind_lines = Tuple[]

    for (i, line) in enumerate(net_line_list)
        B_total_val = B_total[line]
        new_line_name = (line[1], line[2], 0)
        ind_line_map[new_line_name] = i
        B_val = B_net[i]
        push!(all_ind_lines, new_line_name)
        ptdf_by_line[:, i] = ptdf_data.data[:, line_map[line]] * B_val / B_total_val
    end

    for (i, line) in enumerate(net_line_list_cand)
        B_total_val = B_total[line]
        num_lines = B_num_lines[i]
        B_val = B_net_cand[i]
        for j in 1:num_lines
            new_line_name = (line[1], line[2], j)
            push!(all_ind_lines, new_line_name)
            ind_line_map[new_line_name] = length(ind_line_map) + 1
            ptdf_by_line[:, length(ind_line_map)] = ptdf_data.data[:, line_map[line]] * B_val / B_total_val
        end
    end

    ptdf_data_by_line = PTDF(PNM.sparsify(ptdf_by_line, tol), (buses, all_ind_lines), (bus_map, ind_line_map), Dict{Int, Set{Int}}(), ref_bus_position, Base.RefValue(tol), RadialNetworkReduction())

    return ptdf_data, ptdf_data_by_line
end

function get_ptdf_vector(ptdf_mat, line_idx, cand_num, line_map)
    line_tuple = line_map[line_idx]
    line_key = (line_tuple[1], line_tuple[2], cand_num)
    line_lookup = ptdf_mat.lookup[2]
    return ptdf_mat.data[:, line_lookup[line_key]]
    # pass the matrix, line index, cand number; return vector for buses
end

function get_ptdf_line_diff(ptdf_mat, line_idx, cand_num, line_virtual_idx, line_map)
    line_tuple = line_map[line_idx]
    line_virtual_tuple = line_map[line_virtual_idx]
    line_key = (line_tuple[1], line_tuple[2], cand_num)
    line_lookup = ptdf_mat.lookup[2]
    bus_vector = ptdf_mat.data[:, line_lookup[line_key]]
    return bus_vector[line_virtual_tuple[1]] - bus_vector[line_virtual_tuple[2]]
end