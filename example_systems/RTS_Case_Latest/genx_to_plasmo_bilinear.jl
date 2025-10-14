# convert model to plasmo optigraph

using Plasmo, JuMP, Ipopt

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
    if isa(con_obj.func, GenericAffExpr)
        return get_linear_expression(con_obj, var_to_var, node_to_var)
    elseif isa(con_obj.func, QuadExpr)
        return get_quadratic_expression(con_obj, var_to_var, node_to_var)
    end
end

function get_quadratic_expression(con_obj, var_to_var, node_to_var)
    affvars = con_obj.func.aff.terms.keys
    quadterms = collect(con_obj.func.terms.keys)
    quadtermsa = [term.a for term in quadterms]
    quadtermsb = [term.b for term in quadterms]
    quadconstants = [con_obj.func.terms[term] for term in quadterms]
    quadvars = unique(vcat(quadtermsa, quadtermsb))

    # Convert the affine portion of the constraint
    if all(x -> x in keys(var_to_var), affvars)
        node_set = unique([JuMP.owner_model(var_to_var[var]) for var in affvars if (var in keys(var_to_var))])
        owning_node = node_set[1]

        if length(node_set) > 1
            link = true
        elseif length(node_set) == 1
            link = false
        else
            error("variables don't have a node!")
        end

        new_expr = sum(var_to_var[var] * con_obj.func.aff.terms[var] for var in affvars)
    elseif any(x -> x in keys(var_to_var), affvars)
        new_vars = [i for i in affvars if !(i in keys(var_to_var))]
        node_set = unique([JuMP.owner_model(var_to_var[var]) for var in affvars if (var in keys(var_to_var))])
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

        new_expr = sum(var_to_var[var] * con_obj.func.aff.terms[var] for var in affvars)
    else
        error("Constraint $con_obj aff term has no node :(")
    end

    # Convert the quadratic portion of the constraint
    if all(x -> x in keys(var_to_var), quadvars)
        node_set = unique([JuMP.owner_model(var_to_var[var]) for var in quadvars if (var in keys(var_to_var))])
        owning_node = node_set[1]

        if length(node_set) > 1
            link = true
        elseif length(node_set) == 1
            link = false
        else
            error("variables don't have a node!")
        end

        quad_expr = sum(var_to_var[quadtermsa[i]] * var_to_var[quadtermsb[i]] * quadconstants[i] for i in 1:length(quadterms))
    elseif any(x -> x in keys(var_to_var), quadvars)
        new_vars = [i for i in quadvars if !(i in keys(var_to_var))]
        node_set = unique([JuMP.owner_model(var_to_var[var]) for var in quadvars if (var in keys(var_to_var))])
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

        quad_expr = sum(var_to_var[quadtermsa[i]] * var_to_var[quadtermsb[i]] * quadconstants[i] for i in 1:length(quadterms))
    else
        error("Constraint $con_obj aff term has no node :(")
    end

    final_expr = quad_expr + new_expr

    return final_expr, link, owning_node, union(affvars, quadvars)
end

function get_linear_expression(con_obj, var_to_var, node_to_var)
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

    return new_expr, link, owning_node, vars
end

