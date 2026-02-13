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

	return planning_problem
end


#####==================================================####
# Benders Operational Attribute Gathering Functions
#####==================================================####

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

function breakout_costs(master_sol::NamedTuple, subop_sol::Dict)
	list_of_costs = ["CTotal","CFix","CVar","CFuel","CStart","CNetworkExp","CNSE", "COpTot"]
	list_of_zones = ["_" * string(x) for x in 1:length(subop_sol[1].zone_cost.CTotal)]
	cost_mat = Array{Float64,2}(undef,(length(list_of_costs),length(list_of_zones)))
	names = Array{String,2}(undef,(length(list_of_costs),length(list_of_zones)))
	for (j, zone) in enumerate(list_of_zones)
		for (i, cost_name) in enumerate(list_of_costs)
			if cost_name == "CFix"
				cost_mat[i,j] = master_sol.zone_inv_cost[j]
			elseif cost_name == "CNetworkExp"
				cost_mat[i,j] = 0.0
			elseif cost_name == "CTotal"
				cost_mat[i,j] = sum(subop_sol[k].zone_cost.CTotal[j] for k in keys(subop_sol)) + master_sol.zone_inv_cost[j]
			else
				cost_mat[i,j] = sum(subop_sol[k].zone_cost[Symbol(cost_name)][j] for k in keys(subop_sol))
			end
			names[i,j] = cost_name * zone
		end
	end
	total_costs = construct_total_costs(cost_mat, master_sol)
	flat_mat = reshape(cost_mat, (length(list_of_costs)*length(list_of_zones),))
	costs = vcat(total_costs, flat_mat)
	names = reshape(names, (length(list_of_costs)*length(list_of_zones),))
	complete_names = vcat(list_of_costs, names)
	dfCosts = DataFrame(costs', complete_names)
	return dfCosts
end

function construct_total_costs(cost_mat, master_sol)
	total_costs = zeros(size(cost_mat,1))
	for i in 1:size(cost_mat,1)
		total_costs[i] = sum(cost_mat[i,j] for j in 1:size(cost_mat,2))
	end
	total_costs[6] = master_sol.net_exp_cost*ModelScalingFactor^2
	total_costs[1] += master_sol.net_exp_cost*ModelScalingFactor^2
	return total_costs
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

function make_power_df(inputs::Dict, inputs_decomp::Dict,subop_sol::Dict, setup::Dict)
	power = Array{Float64,2}(undef,(0,inputs["G"]))

	for k in eachindex(subop_sol)
		temp_power = subop_sol[k].power'; 
		power = vcat(power,temp_power)
	end
	

	ModelScalingFactor = 10^3

	if setup["ParameterScale"] == 1
		power *= ModelScalingFactor
	end

	weighted_power = power .* inputs["omega"]
	AnnualSum = sum(weighted_power[i,:] for i in 1:size(weighted_power,1)) # Weighted for annual sum
	dfPower = DataFrame(AnnualSum', inputs["RESOURCE_NAMES"])
	
	dfPower_full = DataFrame(power, inputs["RESOURCE_NAMES"]) # Raw for full time series
	return dfPower, dfPower_full

end

function make_charge_df(inputs::Dict, subop_sol::Dict, setup::Dict)
	gen = inputs["RESOURCES"]
	G = inputs["G"]     # Number of resources (generators, storage, DR, and DERs)
	zones = zone_id.(gen)
	charge = Array{Float64,2}(undef,(0,G))


	for k in eachindex(subop_sol)
		temp_charge = subop_sol[k].charge';
		charge = vcat(charge,temp_charge)
	end

	ModelScalingFactor = 10^3

	if setup["ParameterScale"] == 1
		charge *= ModelScalingFactor
	end

	dfCharge = DataFrame(charge, inputs["RESOURCE_NAMES"])
	return dfCharge

end


function get_zonal_nse(inputs::Dict, inputs_decomp::Dict, subop_sol::Dict)
	T = inputs["T"]     # Number of time steps
    Z = inputs["Z"]     # Number of zones
    SEG = inputs["SEG"] # Number of demand curtailment segments
	divs = length(keys(subop_sol))
	l_subperiod = T/divs

	nse = zeros(SEG * Z, T)
    scale_factor = 10^3

	for k in eachindex(subop_sol)
		for z in 1:Z
        	nse[((z - 1) * SEG + 1):(z * SEG), Int((k-1)*l_subperiod+1):Int(k*l_subperiod)] = subop_sol[k].nse[:, :, z] * scale_factor
    	end
	end
	annual_sum = zeros(SEG * Z)
    annual_sum .= nse * inputs["omega"]
	names = ["Zone_$(z)_Seg_$(s)" for z in 1:Z for s in 1:SEG]
	df_nse = DataFrame(annual_sum', names)
	df_nse.Total = [sum(annual_sum)]
	
	return df_nse
end

function get_trans_flows(inputs::Dict, inputs_decomp::Dict, subop_sol::Dict)
	ModelScalingFactor = 10^3
	# Transmission related values
    T = inputs["T"]     # Number of time steps (hours)
    L = inputs["L"]     # Number of transmission lines
    # Power flows on transmission lines at each time step
    
	flow = Array{Float64,2}(undef,(0,L))
	for k in eachindex(subop_sol)
		temp_flow = subop_sol[k].flow';
		flow = vcat(flow,temp_flow)
	end

	weighted_flow = flow .* inputs["omega"]
	annual_flow = sum(weighted_flow[i,:] for i in 1:size(weighted_flow,1))* ModelScalingFactor
	names = "Line_" .* string.(1:L)
	dfFlow = DataFrame(annual_flow', names)

	dfFlow_full = DataFrame(flow, names) # Raw for full time series

    return dfFlow, dfFlow_full
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

#####=================================================####
# Benders Capacity Writing Functions
#####=================================================####

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
			if parse(Int64,num[1]) in inputs["COMMIT"]
				mult = cap_size(inputs["RESOURCES"][parse(Int64,num[1])])
			end
			cap_vec[parse(Int64,num[1])] += master_sol_df.vals[i]*mult
		elseif name[1] == "vRETCAP"
			num = split(name[2], "]")
			mult=1
			if parse(Int64,num[1]) in inputs["COMMIT"]
				mult = cap_size(inputs["RESOURCES"][parse(Int64,num[1])])
			end
			cap_vec[parse(Int64,num[1])] -= master_sol_df.vals[i]*mult
		end
	end
	for i in eachindex(master_sol_df.key)
		name = split(master_sol_df.key[i], "[")
		if name[1] == "vNEW_TRANS_CAP"
			num = split(name[2], "]")
			cap_vec[length(resources)+parse(Int64,num[1])] = master_sol_df.vals[i]
		end
	end
	df_summary = DataFrame(cap_vec', capacity_names)
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


####==================================================####
# Benders Results Compilation Functions
####==================================================####

function make_benders_results_df(master_sol::NamedTuple, subop_sol::Dict, path::AbstractString, setup::Dict, inputs::Dict, inputs_decomp::Dict)
	ModelScalingFactor = 10^3
	dfResults = write_capacity_benders(inputs, master_sol)
	dfResults = dfResults.*ModelScalingFactor
	
	costs = gather_costs(master_sol, subop_sol)
	dfResults[!,:FixedCost] .= costs.investment_costs*ModelScalingFactor^2
	dfResults[!,:OpCost] .= costs.annual_op_cost*ModelScalingFactor^2
	dfResults[!,:TotalCost] .= dfResults.FixedCost[1]+dfResults.OpCost[1]

	dfCosts = breakout_costs(master_sol, subop_sol)
	dfNse = get_zonal_nse(inputs, inputs_decomp, subop_sol)
	dfFlow, dfFlow_full = get_trans_flows(inputs, inputs_decomp, subop_sol)

	add_zone_costs!(costs, dfResults)
	total_ems, zonal_ems = gather_emissions(inputs_decomp,subop_sol)
	dfResults[!,:TotalEmissions] .= total_ems*ModelScalingFactor
	add_zone_ems!(zonal_ems.*ModelScalingFactor, dfResults)
	return dfResults, dfCosts, dfNse, dfFlow, dfFlow_full
end

function write_benders_mga_results!(Results_df::DataFrame, Costs_df::DataFrame, NSE_df::DataFrame, flow_df::DataFrame, power_df::DataFrame, results::AbstractArray, path::AbstractString, setup::Dict, inputs::Dict, inputs_decomp::Dict, sumtime_df::DataFrame)
	num_its = 2*setup["ModelingToGenerateAlternativeIterations"]
	full_power = Vector{DataFrame}(undef,num_its)
	full_charge = Vector{DataFrame}(undef,num_its)
	full_flow = Vector{DataFrame}(undef,num_its)

	for i in 1:num_its
		temp_df, temp_costs, temp_nse, temp_flow, temp_flow_full = make_benders_results_df(results[i,1],results[i,2],path,setup,inputs,inputs_decomp)
		temp_power_df, temp_power_full_df = make_power_df(inputs,inputs_decomp,results[i,2], setup)
		temp_charge_df = make_charge_df(inputs,results[i,2], setup)
		append!(Results_df,temp_df)
		append!(Costs_df,temp_costs)
		append!(NSE_df,temp_nse)
		append!(flow_df,temp_flow)
		append!(power_df,temp_power_df)
		
		full_power[i] = temp_power_full_df
		full_charge[i] = temp_charge_df
		full_flow[i] = temp_flow_full
			
	end
	iterations = collect(0:num_its)
	Results_df[!,:MGAIteration] .= iterations
	Costs_df[!,:MGAIteration] .= iterations
	NSE_df[!,:MGAIteration] .= iterations
	flow_df[!,:MGAIteration] .= iterations
	power_df[!,:MGAIteration] .= iterations
	
	outpath = joinpath(path, "Outputs")
    CSV.write(joinpath(outpath, "SummaryMGA.csv"),Results_df)
    CSV.write(joinpath(outpath, "SummaryMGATimes.csv"),sumtime_df)
	CSV.write(joinpath(outpath, "AnnualPowerByGen.csv"),power_df)
	CSV.write(joinpath(outpath, "FullCostsMGA.csv"),Costs_df)
	CSV.write(joinpath(outpath, "ZonalNSEMGA.csv"),NSE_df)
	CSV.write(joinpath(outpath, "AnnualTransmissionFlowsMGA.csv"),flow_df)

	### Write full time series outputs for each MGA iteration
	
	for i in 1:num_its
		CSV.write(joinpath(outpath, "PowerTimeSeries", "Power_MGAIteration_"*string(i)*".csv"), full_power[i])
		CSV.write(joinpath(outpath, "ChargeTimeSeries", "Charge_MGAIteration_"*string(i)*".csv"), full_charge[i])
		CSV.write(joinpath(outpath, "FlowTimeSeries", "Flow_MGAIteration_"*string(i)*".csv"), full_flow[i])
	end

	return
end

function splitfun(x)
	return String(split(x,"[")[1])
end

####==================================================####
# Benders Extraction Functions
####==================================================####


function make_benders_zonal_invcost(inputs::Dict,EP::Model)
	Resources = inputs["RESOURCES"]
	Z = inputs["Z"]     # Number of zones
	ModelScalingFactor = 10^3

	CFix = zeros(Z)

	for z in 1:Z
		tempCFix = 0.0

		Y_ZONE = Resources.id[Resources.zone .== z]
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
	VRE_STOR = inputs["VRE_STOR"]
	ModelScalingFactor = 10^3
	CTotal = zeros(Z)
	CFix = zeros(Z)
	CVar = zeros(Z)
	CStart = zeros(Z)
	CNSE = zeros(Z)
	CFuel = zeros(Z)
	COpTot = zeros(Z)
	for z in 1:Z
		tempCTotal = 0.0
		tempCFix = 0.0
		tempCVar = 0.0
		tempCFuel = 0.0
		tempCStart = 0.0
		tempCNSE = 0.0

		Y_ZONE = resources_in_zone_by_rid(Resources, z) #Resources.id[Resources.zone .== z]
		STOR_ALL_ZONE = intersect(inputs["STOR_ALL"], Y_ZONE)
		STOR_ASYMMETRIC_ZONE = intersect(inputs["STOR_ASYMMETRIC"], Y_ZONE)
		FLEX_ZONE = intersect(inputs["FLEX"], Y_ZONE)
		COMMIT_ZONE = intersect(inputs["COMMIT"], Y_ZONE)

		eCFix = 0#sum(value.(EP[:eCFix][Y_ZONE]))
		tempCFix += eCFix
		tempCTotal += eCFix

		tempCVar = sum(value.(EP[:eCVar_out][Y_ZONE,:]))
		tempCTotal += tempCVar

		tempCFuel = sum(value.(EP[:ePlantCFuelOut][Y_ZONE, :]))
        tempCTotal += tempCFuel

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
			eCStart = sum(value.(EP[:eCStart][COMMIT_ZONE,:])) +
                      sum(value.(EP[:ePlantCFuelStart][COMMIT_ZONE, :]))
			tempCStart += eCStart
			tempCTotal += eCStart
		#end

		if !isempty(VRE_STOR)
			gen_VRE_STOR = Resources.VreStorage
            Y_ZONE_VRE_STOR = resources_in_zone_by_rid(gen_VRE_STOR, z)
			eCVar_VRE_STOR = 0.0
            if !isempty(SOLAR_ZONE_VRE_STOR)
                eCVar_VRE_STOR += sum(value.(EP[:eCVarOutSolar][SOLAR_ZONE_VRE_STOR, :]))
            end
            if !isempty(WIND_ZONE_VRE_STOR)
                eCVar_VRE_STOR += sum(value.(EP[:eCVarOutWind][WIND_ZONE_VRE_STOR, :]))
            end
            if !isempty(STOR_ALL_ZONE_VRE_STOR)
                vom_map = Dict(DC_CHARGE_ALL_ZONE_VRE_STOR => :eCVar_Charge_DC,
                    DC_DISCHARGE_ALL_ZONE_VRE_STOR => :eCVar_Discharge_DC,
                    AC_DISCHARGE_ALL_ZONE_VRE_STOR => :eCVar_Discharge_AC,
                    AC_CHARGE_ALL_ZONE_VRE_STOR => :eCVar_Charge_AC)
                for (set, symbol) in vom_map
                    if !isempty(set)
                        eCVar_VRE_STOR += sum(value.(EP[symbol][set, :]))
                    end
                end
            end
            tempCVar += eCVar_VRE_STOR

            # Total Added Costs
            tempCTotal += (eCFix_VRE_STOR + eCVar_VRE_STOR)
		end

		tempCNSE = sum(value.(EP[:eCNSE][:,:,z]))
		tempCTotal += tempCNSE

		tempCTotal *= ModelScalingFactor^2
		tempCFix *= ModelScalingFactor^2
		tempCVar *= ModelScalingFactor^2
		tempCFuel *= ModelScalingFactor^2
		tempCNSE *= ModelScalingFactor^2
		tempCStart *= ModelScalingFactor^2

		CTotal[z] = tempCTotal
		CFix[z] = tempCFix
		CVar[z] = tempCVar
		CFuel[z] = tempCFuel
		CStart[z] = tempCStart
		CNSE[z] = tempCNSE
		COpTot[z] = CVar[z] + CStart[z] + CNSE[z] + CFuel[z]
	end
	return (CTotal = CTotal, CFix = CFix, CVar = CVar, CFuel = CFuel, CNSE = CNSE, CStart = CStart, COpTot =COpTot)
end

function make_charge_outputs(inputs::Dict, EP::Model)
	gen = inputs["RESOURCES"]
    zones = zone_id.(gen)

    G = inputs["G"]     # Number of resources (generators, storage, DR, and DERs)
    T = inputs["hours_per_subperiod"]    # Number of time steps per subperiod(hours)
    STOR_ALL = inputs["STOR_ALL"]
    FLEX = inputs["FLEX"]
    ELECTROLYZER = inputs["ELECTROLYZER"]
    VRE_STOR = inputs["VRE_STOR"]
    VS_STOR = !isempty(VRE_STOR) ? inputs["VS_STOR"] : []

    # Power withdrawn to charge each resource in each time step
    charge = zeros(G, T)

    if !isempty(STOR_ALL)
        charge[STOR_ALL, :] = value.(EP[:vCHARGE][STOR_ALL, :])
    end
    if !isempty(FLEX)
        charge[FLEX, :] = value.(EP[:vCHARGE_FLEX][FLEX, :])
    end
    if !isempty(ELECTROLYZER)
        charge[ELECTROLYZER, :] = value.(EP[:vUSE][ELECTROLYZER, :])	
    end
    if !isempty(VS_STOR)
        charge[VS_STOR, :] = value.(EP[:vCHARGE_VRE_STOR][VS_STOR, :])
    end

	return charge

end