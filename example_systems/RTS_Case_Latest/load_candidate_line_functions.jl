function load_candidates_base(myinputs, T=168; demand_scale = 2)
    # myinputs["pTrans_Max"] .*= 2
    #myinputs["pD"] .*= 1
    # myinputs["Voll"] .*= 10
    myinputs["pTrans_Max"] .*= 1
    #myinputs["pTrans_Max"][[5,23,24,70,75]] .*= 1/70
    L = myinputs["L"]
    L_exist = L
    L_cand = L
    myinputs["L_cand"] = L_cand
    myinputs["L_exist"] = L_exist
    myinputs["L"] = L * 2
    myinputs["Z_cand"] = myinputs["Z"]
    myinputs["pNet_Map"] = vcat(myinputs["pNet_Map"], myinputs["pNet_Map"])
    myinputs["pDC_OPF_coeff"] = vcat(myinputs["pDC_OPF_coeff"], myinputs["pDC_OPF_coeff"])
    myinputs["Line_Angle_Limit"] = [6.282 for i in 1:myinputs["L"]]
    myinputs["Line_Reinforcement_Cap_Size"] = vcat([0 for i in 1:L_exist], [i for i in myinputs["pTrans_Max"]])
    myinputs["Max_Trans_Cap"] = vcat([0 for i in 1:L_exist], [1 for i in myinputs["pTrans_Max"]])
    myinputs["pTrans_Max"] = vcat([i for i in myinputs["pTrans_Max"]], [0 for i in 1:L_cand])



    EXPANSION_LEVELS = Dict{Int, Vector}()
    for i in (L_exist + 1):(L_exist + L_cand)
        EXPANSION_LEVELS[i] = (0:1:myinputs["Max_Trans_Cap"][i])
    end
    EXPANSION_LINES = [i for i in (L_exist + 1):(L_exist + L_cand)]
    myinputs["EXPANSION_LINES"] = EXPANSION_LINES
    myinputs["CANDIDATE_LINES"] = copy(EXPANSION_LINES)
    myinputs["EXISTING_LINES"] = [i for i in 1:L_exist]
    myinputs["pPercent_Loss"] = vcat(myinputs["pPercent_Loss"], myinputs["pPercent_Loss"])

    lines = collect(get_technologies(TransmissionTechnology, p));
    myinputs["pC_Line_Reinforcement"] = zeros(myinputs["L"])
    myinputs["pC_Line_Reconductor_High"] = zeros(myinputs["L"])
    myinputs["pC_Line_Reconductor_Low"] = zeros(myinputs["L"])

    scale_factor = mysetup["ParameterScale"] == 1 ? GenX.ModelScalingFactor : 1

    CAN_RETIRE_LINES = Int[]
    CANNOT_RETIRE_LINES = Int[]
    RECONDUCTOR_LINES = Int[]
    existing_to_cand_map = Dict()

    Random.seed!(1)
    for i in 1:length(lines)
        #check for reconductoring; 

        distance = 60 * rand()
        cap_val = distance * 1200
        cost = cap_val * (0.044) / (1 - (1 + 0.044)^(-60))
        myinputs["pC_Line_Reinforcement"][i + L_exist] = cost

        if get_existing_capacity_mw(p, lines[i]) > 200
            push!(CANNOT_RETIRE_LINES, i)
            push!(RECONDUCTOR_LINES, i)
            myinputs["pC_Line_Reconductor_Low"][i] = cost .* 0.3
            myinputs["pC_Line_Reconductor_High"][i] = cost .* 0.7
            myinputs["Line_Reinforcement_Cap_Size"][L_exist + i] *= 1.5
            myinputs["pDC_OPF_coeff"][L_exist + i] *= 1.5
        else
            push!(CAN_RETIRE_LINES, i)
            existing_to_cand_map[i] = L_exist + i
            myinputs["Line_Reinforcement_Cap_Size"][L_exist + i] *= 2.5
            #myinputs["pDC_OPF_coeff"][L_exist + i] *= 2.5
        end
    end

    #myinputs["pDC_OPF_coeff"] .*= 2000 #2000
    # myinputs["pDC_OPF_coeff"] .*= 100 #2000

    myinputs["CAN_RETIRE_LINES"] = CAN_RETIRE_LINES
    myinputs["CANNOT_RETIRE_LINES"] = CANNOT_RETIRE_LINES
    myinputs["RECONDUCTOR_LINES"] = RECONDUCTOR_LINES
    myinputs["existing_to_cand_map"] = existing_to_cand_map

    myinputs["hours_per_subperiod"] = T
    myinputs["INTERIOR_SUBPERIODS"] = [i for i in 2:myinputs["hours_per_subperiod"]]
    myinputs["T"] = T
    myinputs["pD"] .*= demand_scale
end