function build_graph_from_model(model, horizon)

    avs = all_variables(model)
    parsed_vars = parse_variable_name.(avs)
    var_to_parse_map = Dict(avs[i] => parsed_vars[i] for i in 1:length(avs))

    var_names = String.([:vZERO, :vZ_BUILD, :vP, :vNSE, :vFuel, :vStartFuel, :vFLOW, :vCANDFLOW, :p_bus, :p_virtual, :vCANDFLOW_TOTAL, :vCANDPROX, :slack_vFLOW, :slackup_vFLOW, :slackdown_vFLOW])
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
        "vPROX_ANGLE" => 2,
        "vCANDFLOW_TOTAL" => 2,
        "vCANDPROX" => 2,
        "slack_vFLOW" => 2,
        "slackup_vCANDFLOW" => 2, 
        "slackdown_vCANDFLOW" => 2
    )
    master_names = String.([:vZERO, :vZ_BUILD, :vNEW_TRANS_CAP_DECISION_INT, :vRETCAP])#, :vFuel])

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


    for (i, var) in enumerate(avs)
        if i%2000 == 0
            println("Running variable $i")
        end
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

    adj_node_idx = [[6,7], [12,13], [18, 19], [24, 1]]
    adj_node_idx = [[4,5], [8,9], [12,13], [16,17], [20,21], [24,1]]
    #adj_node_idx = []

    adj_node_sets = []#[union(Set([n[j] for j in idxs]), Set([master])) for idxs in adj_node_idx] 

    #println(adj_node_sets)
    for (i, con) in enumerate(acs)
        if i%20000 == 0
            println("running constraint $i")
        end
        con_obj = constraint_object(con)
        if typeof(con_obj.set) == MOI.EqualTo{Float64}
            new_expr, link, owning_node, vars = get_expr(con_obj, var_to_var, node_to_var)
            nodes = Set([JuMP.owner_model(var) for var in vars])
            
            if !(nodes in adj_node_sets)
                if link
                    graph_con = @linkconstraint(graph, new_expr == con_obj.set.value)
                else
                    graph_con = @constraint(owning_node, new_expr == con_obj.set.value)
                end
                con_to_con[con] = graph_con
                graph_con_to_con[graph_con] = con
            end
        elseif typeof(con_obj.set) == MOI.LessThan{Float64}
            new_expr, link, owning_node = get_expr(con_obj, var_to_var, node_to_var)
            nodes = Set([JuMP.owner_model(var) for var in keys(new_expr.terms)])

            if !(nodes in adj_node_sets)
            if link
                graph_con = @linkconstraint(graph, new_expr <= con_obj.set.upper)
            else
                graph_con = @constraint(owning_node, new_expr <= con_obj.set.upper)
            end
                con_to_con[con] = graph_con
                graph_con_to_con[graph_con] = con
            end
        elseif typeof(con_obj.set) == MOI.GreaterThan{Float64}
            new_expr, link, owning_node = get_expr(con_obj, var_to_var, node_to_var)
            nodes = Set([JuMP.owner_model(var) for var in keys(new_expr.terms)])

            if !(nodes in adj_node_sets)
            if link
                graph_con = @linkconstraint(graph, new_expr >= con_obj.set.lower)
            else
                graph_con = @constraint(owning_node, new_expr >= con_obj.set.lower)
            end
                con_to_con[con] = graph_con
                graph_con_to_con[graph_con] = con
            end
        elseif typeof(con_obj.set) == MOI.Interval{Float64}
            new_expr, link, owning_node = get_expr(con_obj, var_to_var, node_to_var)
            nodes = Set([JuMP.owner_model(var) for var in keys(new_expr.terms)])

            if !(nodes in adj_node_sets)
            if link
                graph_con = @linkconstraint(graph, con_obj.set.lower <= new_expr <= con_obj.set.upper)
            else
                graph_con = @constraint(owning_node, con_obj.set.lower <= new_expr <= con_obj.set.upper)
            end
                con_to_con[con] = graph_con
                graph_con_to_con[graph_con] = con
            end
        else
            println(con_obj.set)
            error("constraint object does not match types")
        end

    end

    jm_obj_func = objective_function(model)

    println("ADDING TO OBJECTIVE")
    for (i, node) in enumerate(keys(node_to_var))
        if i%100 == 0
            println("Running node $i")
        end
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

#g, v_to_v, ctc, gctc = build_graph_from_model(m, 8760);
#g, v_to_v, ctc, gctc = build_graph_from_model(m, 70);
g, v_to_v, ctc, gctc = build_graph_from_model(m, 24);

#set_to_node_objectives(g)
solver = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 60, "MIPGap" => 1e-3)#, "LogFile" => (@__DIR__)*"/bigM.txt")
set_optimizer(g, solver)
# optimize!(g)

