function write_nw_expansion(path::AbstractString, inputs::Dict, setup::Dict, EP::Model)
    L_cand = inputs["L_cand"]     # Number of transmission lines
    L = inputs["L"]     # Number of transmission lines

    if setup["DC_OPF"]==1
        # Transmission network reinforcements
        transcap = zeros(L_cand)
        for l in 1:L_cand
            if l in inputs["EXPANSION_LINES"]
                if setup["SOS1"] == 0
                    for i in 1:inputs["Max_Trans_Cap"][l]
                        println("Decision for ", l, " ", i, " ", value.(EP[:vNEW_TRANS_CAP_DECISION_INT][l,i]))
                        transcap[l] = sum(value.(EP[:vNEW_TRANS_CAP_DECISION_INT][l,i]) for i in 1:inputs["Max_Trans_Cap"][l]; init=0)
                    end
                else
                    println("Decision for ", l, " ", value.(EP[:vNEW_TRANS_CAP_DECISION_INT][l]))
                    transcap[l] = value.(EP[:vNEW_TRANS_CAP_DECISION_INT][l])
                end
            end
        end

        dfTransCap = DataFrame(Line = 1:L_cand,
            New_Trans_Capacity_Dec_Var = convert(Array{Int64}, transcap)#=,
            New_Trans_Capacity = convert(Array{Float64}, transcap .* inputs["Line_Reinforcement_Cap_Size"]),
            Cost_Trans_Capacity = convert(Array{Float64},
                transcap .* inputs["Line_Reinforcement_Cap_Size"] .* inputs["pC_Line_Reinforcement"])=#)

        #=if setup["ParameterScale"] == 1
            dfTransCap.New_Trans_Capacity *= ModelScalingFactor  # GW to MW
            dfTransCap.Cost_Trans_Capacity *= ModelScalingFactor^2  # MUSD to USD
        end=#

        CSV.write(joinpath(path, "network_expansion_dc.csv"), dfTransCap)
    else
    
        # Transmission network reinforcements
        transcap = zeros(L)
        for i in 1:L
            if i in inputs["EXPANSION_LINES"]
                transcap[i] = value.(EP[:vNEW_TRANS_CAP][i])
            end
        end

        dfTransCap = DataFrame(Line = 1:L,
            New_Trans_Capacity = convert(Array{Float64}, transcap),
            Cost_Trans_Capacity = convert(Array{Float64},
                transcap .* inputs["pC_Line_Reinforcement"]))

        if setup["ParameterScale"] == 1
            dfTransCap.New_Trans_Capacity *= ModelScalingFactor  # GW to MW
            dfTransCap.Cost_Trans_Capacity *= ModelScalingFactor^2  # MUSD to USD
        end

        CSV.write(joinpath(path, "network_expansion.csv"), dfTransCap)
    end
end
