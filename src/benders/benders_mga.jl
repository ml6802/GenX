function run_benders_mga(benders_inputs::Dict{Any,Any},setup::Dict, inputs::Dict, opt_stats)
    nsubs = length(benders_inputs["subproblems"]);

    EP_master = benders_inputs["planning_problem"];
    master_vars = benders_inputs["planning_variables"];
    EP_subprob = benders_inputs["subproblems"];
    master_vars_sub = benders_inputs["planning_variables_sub"];

    cut_counter=0
    
    setup["MGABudget"] = opt_stats.UB_hist[end]*(1+setup["MGA_Slack"]);

    setup_mga_master_problem!(EP_master,setup)

    cut_counter = name_cuts!(EP_master, cut_counter)
    opt_cuts=name.(all_constraints(EP_master, include_variable_in_set_constraints = false))
    
    sumtime_df = DataFrame(:MGA_it => 0, :Iterations => length(opt_stats.UB_hist), :Iteration_Time => opt_stats.cpu_time[end]) 

    Iterations = setup["MGA_Iterations"]
    retain_master_cuts = setup["MGA_RetainBendersCuts"];
    println("Cut Setting " * string(retain_master_cuts))
    setup["BD_Stab_Method"] = "off"
    results = Array{Union{Dict,NamedTuple},2}(undef,(Iterations,2))
    variables = generate_variable_list(EP_master, setup, inputs)
    vectors = generate_vecs(setup, variables)

    for iteration in 1:Iterations
        if retain_master_cuts == 1
            # do nothing
        elseif retain_master_cuts == 2
            forget_cuts_master!(EP_master, opt_cuts)
        elseif retain_master_cuts == 3
            sp_cuts = retain_fixed_spcuts_early(EP_master, master_cuts, setup["MGA_MaxCuts"],nsubs)
            forget_cuts_master!(EP_master, sp_cuts)
        else
            println("No cut-retention method specified, defaulting to least-cost cuts")
            forget_cuts_master!(EP_master, opt_cuts)
        end
        @objective(EP_master,Min, sum(variable_by_name(EP_master, variables[i])*vectors[i,iteration] for i in eachindex(variables)))
	    @time EP_master, master_sol_final, subop_sol,ApproxSystemCost_hist, TrueSystemCost_hist, cpu_time = mga_cutting_plane(EP_master,master_vars,EP_subprob, master_vars_sub,setup,inputs,iteration);

        results[iteration,:] = [master_sol_final,subop_sol]
    
        time_df = DataFrame(:MGA_it => iteration, :Iterations => length(TrueSystemCost_hist), :Iteration_Time => cpu_time[end])
        append!(sumtime_df, time_df)
    end
    return results, sumtime_df, vectors, variables
end

function name_cuts!(EP_master::Model, counter::Int64)
    for con in all_constraints(EP_master,include_variable_in_set_constraints=false)
        if name(con) == ""
            set_name(con,"BendersCut"*string(counter))
        end
        counter+=1
    end 
    return counter
end

function update_master_problem_multi_cuts_mga!(EP::Model,subop_sol::Dict,master_sol::NamedTuple,master_vars_sub::Dict, mga_it::Int64, benders_it::Int64)
	W = keys(subop_sol);
	name = "BendersCut_"*string(mga_it)*"_"*string(benders_it)
    @constraint(EP, [w in W],subop_sol[w].theta_coeff*EP[:vTHETA][w] >= subop_sol[w].op_cost + sum(subop_sol[w].lambda[i]*(variable_by_name(EP,master_vars_sub[w][i]) - master_sol.values[master_vars_sub[w][i]]) for i in 1:length(master_vars_sub[w])), base_name = name*"_"*string(w));
end

function retain_recent_cuts(EP_master::Model, master_cons::Vector{String}, num_cuts::Int64)
    cut_names = Vector{String}(undef,0)
    opt_names = Vector{String}(undef,0)
    struc_names = Vector{String}(undef,0)
    for con in all_constraints(EP_master, include_variable_in_set_constraints=false)
        if name(con) == "" || occursin("BendersCut", name(con))
            split_name = split(name(con), "_")
            mga_it = parse(Int, split_name[2])
            if mga_it == 0
                push!(opt_names, name(con))
            else
                push!(cut_names,name(con))
            end
        else
            push!(struc_names,name(con))
        end
    end
    opt = length(opt_names)
    tot = length(cut_names)
    start=tot-num_cuts-opt
    if start <= 0
        start = 1
    end
    retained = [opt_names;cut_names[start:end]]
    new_master_cons=struc_names
    append!(new_master_cons, retained)
    return new_master_cons
