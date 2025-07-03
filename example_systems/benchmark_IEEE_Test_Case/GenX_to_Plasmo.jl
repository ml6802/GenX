# convert model to plasmo optigraph

using Plasmo, JuMP

function get_unique_variable_names(vars::Vector{VariableRef})
    # Extract variable names and parse out the part before '['
    raw_names = name.(vars)
    base_names = [split(n, "[", limit=2)[1] for n in raw_names]
    return unique(base_names)
end

function parse_variable_name(var::JuMP.VariableRef)
    varname = name(var)
    if occursin('[', varname)
        base, idx_str = split(varname, '['; limit=2)
        # Remove the trailing ']'
        idx_str = chop(idx_str; head=0, tail=1)
        # Parse the indices as a tuple of integers (or other values)
        idx = Tuple(eval(Meta.parse("($idx_str)")))
        return base, idx
    else
        return varname, ()
    end
end


function copy_var_attributes(JuMP_var, var)
    if is_binary(JuMP_var)
        set_binary(var)
    elseif is_integer(JuMP_var)
        set_integer(var)
    end

    if has_lower_bound(JuMP_var)
        set_lower_bound(var, lower_bound(JuMP_var))
    end
    if has_upper_bound(JuMP_var)
        set_upper_bound(var, upper_bound(JuMP_var))
    end

    if has_start_value(JuMP_var)
        set_start_value(var, start_value(JuMP_var))
    end

    if is_fixed(JuMP_var)
        fix(var, fix_value(JuMP_var); force = true)
    end
end

function add_new_var!(node, JuMP_var, var_to_var, node_to_var)
    new_var = @variable(node)
    var_to_var[JuMP_var] = new_var
    push!(node_to_var[node], new_var)

    copy_var_attributes(JuMP_var, new_var)
end

function get_expr(con_obj, var_to_var, node_to_var)
    vars = con_obj.func.terms.keys

    if all(x -> x in keys(var_to_var), vars)
        node_set = unique([JuMP.owner_model(var_to_var[var]) for var in vars if (var in keys(var_to_var))])
        owning_node = node_set[1]

        if length(node_set) > 1
            link = true
        elseif length(node_set) == 1
            link = false
        else
            error("variables don't have a node!")
        end

        new_expr = sum(var_to_var[var] * con_obj.func.terms[var] for var in vars)
    elseif any(x -> x in keys(var_to_var), vars)
        new_vars = [i for i in vars if !(i in keys(var_to_var))]
        node_set = unique([JuMP.owner_model(var_to_var[var]) for var in vars if (var in keys(var_to_var))])
        owning_node = node_set[1]

        if length(node_set) > 1
            link = true
        elseif length(node_set) == 1
            link = false
        else
            error("variables don't have a node!")
        end

        for new_var in new_vars
            add_new_var!(owning_node, new_var, var_to_var, node_to_var)
        end

        new_expr = sum(var_to_var[var] * con_obj.func.terms[var] for var in vars)
    else
        error("Constraint $con_obj has no node :(")
    end

    return new_expr, link, owning_node
end

