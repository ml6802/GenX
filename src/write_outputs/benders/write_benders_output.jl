function write_benders_output(LB_hist::Vector{Float64},UB_hist::Vector{Float64},cpu_time::Vector{Float64},feasibility_hist::Vector{Float64},outpath::AbstractString, setup::Dict,inputs::Dict,planning_problem::Model)
	println("Running with crossover on")
	set_attribute(planning_problem, "Crossover", 1)
	optimize!(planning_problem)
	
	dfConv = DataFrame(Iter = 1:length(LB_hist),CPU_Time = cpu_time, LB = LB_hist, UB  = UB_hist, Gap = (UB_hist.-LB_hist)./LB_hist,Feasibility=feasibility_hist)
	
	if !has_values(planning_problem)
		set_attribute(planning_problem, "Crossover", 1)
		optimize!(planning_problem)
	end
	
	#write_planning_solution(outpath, inputs, setup, planning_problem)
	
	elapsed_time_capacity = @elapsed dfCap = write_capacity(outpath, inputs, setup, planning_problem)
	println("Time elapsed for writing capacity is")
	println(elapsed_time_capacity)

	
	if inputs["Z"] > 1
		if setup["NetworkExpansion"] == 1
	            elapsed_time_expansion = @elapsed write_nw_expansion(outpath, inputs, setup, planning_problem)
	            println("Time elapsed for writing network expansion is")
	            println(elapsed_time_expansion)
	        end
    	end
	if setup["MinCapReq"] == 1 && has_duals(planning_problem) == 1
		elapsed_time_min_cap_req = @elapsed write_minimum_capacity_requirement(outpath,inputs,setup,planning_problem)
		println("Time elapsed for writing minimum capacity requirement is")
		println(elapsed_time_min_cap_req)
	end
	if setup["MaxCapReq"] == 1 && has_duals(planning_problem) == 1
		elapsed_time_max_cap_req = @elapsed write_maximum_capacity_requirement(outpath,inputs,setup,planning_problem)
		println("Time elapsed for writing maximum capacity requirement is")
		println(elapsed_time_max_cap_req)
	end
	
	write_planning_problem_costs(outpath,
	inputs,
	setup,
	planning_problem)
	CSV.write(joinpath(outpath, "benders_convergence.csv"),dfConv)
	YAML.write_file(joinpath(outpath, "run_settings.yml"),setup)
end


function gather_costs(master_sol::NamedTuple, subop_sol::Dict)
	investment_costs, zone_inv_cost = get_inv_cost(master_sol)
	annual_op_cost, zone_op_cost = get_op_cost(subop_sol)
	return (investment_costs=investment_costs,zone_inv_cost=zone_inv_cost, annual_op_cost=annual_op_cost, zone_op_cost=zone_op_cost)
end

function get_inv_cost(master_sol::NamedTuple)
	investment_costs = master_sol.inv_cost
	zone_inv_cost = zeros(length(master_sol.zone_inv_cost))
	for z in eachindex(zone_inv_cost)
		zone_inv_cost[z] = master_sol.zone_inv_cost[z]
	end
	return investment_costs,zone_inv_cost
end

function get_op_cost(subop_sol::Dict)
	ann_op_cost = sum(subop_sol[i].op_cost for i in keys(subop_sol))
	zone_op_cost = zeros(length(subop_sol[1].zone_cost.CTotal))
	for z in eachindex(zone_op_cost)
		zone_op_cost[z] = sum(subop_sol[i].zone_cost.COpTot[z] for i in keys(subop_sol))
	end
	return ann_op_cost,zone_op_cost
end

function gather_emissions(inputs_decomp::Dict,subop_sol::Dict)
	(Z,T) = size(subop_sol[1].emissions)
	zonal_ems = zeros(Z)
	for z in 1:Z
		zonal_ems[z] = sum(sum(inputs_decomp[k]["omega"].*subop_sol[k].emissions[z,:]) for k in eachindex(subop_sol))
	end
	total_ems = sum(zonal_ems)
	return total_ems, zonal_ems