end


function retain_fixed_spcuts_early(EP_master::Model, master_cons::Vector{String}, num_cuts::Int64, nsubs::Int64)
    cut_names = Vector{String}(undef,0)
    sp_cuts = Vector{Vector{String}}(undef, 0)
    for i in 1:nsubs
        push!(sp_cuts, Vector{String}(undef,0))
    end
    struc_names = Vector{String}(undef,0)
    for con in all_constraints(EP_master, include_variable_in_set_constraints=false)
        if occursin("BendersCut", name(con))
            split_name = split(name(con), "_")
            num = split(split_name[4], "[")
            push!(sp_cuts[parse(Int, num[1])], name(con))
        else
            push!(struc_names,name(con))
        end
    end
    
    for i in 1:nsubs
        tot = length(sp_cuts[i])
        if tot >= num_cuts
            sp_cuts[i] = sp_cuts[i][1:num_cuts]
        end
        cut_names = [cut_names;sp_cuts[i]]
    end
    
    new_master_cons=struc_names
    append!(new_master_cons, cut_names)
    return new_master_cons
end

function forget_cuts_master!(EP_master::Model,master_cons::Vector{String})
    for con in all_constraints(EP_master,include_variable_in_set_constraints=false)
        if name(con) in master_cons
            #do nothing
        else
            delete(EP_master,con)
        end
    end
end


function setup_mga_master_problem!(EP_master::Model,setup::Dict)
    #dfGen = inputs["dfGen"];
    #Z = inputs["Z"];

    @constraint(EP_master,cMGABudget, EP_master[:eObj] + sum(EP_master[:vTHETA]) == setup["MGABudget"])

    #TechTypes = unique(dfGen[dfGen[!, :MGA] .== 1, :Resource_Type])

    #@expression(EP_master,eTotalCapByType[type in TechTypes,z=1:Z],sum(EP_master[:eTotalCap][y] for y in dfGen[(dfGen[!,:Resource_Type] .== type)  .& (dfGen[!,:Zone] .== z), :R_ID]))

end


function solve_mga_master_problem(EP::Model,master_vars::Vector{String}, inputs::Dict, id::Int64, iteration::Int64, mga_it::Int64)
    iteration += 1
    println("In mga master problem solve")
    optimize!(EP)
    
    neg_cap_bool = false;
    if any(value.(EP[:eTotalCap]).<0)
        neg_cap_bool = true;
    elseif haskey(EP,:eTotalCapEnergy)
        if any(value.(EP[:eTotalCapEnergy]).<0)
            neg_cap_bool = true;
        end
    elseif haskey(EP,:eTotalCapCharge)
        if any(value.(EP[:eTotalCapCharge]).<0)
            neg_cap_bool = true;
        end
    elseif haskey(EP,:eAvail_Trans_Cap)
        if any(value.(EP[:eAvail_Trans_Cap]).<0)
            neg_cap_bool = true;
        end
    elseif any(value.(EP[:vCAP]).<0)
        neg_cap_bool = true;
    end
    if neg_cap_bool
        println("***Resolving the master problem with Crossover=1 because of negative capacities***")
        set_attribute(EP, "Crossover", 1)
        #set_attribute(EP, "BarHomogeneous", 1)
        optimize!(EP)
        if has_values(EP)
            zone_inv_cost = make_benders_zonal_invcost(inputs, EP)
            master_sol =  (inv_cost =value(EP[:eObj]), net_exp_cost = value(EP[:eTotalCNetworkExp]), zone_inv_cost = zone_inv_cost, values =Dict([s=>value.(variable_by_name(EP,s)) for s in master_vars]), id = id, iteration = iteration, mga_it=mga_it)
            set_attribute(EP, "Crossover", 0)
        end
    else
        zone_inv_cost = make_benders_zonal_invcost(inputs, EP)
        master_sol =  (inv_cost =value(EP[:eObj]),net_exp_cost = value(EP[:eTotalCNetworkExp]),zone_inv_cost = zone_inv_cost, values =Dict([s=>value.(variable_by_name(EP,s)) for s in master_vars]), id=id, iteration=iteration,mga_it=mga_it)
    end
	return master_sol
end