function build_graph_from_model(model, horizon)

    avs = all_variables(model)
    parsed_vars = parse_variable_name.(avs)
    var_to_parse_map = Dict(avs[i] => parsed_vars[i] for i in 1:length(avs))

    var_names = String.([:vZERO, :vZ_BUILD, :vP, :vNSE, :vFuel, :vStartFuel, :vFLOW, :vCANDFLOW, :p_bus, :p_virtual])
    idx_map = Dict(
        "vP" => 2,
        "vNSE" => 2,
        "vFuel" => 2,
        "vStartFuel" => 2,
        "vFLOW" => 2,
        "vCANDFLOW" => 2,
        "p_bus" => 2,
        "p_virtual" => 3,
        "vANGLE" => 2,
        "vPROX_ANGLE" => 2
    )
    master_names = String.([:vZERO, :vZ_BUILD, :vNEW_TRANS_CAP_DECISION_INT, :vRETCAP])#, :vFuel])


    # vZero - var
    # vZ_BUILD - sparse array
    # vP - matrix
    # vNSE - array
    # vFuel - dense array
    # vStartFuel - dense
    # vFLOW - matrix
    # vCANDFLOW - matrix
    # p_bus - matrix
    # p_virtual - sparse

    # time point idx to node
    # get time point from var name
    # map var_name to idx of time point
    # add variables to all applicable nodes
    # map variables to variables
    # loop through constraints 
        # add constraints to same problem if applicable

    graph = OptiGraph()
    @optinode(graph, master)
    @optinode(graph, n[1:horizon])

    time_to_node = Dict()
    var_to_var = Dict()
    name_to_node = Dict()
    node_to_var = Dict()
    node_to_var[master] = Any[]
    for node in n
        node_to_var[node] = Any[]
    end

    acs = all_constraints(model, include_variable_in_set_constraints = false)

    # for i in 1:length(bus_names)
    #     for j in 1:horizon
    #         optinode = graph[:bus][bus_names[i], j]
    #         node_to_var[optinode] = Any[]
    #     end
    # end
    # for i in 1:length(arc_names)
    #     for j in 1:horizon
    #         optinode = graph[:arc][arc_names[i], j]
    #         node_to_var[optinode] = Any[]
    #     end
    # end

    # function match_data_to_node(data, axis1, axis2, node_to_var = node_to_var)
    #     if eltype(axis1) == String
    #         for (i, name) in enumerate(axis1)
    #             for (j, time) in enumerate(axis2)
    #                 var = data[i, j]
    #                 push!(node_to_var[name_to_node[name][j]], var)
    #             end
    #         end
    #         # Test if it is in the lines, tts, or gens
    #     elseif eltype(axis1) == Int64
    #         for (i, num) in enumerate(axis1)
    #             for (j, time) in enumerate(axis2)
    #                 var = data[i, j]
    #                 push!(node_to_var[bus_to_node[bus_number_to_name[num]][j]], var)
    #             end
    #         end
    #     else
    #         error("Type is incorrect")
    #     end
    # end

    # for (i, set) in enumerate(var_sets)
    #     var_set = variables[var_sets[i]]
    #     if typeof(var_set) <: JuMP.Containers.DenseAxisArray
    #         if length(var_set.axes) == 2
    #             axis1 = var_set.axes[1]
    #             axis2 = var_set.axes[2]
    #             data = var_set.data
    #             match_data_to_node(data, axis1, axis2)
    #         elseif length(var_set.axes) == 1
    #             continue
    #         else
    #             error("variable set is the wrong length")
    #         end
    #         #println(i, "  DENSE")
    #     elseif typeof(var_set) <: JuMP.Containers.SparseAxisArray
    #         #println(i, "    SPARSE")
    #         data = var_set.data
    #         for key in keys(data)
    #             name = key[1]
    #             time = key[3]
    #             var = data[key]

    #             push!(node_to_var[name_to_node[name][time]], var)
    #         end
    #     else
    #         println(i, " did not enter")
    #         println(typeof(var_set))
    #     end
    # end

    for var in avs
        parsed_info = var_to_parse_map[var]
        var_name = parsed_info[1]
        if var_name in master_names
            node = master
        else
            node_idx = parsed_info[2][idx_map[var_name]]
            node = n[node_idx]
        end
        _v_copy = @variable(node)

        var_to_var[var] = _v_copy
        copy_var_attributes(var, _v_copy)
        push!(node_to_var[node], var)
    end

    con_to_con = Dict()
    graph_con_to_con = Dict()

    for (i, con) in enumerate(acs)
        con_obj = constraint_object(con)
        if typeof(con_obj.set) == MOI.EqualTo{Float64}
            new_expr, link, owning_node = get_expr(con_obj, var_to_var, node_to_var)
            if link
                graph_con = @linkconstraint(graph, new_expr == con_obj.set.value)
            else
                graph_con = @constraint(owning_node, new_expr == con_obj.set.value)
            end
        elseif typeof(con_obj.set) == MOI.LessThan{Float64}
            new_expr, link, owning_node = get_expr(con_obj, var_to_var, node_to_var)
            if link
                graph_con = @linkconstraint(graph, new_expr <= con_obj.set.upper)
            else
                graph_con = @constraint(owning_node, new_expr <= con_obj.set.upper)
            end
        elseif typeof(con_obj.set) == MOI.GreaterThan{Float64}
            new_expr, link, owning_node = get_expr(con_obj, var_to_var, node_to_var)
            if link
                graph_con = @linkconstraint(graph, new_expr >= con_obj.set.lower)
            else
                graph_con = @constraint(owning_node, new_expr >= con_obj.set.lower)
            end
        elseif typeof(con_obj.set) == MOI.Interval{Float64}
            new_expr, link, owning_node = get_expr(con_obj, var_to_var, node_to_var)
            if link
                graph_con = @linkconstraint(graph, con_obj.set.lower <= new_expr <= con_obj.set.upper)
            else
                graph_con = @constraint(owning_node, con_obj.set.lower <= new_expr <= con_obj.set.upper)
            end

        else
            println(con_obj.set)
            error("constraint object does not match types")
        end
        con_to_con[con] = graph_con
        graph_con_to_con[graph_con] = con
    end

    jm_obj_func = objective_function(model)

    for (i, node) in enumerate(keys(node_to_var))
        node_vars = intersect(node_to_var[node], jm_obj_func.terms.keys)
        if length(node_vars) > 0
            new_obj_expr = sum(var_to_var[var] * jm_obj_func.terms[var] for var in node_vars)
            @objective(node, Min, new_obj_expr)
        end
    end

    master_obj = objective_function(master)
    add_to_expression!(master_obj, jm_obj_func.constant)
    set_objective_function(master, master_obj)
    # add constant to master

    return graph, var_to_var, con_to_con, graph_con_to_con
end