end

function add_types(inputs::Dict, cap_mat)
	resource_type = inputs["RESOURCES"].resource_type
	type_vec=Vector{String}(undef,length(resource_type))
	for i in eachindex(resource_type)
		type_vec[i] = String(resource_type[i])
	end
	lines = Vector{String}(undef,0)
	for i in inputs["EXPANSION_LINES"]
		push!(lines,"Transmission")
	end
	type_vec = vcat(type_vec,lines)
	cap_mat[3,:] = reshape(type_vec,(1,:))
	return cap_mat
end

function summarize_type_capacities(inputs::Dict,cap_mat::AbstractArray,types)
	Resource = inputs["RESOURCES"].resource
	zones_r = inputs["RESOURCES"].zone
	Z = inputs["Z"]
	nlines = length(inputs["EXPANSION_LINES"])
	tech_types = unique(types)
	cap_vec = zeros((Z, length(tech_types)))
	(row,resource_n)=size(cap_mat)
	for i in 1:(resource_n-nlines)
		indx = findfirst(==(cap_mat[1,i]),Resource)
		
		zone = zones_r[indx]
		type = cap_mat[end,i]
		type_indx = findfirst(==(type),tech_types)
		cap_vec[zone,type_indx] += cap_mat[2,i]
	end
	tot_cap_by_type = sum(cap_vec[z,:] for z in 1:Z)
	cap_by_tz = reduce(hcat,cap_vec')
	summarize_cap = hcat(tot_cap_by_type',cap_by_tz)
	col_names = tech_types
	techs_by_zone = Array{String,2}(undef,(length(tech_types),Z))
	for z in 1:Z
		for i in eachindex(tech_types)
			techs_by_zone[i,z] = tech_types[i]*"Z"*string(z)
		end
	end
	col_names = vcat(col_names,reduce(vcat,techs_by_zone))
	dfSummary = DataFrame(summarize_cap,col_names)
	return dfSummary
end

function write_capacity_benders(inputs::Dict, master_sol::NamedTuple)
	# Capacity decisions
	resources = inputs["RESOURCES"].resource
	existing_cap_mw = inputs["RESOURCES"].existing_cap_mw
	lines = Vector{String}(undef,0)
	for i in inputs["EXPANSION_LINES"]
		push!(lines,"Line_"*string(i))
	end
	master_sol_df = DataFrame(key = collect(keys(master_sol.values)), vals = collect(master_sol.values[i] for i in collect(keys(master_sol.values))))
	sort!(master_sol_df,:key)
	capacity_names = vcat(resources,lines)
	cap_vec = [existing_cap_mw;zeros(length(lines))]
	counter = 0
	for i in eachindex(master_sol_df.key)
		name = split(master_sol_df.key[i], "[")
		if name[1] == "vCAP"
			num = split(name[2], "]")
			mult=1
			try 
				mult = inputs["RESOURCES"].cap_size
			catch
				mult = 1
			end
			cap_vec[parse(Int64,num[1])] += master_sol_df.vals[i]*mult
			counter +=1
		elseif name[1] == "vRETCAP"
			num = split(name[2], "]")
			mult=1
			try 
				mult = inputs["RESOURCES"].cap_size
			catch
				mult = 1
			end
			cap_vec[parse(Int64,num[1])] -= master_sol_df.vals[i]*mult
		end
	end
	for i in eachindex(master_sol_df.key)
		name = split(master_sol_df.key[i], "[")
		if name[1] == "vNEW_TRANS_CAP"
			num = split(name[2], "]")
			cap_vec[counter+parse(Int64,num[1])] = master_sol_df.vals[i]
		end
	end
	cap_mat = Array{Union{String,Float64},2}(undef,(3,length(capacity_names)))
	cap_mat[1,:] = reshape(capacity_names,(1,:))
	cap_mat[2,:] = cap_vec'
	cap_mat = add_types(inputs,cap_mat)
	df_summary = summarize_type_capacities(inputs, cap_mat, cap_mat[3,:])
	return df_summary
end

function add_zone_costs!(costs::NamedTuple, dfResults::DataFrame)
	for k in eachindex(costs.zone_inv_cost)
		zone = "Zone"*string(k)*"_TotalCost"
		dfResults[!,Symbol(zone)] .= costs.zone_inv_cost[k] + costs.zone_op_cost[k]
	end
end

function add_zone_ems!(zonal_ems::Vector, dfResults::DataFrame)
	for k in eachindex(zonal_ems)
		zone = "Zone"*string(k)*"_TotalEmissions"
		dfResults[!,Symbol(zone)] .= zonal_ems[k]
	end
end

function make_benders_results_df(master_sol::NamedTuple, subop_sol::Dict, path::AbstractString, setup::Dict, inputs::Dict, inputs_decomp::Dict)
	ModelScalingFactor = 10^3
	dfResults = write_capacity_benders(inputs, master_sol)
	dfResults = dfResults.*ModelScalingFactor
	
	costs = gather_costs(master_sol, subop_sol)
	dfResults[!,:FixedCost] .= costs.investment_costs*ModelScalingFactor^2
	dfResults[!,:OpCost] .= costs.annual_op_cost*ModelScalingFactor^2
	dfResults[!,:TotalCost] .= dfResults.FixedCost[1]+dfResults.OpCost[1]
	add_zone_costs!(costs, dfResults)
	total_ems, zonal_ems = gather_emissions(inputs_decomp,subop_sol)
	dfResults[!,:TotalEmissions] .= total_ems*ModelScalingFactor
	add_zone_ems!(zonal_ems.*ModelScalingFactor, dfResults)
	return dfResults
end

function write_benders_mga_results!(Results_df::DataFrame, results::AbstractArray, path::AbstractString, setup::Dict, inputs::Dict, inputs_decomp::Dict, sumtime_df::DataFrame)
	num_its = 2*setup["ModelingToGenerateAlternativeIterations"]-1
	for i in 1:num_its
		temp_df = make_benders_results_df(results[i,1],results[i,2],path,setup,inputs,inputs_decomp)
		append!(Results_df,temp_df)
	end
	iterations = collect(0:num_its)
	Results_df[!,:MGAIteration] .= iterations
	println(Results_df)
	outpath = joinpath(path,"Outputs")
	if setup["OverwriteResults"] == 1
		# Overwrite existing results if dir exists
		# This is the default behaviour when there is no flag, to avoid breaking existing code
		if !(isdir(outpath))
		mkdir(outpath)
		end
	else
		# Find closest unused ouput directory name and create it
		path = choose_output_dir(outpath)
		mkdir(path)
	end
    CSV.write(joinpath(outpath, "SummaryMGA.csv"),Results_df)
    CSV.write(joinpath(outpath, "SummaryMGATimes.csv"),sumtime_df)
end

function splitfun(x)
	return String(split(x,"[")[1])
end

function make_benders_zonal_invcost(inputs::Dict,EP::Model)
	Resources = inputs["RESOURCES"]
	Z = inputs["Z"]     # Number of zones
	ModelScalingFactor = 10^3

	CFix = zeros(Z)

	for z in 1:Z
		tempCFix = 0.0

		Y_ZONE = Resources.id[Resources.zone .== 1]
		STOR_ALL_ZONE = intersect(inputs["STOR_ALL"], Y_ZONE)
		STOR_ASYMMETRIC_ZONE = intersect(inputs["STOR_ASYMMETRIC"], Y_ZONE)

		eCFix = sum(value.(EP[:eCFix][Y_ZONE]))
		tempCFix += eCFix

		if !isempty(STOR_ALL_ZONE)
			eCFixEnergy = sum(value.(EP[:eCFixEnergy][STOR_ALL_ZONE]))
			tempCFix += eCFixEnergy
		end
		if !isempty(STOR_ASYMMETRIC_ZONE)
			eCFixCharge = sum(value.(EP[:eCFixCharge][STOR_ASYMMETRIC_ZONE]))
			tempCFix += eCFixCharge
		end

		tempCFix *= ModelScalingFactor^2
		CFix[z] = tempCFix
	end
	return CFix
end

function make_benders_zonal_opcost(inputs::Dict,EP::Model)
	Resources = inputs["RESOURCES"]
	SEG = inputs["SEG"]  # Number of lines
	Z = inputs["Z"]     # Number of zones
	T = inputs["T"]     # Number of time steps (hours)
	ModelScalingFactor = 10^3
	CTotal = zeros(Z)
	CFix = zeros(Z)
	CVar = zeros(Z)
	CStart = zeros(Z)
	CNSE = zeros(Z)
	COpTot = zeros(Z)
	for z in 1:Z
		tempCTotal = 0.0
		tempCFix = 0.0
		tempCVar = 0.0
		tempCStart = 0.0
		tempCNSE = 0.0

		Y_ZONE = Resources.id[Resources.zone .== 1]
		STOR_ALL_ZONE = intersect(inputs["STOR_ALL"], Y_ZONE)
		STOR_ASYMMETRIC_ZONE = intersect(inputs["STOR_ASYMMETRIC"], Y_ZONE)
		FLEX_ZONE = intersect(inputs["FLEX"], Y_ZONE)
		COMMIT_ZONE = intersect(inputs["COMMIT"], Y_ZONE)

		eCFix = 0#sum(value.(EP[:eCFix][Y_ZONE]))
		tempCFix += eCFix
		tempCTotal += eCFix

		tempCVar = sum(value.(EP[:eCVar_out][Y_ZONE,:]))
		tempCTotal += tempCVar

		if !isempty(STOR_ALL_ZONE)
			eCVar_in = sum(value.(EP[:eCVar_in][STOR_ALL_ZONE,:]))
			tempCVar += eCVar_in
			eCFixEnergy = 0#um(value.(EP[:eCFixEnergy][STOR_ALL_ZONE]))
			tempCFix += eCFixEnergy

			tempCTotal += eCVar_in + eCFixEnergy
		end
		if !isempty(STOR_ASYMMETRIC_ZONE)
			eCFixCharge = 0#sum(value.(EP[:eCFixCharge][STOR_ASYMMETRIC_ZONE]))
			tempCFix += eCFixCharge
			tempCTotal += eCFixCharge
		end
		if !isempty(FLEX_ZONE)
			eCVarFlex_in = sum(value.(EP[:eCVarFlex_in][FLEX_ZONE,:]))
			tempCVar += eCVarFlex_in
			tempCTotal += eCVarFlex_in
		end

		#if setup["UCommit"] >= 1
			eCStart = sum(value.(EP[:eCStart][COMMIT_ZONE,:]))
			tempCStart += eCStart
			tempCTotal += eCStart
		#end

		tempCNSE = sum(value.(EP[:eCNSE][:,:,z]))
		tempCTotal += tempCNSE

		tempCTotal *= ModelScalingFactor^2
		tempCFix *= ModelScalingFactor^2
		tempCVar *= ModelScalingFactor^2
		tempCNSE *= ModelScalingFactor^2
		tempCStart *= ModelScalingFactor^2

		CTotal[z] = tempCTotal
		CFix[z] = tempCFix
		CVar[z] = tempCVar
		CStart[z] = tempCStart
		CNSE[z] = tempCNSE
		COpTot[z] = CVar[z] + CStart[z] + CNSE[z]
	end
	return (CTotal = CTotal, CFix = CFix, CVar = CVar, CNSE = CNSE, CStart = CStart, COpTot =COpTot)
end