#node_membership_vector = [1,2,2,2,2,2,2,2,2,1,3,3,3,3,3,3,3,3,3,3,3,3,3,3,1]
node_membership_vector = [1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2]
node_membership_vector = Int.(zeros(70 + 1))
#node_membership_vector = Int.(zeros(8760 + 1))
node_membership_vector[1] = 1
node_membership_vector[2:end] .= 2
node_membership_vector = [1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2]
#node_membership_vector = [1,1,2,2,2,2,2,3,3,3,3,3,3,4,4,4,4,4,4,5,5,5,5,5,5]

#node_membership_vector = [1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,6,6,6,6,7,7,7,7]

#node_membership_vector = [1,2,2,2,2,2,2,2,2,1,3,3,3,3,3,3,3,3,3,3,3,3,3,3,1]

node_partition = Partition(g, node_membership_vector)
apply_partition!(g, node_partition)

solver = optimizer_with_attributes(Gurobi.Optimizer, "MIPGap" => 1e-3, "OutputFlag" => 0, "TimeLimit" => 200, "InfUnbdInfo" => true, "BarHomogeneous" => 1, "Method" => 2, "Crossover" => 0)
solver = optimizer_with_attributes(Gurobi.Optimizer, "MIPGap" => 1e-3, "OutputFlag" => 0, "TimeLimit" => 200, "InfUnbdInfo" => true)#, "QCPDual" => 1, "PreSolve" => 0, "NonConvex" => -1)
solver_ipopt = optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0)
solver_sub = optimizer_with_attributes(Gurobi.Optimizer, "OutputFlag" => 0, "TimeLimit" => 1800, "InfUnbdInfo" => true, "QCPDual" => 1, "ObjScale" => 1e5, "ScaleFlag" => 2)
using PlasmoBenders

root_graph = getsubgraphs(g)[1]
sub_problem = getsubgraphs(g)[2]

#set_optimizer_attribute(root_graph, "OutputFlag", 1)
#set_optimizer_attribute(sub_problem, "OutputFlag", 1)
set_optimizer(root_graph, solver)
set_optimizer(sub_problem, solver_ipopt)
# root_avs = all_variables(root_graph)
# root_bin_vars = root_avs[JuMP.is_binary.(root_avs)]

# unset_binary.(root_bin_vars)
# set_upper_bound.(root_bin_vars, 1)
# set_lower_bound.(root_bin_vars, 0)

ba = BendersAlgorithm(
    g, 
    getsubgraphs(g)[1],
    max_iters = 100, 
    regularize=false,
    #solver = solver,
    #feasibility_cuts = true,
    tol = 1e-3
);

run_algorithm!(ba)

#root_sols = ba.ext["root_sols"]
#writedlm((@__DIR__)*"/bilinear_root_sols.csv", root_sols)


ba.best_upper_bound = Inf

for var in m[:slack_vFLOW]
    fix(v_to_v[var], 0, force = true)
end

ba.max_iters = 100
run_algorithm!(ba)

for var in m[:slackup_vCANDFLOW]
    fix(v_to_v[var], 0, force = true)
end
for var in m[:slackdown_vCANDFLOW]
    fix(v_to_v[var], 0, force = true)
end

root_avs = all_variables(root_graph)
root_bin_vars = root_avs[JuMP.is_binary.(root_avs)]

unset_binary.(root_bin_vars)
set_upper_bound.(root_bin_vars, 1)
set_lower_bound.(root_bin_vars, 0)

ba.best_upper_bound = Inf
ba.max_iters = ba.current_iter + 50
run_algorithm!(ba)

ba.max_iters = ba.current_iter + 150
ba.best_upper_bound = Inf
set_binary.(root_bin_vars)
run_algorithm!(ba)






builds = [0.]
for v in m[:vNEW_TRANS_CAP_DECISION_INT]
    builds[1] += value(ba, v_to_v[v])
end

#g, v_to_v, ctc, gctc = build_graph_from_model(m, 24);