function load_no_candidates(myinputs, T=168; demand_scale = 2)
    # myinputs["pTrans_Max"] .*= 2
    #myinputs["pD"] .*= 1
    # myinputs["Voll"] .*= 10
    myinputs["pTrans_Max"] .*= 1
    #myinputs["pTrans_Max"][[5,23,24,70,75]] .*= 1/70
    L = myinputs["L"]
    L_exist = L
    #L_cand = L
    myinputs["L_cand"] = 0
    myinputs["L_exist"] = L_exist
    myinputs["L"] = L_exist
    myinputs["Z_cand"] = myinputs["Z"]
    myinputs["pNet_Map"] = vcat(myinputs["pNet_Map"])
    myinputs["pDC_OPF_coeff"] = vcat(myinputs["pDC_OPF_coeff"])
    myinputs["Line_Angle_Limit"] = [6.282 for i in 1:myinputs["L"]]
    myinputs["Line_Reinforcement_Cap_Size"] = vcat([0 for i in 1:L_exist], [i for i in myinputs["pTrans_Max"]])
    myinputs["Max_Trans_Cap"] = vcat([0 for i in 1:L_exist], [1 for i in myinputs["pTrans_Max"]])
    L_cand = 0
    myinputs["pTrans_Max"] = vcat([i for i in myinputs["pTrans_Max"]], [0 for i in 1:L_cand])



    EXPANSION_LEVELS = Dict{Int, Vector}()
    for i in (L_exist + 1):(L_exist + L_cand)
        EXPANSION_LEVELS[i] = (0:1:myinputs["Max_Trans_Cap"][i])
    end
    EXPANSION_LINES = [i for i in (L_exist + 1):(L_exist + L_cand)]
    myinputs["EXPANSION_LINES"] = EXPANSION_LINES
    myinputs["CANDIDATE_LINES"] = []
    myinputs["EXISTING_LINES"] = [i for i in 1:L_exist]
    myinputs["pPercent_Loss"] = vcat(myinputs["pPercent_Loss"])

    lines = collect(get_technologies(TransmissionTechnology, p));
    myinputs["pC_Line_Reinforcement"] = zeros(myinputs["L"])
    myinputs["pC_Line_Reconductor_High"] = zeros(myinputs["L"])
    myinputs["pC_Line_Reconductor_Low"] = zeros(myinputs["L"])

    scale_factor = mysetup["ParameterScale"] == 1 ? GenX.ModelScalingFactor : 1

    CAN_RETIRE_LINES = Int[]
    CANNOT_RETIRE_LINES = Int[]
    RECONDUCTOR_LINES = Int[]
    existing_to_cand_map = Dict()

        #myinputs["pDC_OPF_coeff"] .*= 2000 #2000
    # myinputs["pDC_OPF_coeff"] .*= 100 #2000

    myinputs["CAN_RETIRE_LINES"] = CAN_RETIRE_LINES
    myinputs["CANNOT_RETIRE_LINES"] = CANNOT_RETIRE_LINES
    myinputs["RECONDUCTOR_LINES"] = RECONDUCTOR_LINES
    myinputs["existing_to_cand_map"] = existing_to_cand_map

    myinputs["hours_per_subperiod"] = T
    myinputs["INTERIOR_SUBPERIODS"] = [i for i in 2:myinputs["hours_per_subperiod"]]
    myinputs["T"] = T
    myinputs["pD"] .*= demand_scale
end

vom_dict = Dict("CC" => 2.12, "CT" => 6.94, "STEAM" => 9.18, "NUCLEAR" => 2.8, "PV" => 0, "CSP" => 3.8, "WIND" => 0)

#fom_dict = Dict("CC" => 33500, "CT" => 33500, "STEAM" => 33500, "NUCLEAR" => 175000, "PV" => 22000, "CSP" => 74000, "WIND" => 31000)
fom_dict = Dict("CC" => 33500, "CT" => 26000, "STEAM" => 33500, "NUCLEAR" => 175000, "PV" => 22000, "CSP" => 74000, "WIND" => 31000)

function add_om_costs(p)
    techs = collect(get_technologies(ResourceTechnology, p))

    for t in techs
        if isa(t, StorageTechnology)
            continue
        end
        op_cost = t.operation_costs.variable

        key_val = [""]
        for key in keys(vom_dict)
            if occursin(key, t.name)
                key_val[1] = key
                break
            end
        end
        if key_val[1] == ""
            error("Technology of name $(t.name) does not have a corresponding dictionary pairing")
        end
        vom_val = vom_dict[key_val[1]]
        fom_val = fom_dict[key_val[1]]
        if isa(op_cost, CostCurve)
            new_cc = CostCurve(LinearCurve(LinearFunctionData(0, fom_val)), op_cost.power_units, LinearCurve(LinearFunctionData(vom_val, 0)))
            t.operation_costs.variable = new_cc
        elseif isa(op_cost, FuelCurve)
            new_fc = FuelCurve(op_cost.value_curve, op_cost.power_units, op_cost.fuel_cost, op_cost.startup_fuel_offtake, LinearCurve(LinearFunctionData(vom_val, 0)))
            t.operation_costs.variable = new_fc
            t.operation_costs.fixed = fom_val
        else
            error("Variable Costs are of type , ", typeof(op_cost))
        end
    end
end

# for t in techs
#     if has_time_series(t) && !(has_supplemental_attributes(t))
#         tkeys = get_time_series_keys(t)
#         vom_key = [""]
#         for k in tkeys
#             if occursin("fom", k.name) || occursin("ixed", k.name)
#             # if occursin("vom", k.name) || occursin("Var", k.name)
#                 vom_key[1] = k.name
#                 break
#             end
#         end
#         if vom_key[1] == ""
#             println()
#             println()
#             println(t.name, "    ", length(tkeys), "   ", tkeys)
#             println()
#             println()
            
#         else
#             tvalues = get_time_series_values(SingleTimeSeries, t, vom_key[1])
#             vom_val = tvalues[16]
#             println(t.name, "   ", vom_val)
#             if vom_val == 0
#                 println("ZERO VALUE FOR ", t.name)
#             end
#             push!(voms, vom_val)
#         end
        
#     end
# end
