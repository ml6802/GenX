function benders(benders_inputs::Dict{Any,Any},setup::Dict,inputs)
	
    #### Algorithm from:
    ### Pecci, F. and Jenkins, J. D. “Regularized Benders Decomposition for High Performance Capacity Expansion Models”. arXiv:2403.02559 [math]. URL: http://arxiv.org/abs/2403.02559.

	### It's a regularized version of the Benders decomposition algorithm in:
	### A. Jacobson, F. Pecci, N. Sepulveda, Q. Xu, and J. Jenkins, “A computationally efficient Benders decomposition for energy systems planning problems with detailed operations and time-coupling constraints.” INFORMS Journal on Optimization 6(1):32-45. doi: https://doi.org/10.1287/ijoo.2023.0005

	## Start solver time
	solver_start_time = [time()]

    planning_problem = benders_inputs["planning_problem"];
	planning_variables = benders_inputs["planning_variables"];

	subproblems = benders_inputs["subproblems"];
	planning_variables_sub = benders_inputs["planning_variables_sub"];
    
    #### Algorithm parameters:
	MaxIter = setup["BD_MaxIter"]
    ConvTol = setup["BD_ConvTol"]
	MaxCpuTime = setup["BD_MaxCpuTime"]
	γ = setup["BD_StabParam"];
	stab_method = setup["BD_Stab_Method"];
    integer_investment = setup["IntegerInvestments"]
	if !haskey(setup, "BD_integer_routine")
		setup["BD_integer_routine"] = 0
		integer_routine_flag = false
	elseif setup["BD_integer_routine"] == 1
		integer_routine_flag = true
	else
		integer_routine_flag = false
	end
	if !(haskey(setup, "BD_post_warmstart_ConvTol"))
		post_warmstart_ConvTol = ConvTol
	else
		post_warmstart_ConvTol = setup["BD_post_warmstart_ConvTol"]
	end


	if !haskey(setup, "BD_warmstart_bilinear")
		setup["BD_warmstart_bilinear"] = 0
		warmstart_bilinear_routine = false
	elseif setup["BD_warmstart_bilinear"] == 1
		warmstart_bilinear_routine = true
	else
		warmstart_bilinear_routine = false
	end

	if !haskey(setup, "BD_warmstart_bigM")
		setup["BD_warmstart_bigM"] = 0
		warmstart_linear_routine = false
	elseif setup["BD_warmstart_bigM"] == 1
		warmstart_linear_routine = true
	else
		warmstart_linear_routine = false
	end

	# if !haskey(setup, "BD_cap_integer_routine")
	# 	setup["BD_cap_integer_routine"] = 0
	# 	cap_integer_routine = false
	# elseif setup["BD_cap_integer_routine"] == 1
	# 	if integer_routine_flag == 1
	# 		cap_integer_routine = false
	# 	else
	# 		cap_integer_routine = true
	# 	end
	# else
	# 	cap_integer_routine = false
	# end

	if !haskey(setup, "BD_post_warmstart_integer_routine")
		setup["BD_post_warmstart_integer_routine"] = 0
		post_warmstart_integer_routine = false
	elseif setup["BD_post_warmstart_integer_routine"] == 1
		post_warmstart_integer_routine = true
		if !(warmstart_bilinear_routine) && !(warmstart_linear_routine)
			error("post warmstart routine turned on, but no warmstarting is set")
		end
	else
		post_warmstart_integer_routine = false
	end

	if haskey(setup, "BD_warmstart_bigM_maxiter")
		BD_warmstart_bigM_maxiter = setup["BD_warmstart_bigM_maxiter"]
	else
		BD_warmstart_bigM_maxiter = 200
	end

	if haskey(setup, "BD_warmstart_bilinear_maxiter")
		BD_warmstart_bilinear_maxiter = setup["BD_warmstart_bilinear_maxiter"]
	else
		BD_warmstart_bilinear_maxiter = 200
	end

	if haskey(setup, "BD_integer_routine_maxiter")
		BD_integer_routine_maxiter = setup["BD_integer_routine_maxiter"]
	else
		BD_integer_routine_maxiter = 250
	end

	if haskey(setup, "BD_post_warmstart_integer_routine_maxiter")
		BD_post_warmstart_integer_routine_maxiter = setup["BD_post_warmstart_integer_routine_maxiter"]
	else
		BD_post_warmstart_integer_routine_maxiter = 300
	end

	#integer_routine_flag = false
	if integer_routine_flag# && stab_method != "off"
		all_planning_variables = all_variables(planning_problem);
		integer_variables = all_planning_variables[is_integer.(all_planning_variables)];
		binary_variables = all_planning_variables[is_binary.(all_planning_variables)]; #APPEND
		unset_integer.(integer_variables)
		unset_binary.(binary_variables)
		set_upper_bound.(binary_variables, 1)
		set_lower_bound.(binary_variables, 0)
		integer_routine_flag = true;
	elseif post_warmstart_integer_routine
		all_planning_variables = all_variables(planning_problem);
		integer_variables = all_planning_variables[is_integer.(all_planning_variables)];
		binary_variables = all_planning_variables[is_binary.(all_planning_variables)]; #APPEND
	# elseif cap_integer_routine
	# 	all_planning_variables = all_variables(planning_problem);
	# 	integer_variables = all_planning_variables[is_integer.(all_planning_variables)];
	# 	unset_integer.(integer_variables)
	end

	
	# all_planning_variables = all_variables(planning_problem);
		# integer_variables = all_planning_variables[is_integer.(all_planning_variables)];
		# binary_variables = all_planning_variables[is_binary.(all_planning_variables)];
		# unset_integer.(integer_variables)
		# unset_binary.(binary_variables)
		# set_upper_bound.(binary_variables, 1)
		# set_lower_bound.(binary_variables, 0)
    #### Initialize UB and LB
	planning_sol = solve_planning_problem(planning_problem,planning_variables,inputs);
	subop_sol = Dict()

    UB = Inf;
    LB = planning_sol.LB;

    LB_hist = Float64[];
    UB_hist = Float64[];
    cpu_time = Float64[];
	feasibility_hist = Float64[];

	planning_sol_best = deepcopy(planning_sol);
	planning_sol_last = [planning_sol]
	# build_decisions = zeros(length(planning_problem[:vNEW_TRANS_CAP_DECISION_INT]))

    #### Run Benders iterations
    for k = 0:MaxIter
		
		start_subop_sol = time();

        
        t1 = @elapsed subop_sol, has_duals = solve_dist_subproblems(subproblems,planning_sol,inputs);
        println("Time to run distributed subproblems is ", t1 / 60, " minutes")
        
		cpu_subop_sol = time()-start_subop_sol;
		# @info "Solving the subproblems required $cpu_subop_sol seconds"
		# @info "Investment Cost: " planning_sol.inv_cost
		# @info "Operational Cost: " sum(subop_sol[w].op_cost for w in keys(subop_sol))

        t2 = @elapsed begin
		UBnew = sum((subop_sol[w].theta_coeff==0 ? Inf : subop_sol[w].op_cost) for w in keys(subop_sol))+planning_sol.inv_cost;
		if UBnew < UB
			planning_sol_best = deepcopy(planning_sol);
			UB = UBnew;
		end
		end
		# println("Time to copy planning_sol was ", t2 / 60, " minutes")

		# print("Updating the planning problem....")
		time_start_update = time()

		if haskey(setup, "multicuts")
			if setup["multicuts"] == 1
				update_planning_problem_multi_cuts!(planning_problem,subop_sol,planning_sol,planning_variables_sub)
			else
				update_planning_problem_aggregated_cuts!(planning_problem,subop_sol,planning_sol,planning_variables_sub)
			end
		else
			update_planning_problem_multi_cuts!(planning_problem,subop_sol,planning_sol,planning_variables_sub)
		end

		if !(has_duals)
			println("RUNNING INT_LEVEL_SET DUE TO NO SOLUTIONS RECOVERED")
			flush(stdout)
			planning_sol = solve_int_level_set_problem(planning_problem,planning_variables,planning_sol_last[1],LB,UB,γ,inputs);

			t1 = @elapsed subop_sol, has_duals = solve_dist_subproblems(subproblems,planning_sol,inputs);
        	println("Time to run distributed subproblems is ", t1 / 60, " minutes")
			
			cpu_subop_sol = time()-start_subop_sol;
			# @info "Solving the subproblems required $cpu_subop_sol seconds"
			# @info "Investment Cost: " planning_sol.inv_cost
			# @info "Operational Cost: " sum(subop_sol[w].op_cost for w in keys(subop_sol))

        	t2 = @elapsed begin
			UBnew = sum((subop_sol[w].theta_coeff==0 ? Inf : subop_sol[w].op_cost) for w in keys(subop_sol))+planning_sol.inv_cost;
			if UBnew < UB
				planning_sol_best = deepcopy(planning_sol);
				UB = UBnew;
			end
			end
			# println("Time to copy planning_sol was ", t2 / 60, " minutes")

			# print("Updating the planning problem....")
			time_start_update = time()

			if haskey(setup, "multicuts")
				if setup["multicuts"] == 1
					update_planning_problem_multi_cuts!(planning_problem,subop_sol,planning_sol,planning_variables_sub)
				else
					update_planning_problem_aggregated_cuts!(planning_problem,subop_sol,planning_sol,planning_variables_sub)
				end
			else
				update_planning_problem_multi_cuts!(planning_problem,subop_sol,planning_sol,planning_variables_sub)
			end
		end
		time_planning_update = time()-time_start_update
		println("done (it took $time_planning_update s).")
		
		avs = all_variables(planning_problem)
		start_planning_sol = time()

		unst_planning_sol = solve_planning_problem(planning_problem,planning_variables,inputs);
		
		planning_sol_last[1] = unst_planning_sol

		cpu_planning_sol = time()-start_planning_sol;
		println("Solving the planning problem required $cpu_planning_sol seconds")

		LB = max(LB,unst_planning_sol.LB);
		
		append!(LB_hist,LB)
        append!(UB_hist,UB)
		append!(feasibility_hist,sum(subop_sol[w].feasibility_slack for w in keys(subop_sol)))
        append!(cpu_time,time()-solver_start_time[1])

		if any(subop_sol[w].theta_coeff==0 for w in keys(subop_sol))
			println("***k = ", k,"      LB = ", LB,"     UB = ", UB,"       Gap = ", (UB-LB)/abs(LB),"       CPU Time = ",cpu_time[end])
		else
			println("k = ", k,"      LB = ", LB,"     UB = ", UB,"       Gap = ", (UB-LB)/abs(LB),"       CPU Time = ",cpu_time[end])
		end

		#println(unst_planning_sol)
		
		# for i in 1:length(planning_problem[:vNEW_TRANS_CAP_DECISION_INT])
		# 	key = "vNEW_TRANS_CAP_DECISION_INT[$i]"
		# 	val = unst_planning_sol.values[key]
		# 	build_decisions[i] = val
		# end
		# build_indices = findall(x -> x > 0.5, build_decisions)
		# @debug "Lines built at iteration $k: " build_indices
		# @debug "Number of lines built at iteration $k: " length(build_indices)

		#@debug "Theta" Vector(value.(planning_problem[:vTHETA]))

		#cap_builds = findall(x -> x > 0.1, Vector(value.(planning_problem[:vCAP])))
		#@debug "vCAP Builds" cap_builds

        flush(stdout)
		
        if (UB-LB)/abs(LB) <= ConvTol || (integer_routine_flag && k == BD_integer_routine_maxiter) || (warmstart_bilinear_routine && k == BD_warmstart_bilinear_maxiter) || (warmstart_linear_routine && k == BD_warmstart_bigM_maxiter) || (post_warmstart_integer_routine && k == BD_post_warmstart_integer_routine_maxiter)
			if integer_routine_flag
				println()
				println()
				println()
				println()
				println()
				println("*** Switching on integer constraints *** ")
				println()
				println()  
				println()
				println()
				println()
				UB = Inf;
				
				#planning_sol = solve_planning_problem(planning_problem,planning_variables,inputs);
				#if haskey(setup, "print_sols")
				    # for var in all_variables(planning_problem)
				    #     if value(var) > 0
				    #         println(var, "   ", value(var))
				    #     end
				    # end
				    # return nothing
				#end
				#set_integer.(planning_problem[:vCAP]) #APPENDED after
				set_integer.(integer_variables)
				set_binary.(binary_variables)
				planning_sol = solve_planning_problem(planning_problem,planning_variables,inputs);
				LB = planning_sol.LB;
				planning_sol_best = deepcopy(planning_sol);
				integer_routine_flag = false;
				#return (planning_problem=planning_problem,planning_sol = planning_sol_best,operational_sol = subop_sol,LB_hist = LB_hist,UB_hist = UB_hist,cpu_time = cpu_time,feasibility_hist = feasibility_hist, build_decisions = build_decisions)
			elseif warmstart_bilinear_routine
				println()
				println()
				println()
				println()
				println()
				println("RUNNING BILINEAR WARMSTART ROUTINE")
				println()
				println()
				println()
				println()
				println()

				println("BEST SOLUTIONS OF THE WATERFLOW MODEL ARE: ")

				for k in keys(planning_sol_best.values)
					if planning_sol_best.values[k] != 0
						println(k, "    ", planning_sol_best.values[k])
					end
				end

				# go through the bilinear problem and remove slacks and add bilinear variables
				p_id = workers();
    			np_id = length(p_id);
				t = @elapsed begin
    			@sync for k in 1:np_id
    			    @async @fetchfrom p_id[k] reset_subproblem_vector_to_bilinear(localpart(subproblems), inputs) #solve_local_subproblem(localpart(EP_subproblems),planning_sol,inputs); ### This is equivalent to fetch(@spawnat p .....)
    			end
				end
				println("TIME TO RESET SUBPROBLEMS WAS ", t / 60, " MINUTES")
				solver_start_time[1] = solver_start_time[1] - t
				UB = Inf
				warmstart_bilinear_routine = false

				if post_warmstart_integer_routine
					println()
					println("WARMSTART INTEGER ROUTINE IS ON - RELAXING INTEGERS")
					println()
					unset_integer.(integer_variables)
					unset_binary.(binary_variables)
					set_upper_bound.(binary_variables, 1)
					set_lower_bound.(binary_variables, 0)
				else
					ConvTol = post_warmstart_ConvTol
				end
				planning_sol = solve_planning_problem(planning_problem,planning_variables,inputs);
				LB = planning_sol.LB;
				planning_sol_best = deepcopy(planning_sol);
				
				#stab_method = "off"

			elseif warmstart_linear_routine
				println()
				println()
				println()
				println()
				println()
				println("RUNNING LINEAR WARMSTART ROUTINE")
				println()
				println()
				println()
				println()
				println()

				println("BEST SOLUTIONS OF THE WATERFLOW MODEL ARE: ")

				for k in keys(planning_sol_best.values)
					if planning_sol_best.values[k] != 0
						println(k, "    ", planning_sol_best.values[k])
					end
				end

				# go through the bilinear problem and remove slacks and add bilinear variables
				p_id = workers();
    			np_id = length(p_id);
				t = @elapsed begin
    			@sync for k in 1:np_id
    			    @async @fetchfrom p_id[k] reset_subproblem_vector_to_linear(localpart(subproblems), inputs) #solve_local_subproblem(localpart(EP_subproblems),planning_sol,inputs); ### This is equivalent to fetch(@spawnat p .....)
    			end
				end
				println("TIME TO RESET SUBPROBLEMS WAS ", t / 60, " MINUTES")
				solver_start_time[1] = solver_start_time[1] - t
				UB = Inf
				warmstart_linear_routine = false
				if post_warmstart_integer_routine
					println()
					println("WARMSTART INTEGER ROUTINE IS ON - RELAXING INTEGERS")
					println()
					unset_integer.(integer_variables)
					unset_binary.(binary_variables)
					set_upper_bound.(binary_variables, 1)
					set_lower_bound.(binary_variables, 0)
				else 
					ConvTol = post_warmstart_ConvTol
				end
				#stab_method = "off"
				planning_sol = solve_planning_problem(planning_problem,planning_variables,inputs);
				LB = planning_sol.LB;
				planning_sol_best = deepcopy(planning_sol);
			elseif post_warmstart_integer_routine
				println()
				println()
				println()
				println()
				println()
				println("RESETTING BINARY/INTEGER CONSTRAINTS POST WARMSTART")
				println()
				println()
				println()
				println()
				println()
				set_integer.(integer_variables)
				set_binary.(binary_variables)
				LB = planning_sol.LB;
				post_warmstart_integer_routine = false;
				UB = Inf
				planning_sol = solve_planning_problem(planning_problem,planning_variables,inputs);
				LB = planning_sol.LB;
				planning_sol_best = deepcopy(planning_sol);
				ConvTol = post_warmstart_ConvTol
			else
				break
			end
		elseif (cpu_time[end] >= MaxCpuTime)|| (k == MaxIter)
			break
		elseif UB==Inf
			planning_sol = deepcopy(unst_planning_sol);
		else
			if stab_method == "int_level_set"
				start_stab_method = time()
				# if  integer_investment==1 && integer_routine_flag==false
				# 	unset_integer.(integer_variables)
				# 	unset_binary.(binary_variables)
				# 	for v in integer_variables
				# 		fix(v,unst_planning_sol.values[name(v)];force=true)
				# 	end
				# 	for v in binary_variables
				# 		fix(v,unst_planning_sol.values[name(v)];force=true)
				# 	end
                #     println("Solving the interior level set problem with γ = $γ")
				# 	planning_sol = solve_int_level_set_problem(planning_problem,planning_variables,unst_planning_sol,LB,UB,γ,inputs);
				# 	unfix.(integer_variables)
				# 	unfix.(binary_variables)
				# 	set_integer.(integer_variables)
				# 	set_binary.(binary_variables)
				# 	set_lower_bound.(integer_variables,0.0)
				# 	set_lower_bound.(binary_variables,0.0)
				# else
                    println("Solving the interior level set problem with γ = $γ")
					planning_sol = solve_int_level_set_problem(planning_problem,planning_variables,unst_planning_sol,LB,UB,γ,inputs);
				# end
				cpu_stab_method = time()-start_stab_method;
				println("Solving the interior level set problem required $cpu_stab_method seconds")
			else
				planning_sol = deepcopy(unst_planning_sol);
			end

		end

    end
    
    #build_indices = findall(x -> x > 0.5, build_decisions)
	#@info "Lines built: " build_indices
	#@info "Number of lines built: " length(build_indices)

	#@info "Theta: " Vector(value.(planning_problem[:vTHETA]))

	#cap_builds = findall(x -> x > 0.1, Vector(value.(planning_problem[:vCAP])))
	#@info "vCAP Builds: " cap_builds

	return (planning_problem=planning_problem,planning_sol = planning_sol_best,operational_sol = subop_sol,LB_hist = LB_hist,UB_hist = UB_hist,cpu_time = cpu_time,feasibility_hist = feasibility_hist)#, build_decisions = build_decisions)
end

function update_planning_problem_multi_cuts!(EP::Model,subop_sol::Dict,planning_sol::NamedTuple,planning_variables_sub::Dict)
    
	W = keys(subop_sol);

    @constraint(EP,[w in W],subop_sol[w].theta_coeff*EP[:vTHETA][w] >= subop_sol[w].cut_value + sum(subop_sol[w].lambda[i]*(variable_by_name(EP,planning_variables_sub[w][i]) - planning_sol.values[planning_variables_sub[w][i]]) for i in 1:length(planning_variables_sub[w])));
end

function update_planning_problem_aggregated_cuts!(EP::Model,subop_sol::Dict,planning_sol::NamedTuple,planning_variables_sub::Dict)
    
	W = keys(subop_sol);

    @constraint(EP,subop_sol[1].theta_coeff*EP[:vTHETA][1] >= sum(subop_sol[w].cut_value + sum(subop_sol[w].lambda[i]*(variable_by_name(EP,planning_variables_sub[w][i]) - planning_sol.values[planning_variables_sub[w][i]]) for i in 1:length(planning_variables_sub[w])) for w in W));
end