function mga_cutting_plane(EP_master::Model, master_vars::Vector{String},EP_subprob, master_vars_sub,setup::Dict, inputs::Dict, mga_it::Int64)
	
	## Start solver time
    cpu_time = [0.0];
	solver_start_time = time()
	id=1
	iteration=1
	indicator = 0

	#### Algorithm parameters:
	
	MaxIter = setup["BD_MaxIter"]
	MaxCpuTime = setup["BD_MaxCpuTime"]
	γ = 0.0 #setup["BD_MGA_StabParam"];
	stab_method = "off" #setup["BD_MGA_Stab_Method"];

    TrueSystemCost = Inf;
    ApproxSystemCost = setup["MGABudget"];

    ApproxSystemCost_hist = [ApproxSystemCost];
    TrueSystemCost_hist = [TrueSystemCost];
    master_sol_temp = (inv_cost = 0.0, values =Dict());
	master_sol_final = (inv_cost = 0.0, values =Dict());
    subop_sol = Dict()
    #### Run Benders iterations
    master_times=Vector{Float64}(undef,0)
    sub_times=Vector{Float64}(undef,0)
    id = 1
    
    for k = 1:MaxIter
		start_master_sol = time()
		master_sol = solve_mga_master_problem(EP_master,master_vars, inputs,id, k,mga_it);
		cpu_master_sol = time()-start_master_sol;
		println("Solving the master problem required $cpu_master_sol seconds")

		start_subop_sol = time();
        subop_sol = solve_dist_subproblems(EP_subprob,master_sol,inputs);
		cpu_subop_sol = time()-start_subop_sol;
		push!(sub_times, cpu_subop_sol)
		println("Solving the subproblems required $cpu_subop_sol seconds")

		TrueSystemCost_new = sum(subop_sol[w].op_cost for w in keys(subop_sol))+master_sol.inv_cost;
		if TrueSystemCost_new <= TrueSystemCost
        	TrueSystemCost = copy(TrueSystemCost_new);
			master_sol_final = deepcopy(master_sol);
		end

        append!(ApproxSystemCost_hist,ApproxSystemCost)
        append!(TrueSystemCost_hist,TrueSystemCost)
        append!(cpu_time,time()-solver_start_time)
		
		println("k = ", k,"      ApproxSystemCost = ", ApproxSystemCost,"     TrueSystemCost = ", TrueSystemCost,"     TrueSystemCost_new = ", TrueSystemCost_new,"       MGABudget Violation = ", (TrueSystemCost_new-setup["MGABudget"])/abs(setup["MGABudget"]),"       CPU Time = ",cpu_time[end])

        if (isapprox(TrueSystemCost_new, setup["MGABudget"], rtol=setup["RelaxBudget"]) && setup["RelaxBudget"] > 0) || (TrueSystemCost_new <= setup["MGABudget"])
            if indicator == 0
                println("Rerunning with crossover on")
                set_attribute(EP_master, "Crossover", 1)
                TrueSystemCost = Inf;
                TrueSystemCost_new = Inf;
                indicator = 1
            else
                set_attribute(EP_master, "Crossover", 0)
                master_avg = mean(master_times)
                subop_avg = mean(sub_times)
                ms_ratio = master_avg/subop_avg
                println("MGA iteration finished")
                println("Average Master Time = "*string(master_avg))
                println("Average Subop Time = "*string(subop_avg))
                println("Master/Subop Ratio = "*string(ms_ratio))
        
                return (EP_master=EP_master,master_sol = master_sol_final,subop_sol=subop_sol,ApproxSystemCost_hist = ApproxSystemCost_hist,TrueSystemCost_hist = TrueSystemCost_hist,cpu_time = cpu_time)
		    end
		elseif cpu_time[end] >= MaxCpuTime
			return (EP_master=EP_master,master_sol = master_sol_final,subop_sol=subop_sol,ApproxSystemCost_hist = ApproxSystemCost_hist,TrueSystemCost_hist = TrueSystemCost_hist,cpu_time = cpu_time)
        else
            print("Updating the master problem....")
            time_start_update = time()
            if setup["BD_Mode"]=="full"
                update_master_problem_single_cut!(EP_master,subop_sol,master_sol,master_vars_sub)
            elseif setup["BD_Mode"]=="serial" || setup["BD_Mode"]=="distributed"
                update_master_problem_multi_cuts_mga!(EP_master,subop_sol,master_sol,master_vars_sub,mga_it,k)
            end
            time_master_update = time()-time_start_update
            println("done (it took $time_master_update s).")
            master_time = cpu_master_sol + time_master_update
            push!(master_times, master_time)
        end
    end
end