g, v_to_v, ctc, gctc = build_graph_from_model(m, 24)

node_membership_vector = [1,2,2,2,2,2,2,2,2,1,3,3,3,3,3,3,3,3,3,3,3,3,3,3,1]
#node_membership_vector = [1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2]
#node_membership_vector = Int.(zeros(70 + 1))
#node_membership_vector[1] = 1
#node_membership_vector[2:end] .= 2
#

node_partition = Partition(g, node_membership_vector)
apply_partition!(g, node_partition)

solver = optimizer_with_attributes(Gurobi.Optimizer, "MIPGap" => 1e-3, "OutputFlag" => 0, "TimeLimit" => 200, "InfUnbdInfo" => true, "BarHomogeneous" => 1, "Method" => 2, "Crossover" => 0)

using PlasmoBenders

# root_graph = getsubgraphs(g)[1]

# root_avs = all_variables(root_graph)
# root_bin_vars = root_avs[JuMP.is_binary.(root_avs)]

# unset_binary.(root_bin_vars)
# set_upper_bound.(root_bin_vars, 1)
# set_lower_bound.(root_bin_vars, 0)
ba = BendersAlgorithm(
    g, 
    getsubgraphs(g)[1],
    solver = solver,
    max_iters = 50, 
    regularize=false,
    #feasibility_cuts = true,
    tol = 1e-3
);

run_algorithm!(ba)

# ba.best_upper_bound = Inf
# ba.max_iters = 300
# set_binary.(root_bin_vars)
# run_algorithm!(ba)
a=1

#=
run_algorithm!(ba)

sub = getsubgraphs(g)[2]
acs = all_constraints(sub, include_variable_in_set_constraints = false)

con_objs = constraint_object.(acs)
typeof.(con_objs)

lt_con_idx = [con_objs[i] isa ScalarConstraint{GenericAffExpr{Float64, NodeVariableRef}, MOI.LessThan{Float64}} for i in 1:length(con_objs)]
gt_con_idx = [con_objs[i] isa ScalarConstraint{GenericAffExpr{Float64, NodeVariableRef}, MOI.GreaterThan{Float64}} for i in 1:length(con_objs)]


active_sets = ba.ext["active_sets"]

lt_active_sets = active_sets[lt_con_idx, :]
gt_active_sets = active_sets[gt_con_idx, :]

sum_lt_active_sets = sum(lt_active_sets, dims = 2)[:]
sum_gt_active_sets = sum(gt_active_sets, dims = 2)[:]

lt_active_sets_big_idx = [sum_lt_active_sets[i] < -1 for i in 1:length(sum_lt_active_sets)]
gt_active_sets_big_idx = [sum_gt_active_sets[i] > 1 for i in 1:length(sum_gt_active_sets)]

gt_duals = gt_active_sets[gt_active_sets_big_idx, :]
gt_duals_bin = gt_duals .> 1e-7
lt_duals = lt_active_sets[lt_active_sets_big_idx, :]
lt_duals_bin = lt_duals .< -1e-7


gt_duals_change = zeros(size(gt_duals))
lt_duals_change = zeros(size(lt_duals))

for j in 1:(size(gt_duals_change)[2]-1)
    for i in 1:size(gt_duals_change)[1]
        gt_duals_change[i, j] = (abs(gt_duals[i,j]) <= 1e-7 || abs(gt_duals[i, j+1] <= 1e-7)) && (abs(gt_duals[i, j]) > 1e-7 || abs(gt_duals[i, j+1] > 1e-7))
    end
end
=#
# ba.max_iters = ba.current_iter + 1

# for i in 1:length(root_bin_vars)
#     ba.best_upper_bound = Inf
#     ba.max_iters += 5
#     set_binary(root_bin_vars[i])
#     run_algorithm!(ba)
# end


# ba.best_upper_bound = Inf
# ba.max_iters = 100

# set_binary.(root_bin_vars[1:10])
# run_algorithm!(ba)

# ba.best_upper_bound = Inf
# ba.max_iters = 200

# set_binary.(root_bin_vars[11:20])
# run_algorithm!(ba)

# ba.best_upper_bound = Inf
# ba.max_iters = 300

# set_binary.(root_bin_vars[21:30])
# run_algorithm!(ba)

# ba.best_upper_bound = Inf
# ba.max_iters = 400

# set_binary.(root_bin_vars[31:40])
# run_algorithm!(ba)

# ba.best_upper_bound = Inf
# ba.max_iters = 500

# set_binary.(root_bin_vars[41:50])
# run_algorithm!(ba)


# ba.best_upper_bound = Inf
# ba.max_iters = 550

# set_binary.(root_bin_vars[51:60])
# run_algorithm!(ba)

# ba.best_upper_bound = Inf
# ba.max_iters = 600

# set_binary.(root_bin_vars[61:end])
# run_algorithm!(ba)



# ba.best_upper_bound = Inf
# ba.max_iters = 650

# run_algorithm!(ba)



