function run_benders_mga(benders_inputs::Dict{Any,Any},setup::Dict, inputs::Dict, opt_stats)
    nsubs = length(benders_inputs["subproblems"]);
    
    opt_sol = Dict();

    EP_master = benders_inputs["planning_problem"];
    master_vars = benders_inputs["planning_variables"];
    EP_subprob = benders_inputs["subproblems"];
    master_vars_sub = benders_inputs["planning_variables_sub"];
    mga_vectors = benders_inputs["mga_vectors"]

    cut_counter=0
    
    setup["MGABudget"] = opt_stats.UB_hist[end]*(1+setup["ModelingtoGenerateAlternativeSlack"]);

    setup_mga_master_problem!(EP_master,setup)

    cut_counter = name_cuts!(EP_master, cut_counter)
    opt_cuts=name.(all_constraints(EP_master, include_variable_in_set_constraints = false))

    indx = collect(1:length(opt_stats.UB_hist)-1)
    mga_it = zeros(Int64, length(opt_stats.UB_hist)-1)
    
    sumtime_df = DataFrame(:MGA_it => 0, :Iterations => length(opt_stats.UB_hist), :Iteration_Time => opt_stats.cpu_time[end]) 


    (TechTypes, Zones, Iterations) = size(mga_vectors)
    retain_master_cuts = setup["ModelingToGenerateAlternativeRetainBendersCuts"];
    println("Cut Setting " * string(retain_master_cuts))
    setup["BD_Stab_Method"] = "off"
    results = Array{Union{Dict,NamedTuple},2}(undef,(Iterations,2))
    id = 1
    

    for iteration in 1:Iterations
        if retain_master_cuts == 1
            # do nothing
        elseif retain_master_cuts == 2
            forget_cuts_master!(EP_master, opt_cuts)
        elseif retain_master_cuts == 3
            recent_cuts = retain_recent_cuts(EP_master, master_cuts, setup["MaxCuts"])
            forget_cuts_master!(EP_master, recent_cuts)
        elseif retain_master_cuts == 5
            sp_cuts = retain_fixed_spcuts_early(EP_master, master_cuts, setup["MaxCuts"],nsubs)
            forget_cuts_master!(EP_master, sp_cuts)
        else
            println("No cut-retention method specified, defaulting to least-cost cuts")
            forget_cuts_master!(EP_master, opt_cuts)
        end
        @objective(EP_master,Min,sum(mga_vectors[tt,z,iteration]*EP_master[:vSumvCap][tt,z] for z in 1:Zones, tt in 1:TechTypes))
      #  if setup["BD_IntegerMethod"] == 2 && setup["IntegerInvestments"] == 1
        #    all_master_vars = all_variables(EP_master);
    	#	integer_vars = all_master_vars[is_integer.(all_master_vars)];
    	#	binary_vars = all_master_vars[is_binary.(all_master_vars)];
    	#	unset_integer.(integer_vars)
    	#	unset_binary.(binary_vars)
    		
    		#EP_master, master_sol_final, subop_sol,ApproxSystemCost_hist, TrueSystemCost_hist, cpu_time = mga_cutting_plane(EP_master,master_vars,EP_subprob, master_vars_sub,setup,inputs, iteration);
        #
          #  set_integer.(integer_vars)
		#	set_binary.(binary_vars)
		#	_setup = deepcopy(setup);
		#	_setup["BD_Stab_Method"] = "off";
			
		#	 EP_master, master_sol_final, subop_sol,ApproxSystemCost_hist, TrueSystemCost_hist, cpu_time = mga_cutting_plane(EP_master,master_vars,EP_subprob, master_vars_sub,setup,inputs,iteration);
	    #else
	        @time EP_master, master_sol_final, subop_sol,ApproxSystemCost_hist, TrueSystemCost_hist, cpu_time = mga_cutting_plane(EP_master,master_vars,EP_subprob, master_vars_sub,setup,inputs,iteration);
	   # end
        results[iteration,:] = [master_sol_final,subop_sol]
    
        time_df = DataFrame(:MGA_it => iteration, :Iterations => length(TrueSystemCost_hist), :Iteration_Time => cpu_time[end])
        append!(sumtime_df, time_df)
    end

    return results, sumtime_df
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
            master_sol =  (inv_cost =value(EP[:eObj]),zone_inv_cost = zone_inv_cost, values =Dict([s=>value.(variable_by_name(EP,s)) for s in master_vars]), id = id, iteration = iteration, mga_it=mga_it)
            set_attribute(EP, "Crossover", 0)
        end
    else
        zone_inv_cost = make_benders_zonal_invcost(inputs, EP)
        master_sol =  (inv_cost =value(EP[:eObj]),zone_inv_cost = zone_inv_cost, values =Dict([s=>value.(variable_by_name(EP,s)) for s in master_vars]), id=id, iteration=iteration,mga_it=mga_it)
    end
	return master_sol