function generate_variable_list(EP_master::Model, setup::Dict, inputs::Dict)
    variables = Vector{String}(undef,0)
    var_type = setup["MGA_VariableType"]
    techs = setup["MGA_Technologies"] == [] ? collect(unique(inputs["RESOURCES"].resource_type)) : setup["MGA_Technologies"]
    ag_level = setup["MGA_AggregationLevel"]
    include_transmission = setup["MGA_IncludeTransmission"] 

    if var_type == "capacity"
        if ag_level == 1
            @expression(EP_master,eTotalCapByType[type in techs], sum(EP_master[:vSumvCap][type, z] for z in 1:inputs["Z"]))
            variables = name.(EP_master[:eTotalCapByType])
            if include_transmission == true
                @expression(EP_master,eTotalTransCap, sum(EP_master[:vNEW_TRANS_CAP][l] for l in 1:inputs["lines"]))
                variables = vcat(variables, name(EP_master[:eTotalTransCap]))
            end
        elseif ag_level == 2
            for v in name.(EP_master[:vSumvCap])
                if any(s -> occursin(s, v), techs)
                    push!(variables, v)
                end
            end
            if include_transmission == true
                variables = vcat(variables, [name(v) for v in all_variables(EP_master) if occursin("vNEW_TRANS_CAP", name(v))])
            end
        elseif ag_level == 3
            error("Cluster-level aggregation not currently implemented. To use cluster-level variables, please specify custom variables in mga_custom_weights.csv and set MGA_VariableType to 'custom'.")
            #variables = [name(e) for e in EP_master[:eTotalCap]]
            #if include_transmission == true
            #    variables = vcat(variables, [name(v) for v in all_variables(EP_master) if occursin("vNEW_TRANS_CAP", name(v))])
            #end
        end
    elseif var_type == "custom"
        variables = setup["CustomObjs"].variables
    else
        error("operational variables not implemented")
    end
    return variables
end

function make_rand_vecs(nvars::Int64, iterations::Int64)
    vecs = randn(nvars, ceil(Int64, iterations/2))
    vecs = hcat(vecs, -1*vecs)
    vecs = vecs[:,1:iterations]
    return vecs
end

function make_capmm_vecs(nvars::Int64, iterations::Int64)
    vecs = unique(rand(-1:1,nvars, ceil(Int64, iterations)), dims=2)[:,1:ceil(Int64, iterations/2)]
    vecs = hcat(vecs, -1*vecs)
    vecs = vecs[:,1:iterations]
    return vecs
end

function find_ratio(setup::Dict)
    if setup["MGA_Method"] == 0
        if setup["MGA_ComboRatio"] >= 0 && setup["MGA_ComboRatio"] <= 1
            return setup["MGA_ComboRatio"]
        else
            println("Invalid combo ratio specified. Defaulting to 0.25 (i.e. 25% random vectors and 75% capMM vectors).")
            return 0.25
        end
    else
        return 0
    end
end

function generate_vecs(setup::Dict, variables::Vector{String})
    iterations = setup["MGA_Iterations"]
    method = setup["MGA_Method"]
    combo_ratio = find_ratio(setup)
    seed = setup["MGA_RandomSeed"]

    nvars = length(variables)
    vecs = Array{Float64,2}(undef,nvars, iterations)
    Random.seed!(seed)

    #### Generate vectors
    if method == 1
        vecs = make_rand_vecs(nvars, iterations)
    elseif method == 2
        vecs = make_capmm_vecs(nvars, iterations)
    elseif method == 0
        vecs_a = make_rand_vecs(nvars, ceil(Int64, iterations*combo_ratio))
        vecs_b = make_capmm_vecs(nvars, ceil(Int64, iterations*(1-combo_ratio)))
        
        vecs = hcat(vecs_a, vecs_b)[:,1:iterations]
    elseif method == 3
        vecs = setup["CustomObjs"].vectors
    else
        error("Invalid MGA_Method specified. Please specify 0 for combination of random and capMM vectors, 1 for random vectors, 2 for capMM vectors, or 3 for custom vectors.")
    end
    vecs = reorder_vecs(vecs, setup)
    return vecs
end

function reorder_vecs(vecs::Array{Float64,2}, setup::Dict)
    if setup["MGA_VectorSortMethod"] == "angle"
        norms = [norm(vecs[:,i]) for i in 1:size(vecs,2)]
        angles = [acos(dot(vecs[:,i], vecs[:,1])/(norms[i]*norms[1])) for i in 1:size(vecs,2)]
        sorted_indices = sortperm(angles)
        vecs = vecs[:,sorted_indices]
    elseif setup["MGA_VectorSortMethod"] == "nearest-neighbor"
        sorted_indices = [1]
        for i in 2:size(vecs,2)
            last_vec = vecs[:,sorted_indices[end]]
            distances = [norm(vecs[:,j] - last_vec) for j in 1:size(vecs,2)]
            sorted_indices = vcat(sorted_indices, argmin(distances))
        end
    end
    return vecs
end