# ba_vflows = zeros(76, 24)
# ba_vcandflows = zeros(76, 24)
# ba_vP = zeros(10, 24)
# ba_builds = zeros(76)

# for j in 1:24
#     for i in 1:76
#         flow_var = m[:vFLOW][i,j]
#         candflow_var = m[:vCANDFLOW][i,j,1]
#         ba_vflows[i,j] = value(ba, v_to_v[flow_var])
#         ba_vcandflows[i, j] = value(ba, v_to_v[candflow_var])
#     end
#     for i in 1:10
#         vP_var = m[:vP][i,j]
#         ba_vP[i,j] = value(ba, v_to_v[vP_var])
#     end    
# end
# for i in 1:76
#     build_var = m[:vNEW_TRANS_CAP_DECISION_INT][i, 1]
#     ba_builds[i] = value(ba, v_to_v[build_var])
# end

# using JLD2
# jldsave(
#     (@__DIR__)*"/Benders_solutions.jld2",
#     build = ba_builds,
#     vP = ba_vP,
#     flows = ba_vflows,
#     candflows = ba_vcandflows
# )

using Plots


iters = ba.current_iter
obj_val = 1.9228e6#ba.best_upper_bound#1.9228e6
ba_ub = [[minimum(ba.upper_bounds[1:i]) for i in 1:27]; [minimum(ba.upper_bounds[28:i]) for i in 28:51]; [minimum(ba.upper_bounds[52:i]) for i in 52:92]; [minimum(ba.upper_bounds[93:i]) for i in 93:length(ba.upper_bounds)]]
#ba_ub = [minimum(ba.upper_bounds[1:i]) for i in 1:length(ba.upper_bounds)]
ba_lb = ba.lower_bounds
plot([], [], color = "black", yaxis=:log10, label = "Upper Bound", legend = :bottomright, ylims=[1e5, 1e7])#, yticks = [1e-3,1e-2, 1e-1,1e0, 1e1, 1e2, 1e3, 1e4, 1e5], xticks = [0, 3, 6, 9, 12, 15, 18])
plot!([], [], color = "black", linestyle = :dash, label = "Lower Bound")
plot!([], [], color = "red", label = "Optimal")

plot!([1, iters], [obj_val, obj_val], color = "red", label = :none, linewidth = 3)
plot!(1:iters, ba_ub, color = "black", label = :none, linewidth = 2)
plot!(2:iters, ba_lb[2:iters], color = "black", linestyle = :dash, label = :none, linewidth = 2)
xlabel!("Benders Iteration")
ylabel!("Objective")
title!("49 Bus Case")


iters = ba.current_iter
obj_val = 1.9228e6#ba.best_upper_bound#1.9228e6
ba_ub = [[minimum(ba.upper_bounds[1:i]) for i in 1:27]; [minimum(ba.upper_bounds[28:i]) for i in 28:length(ba.upper_bounds)]]
#ba_ub = [minimum(ba.upper_bounds[1:i]) for i in 1:length(ba.upper_bounds)]
ba_lb = ba.lower_bounds
plot([], [], color = "black", yaxis=:log10, label = "GBD Upper Bound", legend = :bottomright, ylims=[1e5, 1e7])#, yticks = [1e-3,1e-2, 1e-1,1e0, 1e1, 1e2, 1e3, 1e4, 1e5], xticks = [0, 3, 6, 9, 12, 15, 18])
plot!([], [], color = "black", linestyle = :dash, label = "GBD Lower Bound")
plot!([], [], color = "red", label = "Optimal")

plot!([1, iters], [obj_val, obj_val], color = "red", label = :none, linewidth = 3)
plot!(1:iters, ba_ub, color = "black", label = :none, linewidth = 2)
plot!(2:iters, ba_lb[2:iters], color = "black", linestyle = :dash, label = :none, linewidth = 2)
xlabel!("Benders Iteration")
ylabel!("Objective")
title!("9 Bus Case")
#ylims!(2e3, 4e6)