end

function mga_cutting_plane(EP_master::Model, master_vars::Vector{String},EP_subprob, master_vars_sub,setup::Dict, inputs::Dict, mga_it::Int64)
	
	## Start solver time
    cpu_time = [0.0];
	solver_start_time = time()
	id=1
	iteration=1

	#### Algorithm parameters:
	
	MaxIter = setup["BD_MaxIter"]
	MaxCpuTime = setup["BD_MaxCpuTime"]
	γ = 0.0 #setup["BD_MGA_StabParam"];
	stab_method = "off" #setup["BD_MGA_Stab_Method"];

    TrueSystemCost = 100000000.0
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
            #master_sol = deepcopy(master_sol_temp);
		end

        append!(ApproxSystemCost_hist,ApproxSystemCost)
        append!(TrueSystemCost_hist,TrueSystemCost)
        append!(cpu_time,time()-solver_start_time)
		
		println("k = ", k,"      ApproxSystemCost = ", ApproxSystemCost,"     TrueSystemCost = ", TrueSystemCost,"     TrueSystemCost_new = ", TrueSystemCost_new,"       MGABudget Violation = ", (TrueSystemCost_new-setup["MGABudget"])/abs(setup["MGABudget"]),"       CPU Time = ",cpu_time[end])

        if (isapprox(TrueSystemCost_new, setup["MGABudget"], rtol=setup["RelaxBudget"]) && setup["RelaxBudget"] > 0) || TrueSystemCost_new <= setup["MGABudget"]
            master_avg = mean(master_times)
            subop_avg = mean(sub_times)
            ms_ratio = master_avg/subop_avg
            println("MGA iteration finished")
            println("Average Master Time = "*string(master_avg))
            println("Average Subop Time = "*string(subop_avg))
            println("Master/Subop Ratio = "*string(ms_ratio))
            return (EP_master=EP_master,master_sol = master_sol_final,subop_sol=subop_sol,ApproxSystemCost_hist = ApproxSystemCost_hist,TrueSystemCost_hist = TrueSystemCost_hist,cpu_time = cpu_time)
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


function make_rand_vecs(iterations::Int64, TechTypes::Int64, Zones::Int64)
    vecs = rand(Float64,(TechTypes,Zones,iterations))
    return vecs
end

function make_capMM_vecs(iterations::Int64, TechTypes::Int64, Zones::Int64)
    vecs =  unique_int(rand(-1:1,TechTypes,2*iterations))#unique_int(rand(-1:1,TechTypes,Zones,2*iterations))
    #check_it_a!(vecs,iterations)
    check_it_a_ag!(vecs,iterations)
    cap_vecs = convert_ag_to_disag(vecs,Zones)
    return cap_vecs
end

function unique_int(points::AbstractArray)
    pointst = transpose(points)
    nrow, ncol = size(points)

    uniques = fill(-2, (nrow, ncol))
    counter=0
    for i in 1:ncol
        for k in 1:ncol
            if points[:,i]==uniques[:,k]
                break
            elseif k == ncol
                counter = counter + 1
                uniques[:,counter] = points[:,i]
            end
        end
    end
    uniques = uniques[1:end, 1:counter]
    uniquesT = transpose(uniques)
    println("Done with uniques")
    return uniques
end

function make_combo_vecs(iterations::Int64, TechTypes::Int64, Zones::Int64, ratio::Float64)
    rand_vecs = make_rand_vecs(ceil(Int64,iterations*ratio),TechTypes,Zones)
    cap_vecs = make_capMM_vecs(floor(Int64,iterations*(1-ratio)),TechTypes, Zones)
    vecs = cat(rand_vecs,cap_vecs,dims=3)
    vecs = vecs[:,:,1:iterations]
    return vecs
end

function convert_ag_to_disag(ag_vecs::AbstractArray, Zones::Int64)
    (techs,iterations) = size(ag_vecs)
    vecs = Array{Float64,3}(undef,(techs,Zones,iterations))
    for i in 1:iterations
        for j in 1:techs
			vecs[j,:,i] .= ag_vecs[j,i]
        end
    end
    return vecs
end

function check_it_a_ag!(a::AbstractArray, iterations::Int64)
    (r,i) = size(a)
    if iterations < i
        a = a[1:r,1:iterations]
        return a
    else
        println("Error")
    end
end

function check_it_a!(a::AbstractArray, iterations::Int64)
    (r,c,i) = size(a)
    if iterations < i
        a = a[1:r,1:c, 1:iterations]
        return a
    else
        println("Error")
    end
end

function find_ratio(setup::Dict)
    ratio = 0.0
    if "ComboRatio" in keys(setup)
        ratio = setup["ComboRatio"]
        if ratio < 1
            return ratio
        else
            throw(ErrorException("Ratio greater than 1"))
        end
    else
        ratio = 0.25
    end
    return ratio
end

function generate_vecs(inputs::Dict, setup::Dict)
    iterations = setup["ModelingToGenerateAlternativeIterations"]
    TechTypes = collect(eachindex(unique(inputs["RESOURCES"].resource_type)))[end]
    zones = inputs["Z"]
    println(TechTypes)
    println(iterations)
    method = setup["MGAMethod"]
    cluster_vecs = setup["ClusterMGAVecs"]

    
    n_its = iterations
    
    if method == 0
        ratio = find_ratio(setup)
        mats = make_combo_vecs(iterations,TechTypes,zones,ratio)
    elseif method == 1
        mats = make_rand_vecs(iterations,TechTypes,zones)
    elseif method == 2
        mats = make_capMM_vecs(iterations,TechTypes,zones)
    end
    max_mats = -1.0 .* mats
    all_mats = cat(mats, max_mats, dims=3)
    
    if cluster_vecs == 1
        nclusters= setup["NumMGACluster"]
        focus_cluster = setup["FocusCluster"]
        if focus_cluster == 1
            iterations = 320
            nclusters = 16
        end
        all_vecs = Vector{Vector{Float64}}(undef,0)
        (r,c,its) = size(all_mats)
        vec_leng = r*c
        for i in 1:its
            mat = all_mats[:,:,i]
            vec = reshape(mat, vec_leng)
            push!(all_vecs, vec)
        end
        all_vecs = mapreduce(permutedims, vcat, all_vecs)
        if focus_cluster == 0
            all_vecs = kmeanscluster_vecs(all_vecs, nclusters)
        else
            all_vecs = kmeansfocuscluster_vecs(all_vecs, nclusters, n_its)
        end
        
        for i in 1:n_its*2
            all_mats[:,:,i] = reshape(all_vecs[i,:], (r,c))
        end
    end
    return all_mats
end

function kmeanscluster_vecs(vecs::AbstractArray, nclusters::Int64)
    vecsT = (vecs')
    result= kmeans(vecsT,nclusters)
    clusters=Vector{Vector{Vector{Float64}}}(undef,0)
    final_clusters = Vector{Vector{Float64}}(undef,0)
    for i in 1:nclusters
        push!(clusters, Vector{Vector{Float64}}(undef,0))
    end
    assignments = result.assignments
    for i in 1:length(assignments)
        push!(clusters[assignments[i]], vecs[i,:])
    end
    for i in 1:nclusters
        append!(final_clusters, clusters[i])
    end
    vecs_out = mapreduce(permutedims, vcat, final_clusters)
    return vecs_out
end

function kmeansfocuscluster_vecs(vecs::AbstractArray, nclusters::Int64, n_its::Int64)
    vecsT = (vecs')
    result= kmeans(vecsT,nclusters)
    clusters=Vector{Vector{Vector{Float64}}}(undef,0)
    final_clusters = Vector{Vector{Float64}}(undef,0)
    for i in 1:nclusters
        push!(clusters, Vector{Vector{Float64}}(undef,0))
    end
    assignments = result.assignments
    for i in 1:length(assignments)
        push!(clusters[assignments[i]], vecs[i,:])
    end
    for i in 1:nclusters
        if length(clusters[i]) >= n_its*2
            final_clusters = clusters[i][1:n_its*2]
            break
        end
        #append!(final_clusters, clusters[i])
    end
    vecs_out = mapreduce(permutedims, vcat, final_clusters)
    return vecs_out
end