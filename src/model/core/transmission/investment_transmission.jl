@doc raw"""
    investment_transmission!(EP::Model, inputs::Dict, setup::Dict)
This function model transmission expansion and adds transmission reinforcement or construction costs to the objective function. Transmission reinforcement costs are equal to the sum across all lines of the product between the transmission reinforcement/construction cost, $\pi^{TCAP}_{l}$, times the additional transmission capacity variable, $\bigtriangleup\varphi^{cap}_{l}$.
```math
\begin{aligned}
    & \sum_{l \in \mathcal{L}}\left(\pi^{TCAP}_{l} \times \bigtriangleup\varphi^{cap}_{l}\right)
\end{aligned}
```
Note that fixed O\&M and replacement capital costs (depreciation) for existing transmission capacity is treated as a sunk cost and not included explicitly in the GenX objective function.

**Accounting for Transmission Between Zones**

Available transmission capacity between zones is set equal to the existing line's maximum power transfer capacity, $\overline{\varphi^{cap}_{l}}$, plus any transmission capacity added on that line (for lines eligible for expansion in the set $\mathcal{E}$). 
```math
\begin{aligned}
    &\varphi^{cap}_{l} = \overline{\varphi^{cap}_{l}} , &\quad \forall l \in (\mathcal{L} \setminus \mathcal{E} ),\forall t  \in \mathcal{T}\\
    % trasmission expansion
    &\varphi^{cap}_{l} = \overline{\varphi^{cap}_{l}} + \bigtriangleup\varphi^{cap}_{l} , &\quad \forall l \in \mathcal{E},\forall t  \in \mathcal{T}        
\end{aligned}
```
The additional transmission capacity, $\bigtriangleup\varphi^{cap}_{l} $, is constrained by a maximum allowed reinforcement, $\overline{\bigtriangleup\varphi^{cap}_{l}}$, for each line $l \in \mathcal{E}$.
```math
\begin{aligned}
    & \bigtriangleup\varphi^{cap}_{l}  \leq \overline{\bigtriangleup\varphi^{cap}_{l}}, &\quad \forall l \in \mathcal{E}
\end{aligned}
```
"""
function investment_transmission!(EP::Model, inputs::Dict, setup::Dict)
    println("Investment Transmission Module")

    L = inputs["L"]     # Number of transmission lines
    NetworkExpansion = setup["NetworkExpansion"]
    MultiStage = setup["MultiStage"]

    if NetworkExpansion == 1
        L_cand = inputs["L_cand"]     # Number of candidate transmission lines
        # Network lines and zones that are expandable have non-negative maximum reinforcement inputs
        EXPANSION_LINES = inputs["EXPANSION_LINES"]
        if setup["DC_OPF"] == 1
            REINFORCEMENT_CAP_SIZE = inputs["Line_Reinforcement_Cap_Size"]
            MAX_TRAN_EXPANSION_LIMIT=inputs["Max_Trans_Cap"]
            EXPANSION_LEVELS=Dict{Int,Vector{Float64}}()
            for l in EXPANSION_LINES
                EXPANSION_LEVELS[l] = (0:1:MAX_TRAN_EXPANSION_LIMIT[l]) #-Might not need multiplication of this part -->* REINFORCEMENT_CAP_SIZE[l]
            end
            inputs["EXPANSION_LEVELS"] = EXPANSION_LEVELS
            if setup["ptdf"] == 1
                line_map = Dict()
                cand_line_map = Dict()

                line_adj = inputs["pNet_Map"]
                cand_line_adj = inputs["pNet_Map_cand"]
                for i in 1:size(line_adj)[1]
                    from_idx = findfirst(x -> x == 1, line_adj[i, :])
                    to_idx = findfirst(x -> x == -1, line_adj[i, :])
                    line_map[i] = (from_idx, to_idx)
                end
                for i in 1:size(cand_line_adj)[1]
                    from_idx = findfirst(x -> x == 1, cand_line_adj[i, :])
                    to_idx = findfirst(x -> x == -1, cand_line_adj[i, :])
                    cand_line_map[i] = (from_idx, to_idx)
                end


                inputs["Line_Map"] = line_map
                inputs["Cand_Line_Map"] = cand_line_map
            end
        end
    end

    ### Variables ###

    if MultiStage == 1
        @variable(EP, vTRANSMAX[l = 1:L]>=0)
    end
    if NetworkExpansion == 1
        if setup["DC_OPF"] == 1
            if setup["ptdf"] == 1
                @variable(EP, vZ_BUILD[l in EXPANSION_LINES, i in 1:(inputs["Max_Trans_Cap"][l])], Bin)
                @constraint(EP, 
                    cBUILD_SEQUENCE[l in EXPANSION_LINES, i in 1:(inputs["Max_Trans_Cap"][l]-1)],
                    EP[:vZ_BUILD][l, i] >= EP[:vZ_BUILD][l, i + 1]
                )
            elseif setup["SOS1"] == 1
                @variable(EP, 0<=vZ_SOS1_VAR[l in EXPANSION_LINES, i in 1:(1+inputs["Max_Trans_Cap"][l])]<=1) #SOS1 variable
	            @variable(EP, vNEW_TRANS_CAP_DECISION_INT[l in EXPANSION_LINES], Int, lower_bound = 0)
            elseif setup["disaggregate"] == 1
                @variable(EP, vNEW_TRANS_CAP_DECISION_INT[l in EXPANSION_LINES, i in 1:(inputs["Max_Trans_Cap"][l]+1)], Bin) #binary decisions function as SOS1 vars
                @constraint(EP, SOS1_CONSTRAINT[l in EXPANSION_LINES], sum(vNEW_TRANS_CAP_DECISION_INT[l, i] for i in 1:(inputs["Max_Trans_Cap"][l]+1)) == 1)
                #@constraint(EP, 
                #        cBUILD_SEQUENCE[l in EXPANSION_LINES, i in 1:(inputs["Max_Trans_Cap"][l]-1)],
                #        EP[:vNEW_TRANS_CAP_DECISION_INT][l, i] >= EP[:vNEW_TRANS_CAP_DECISION_INT][l, i + 1]
                #)
            elseif setup["bilinear"] == 1
	            @variable(EP, vNEW_TRANS_CAP_DECISION_INT[l in EXPANSION_LINES, i in 1:inputs["Max_Trans_Cap"][l]], Bin)
                @constraint(EP, 
                        cBUILD_SEQUENCE[l in EXPANSION_LINES, i in 1:(inputs["Max_Trans_Cap"][l]-1)],
                        EP[:vNEW_TRANS_CAP_DECISION_INT][l, i] >= EP[:vNEW_TRANS_CAP_DECISION_INT][l, i + 1]
                )
            else
                @variable(EP, vNEW_TRANS_CAP_DECISION_INT[l in EXPANSION_LINES, i in 1:inputs["Max_Trans_Cap"][l]], Bin)
                @constraint(EP, 
                        cBUILD_SEQUENCE[l in EXPANSION_LINES, i in 1:(inputs["Max_Trans_Cap"][l]-1)],
                        EP[:vNEW_TRANS_CAP_DECISION_INT][l, i] >= EP[:vNEW_TRANS_CAP_DECISION_INT][l, i + 1]
                )
            end
        elseif setup["IntegerInvestments"] == 1
            # Transmission network capacity reinforcements per line, integer
            @variable(EP, vNEW_TRANS_LINES[l in EXPANSION_LINES], Int, lower_bound=0)
            for l in EXPANSION_LINES
                set_upper_bound(vNEW_TRANS_LINES[l], inputs["Max_Trans_Cap"][l])
            end
        else
            # Transmission network capacity reinforcements per line
            @variable(EP, vNEW_TRANS_CAP[l in EXPANSION_LINES]>=0)
        end
    end

    ### Expressions ###

    if MultiStage == 1
        @expression(EP, eTransMax[l = 1:L], vTRANSMAX[l])
    else
        @expression(EP, eTransMax[l = 1:L], inputs["pTrans_Max"][l])
    end

    ## Transmission power flow and loss related expressions:
    # Total availabile maximum transmission capacity is the sum of existing maximum transmission capacity plus new transmission capacity
    if NetworkExpansion == 1
        if setup["DC_OPF"] == 1
            if setup["ptdf"] == 1
                @expression(EP, eAvail_Trans_Cap[l = 1:L],
                    if l in EXPANSION_LINES
                        eTransMax[l] + sum(vZ_BUILD[l, i] for i in 1:(inputs["Max_Trans_Cap"][l])) * inputs["Line_Reinforcement_Cap_Size"][l] #TODO: Make sure this "l" is the correct index
                    else
                        eTransMax[l]
                    end
                )
            elseif setup["SOS1"] == 1
                @expression(EP, eAvail_Trans_Cap[l = 1:L],
                if l in EXPANSION_LINES
                    eTransMax[l] + vNEW_TRANS_CAP_DECISION_INT[l]*inputs["Line_Reinforcement_Cap_Size"][l]
                else
                    eTransMax[l]
                end)
            else 
                @expression(EP, eAvail_Trans_Cap[l = 1:L],
                if l in EXPANSION_LINES
                    eTransMax[l] + sum(vNEW_TRANS_CAP_DECISION_INT[l,i] for i in 1:inputs["Max_Trans_Cap"][l])*inputs["Line_Reinforcement_Cap_Size"][l]
                else
                    eTransMax[l]
                end)
            end
        elseif setup["IntegerInvestments"] == 1
            @expression(EP, eAvail_Trans_Cap[l = 1:L],
            if l in EXPANSION_LINES
                eTransMax[l] + vNEW_TRANS_LINES[l]*inputs["Line_Reinforcement_Cap_Size"][l]
            else
                eTransMax[l]
            end)
        else
            @expression(EP, eAvail_Trans_Cap[l = 1:L],
            if l in EXPANSION_LINES
                eTransMax[l] + vNEW_TRANS_CAP[l]
            else
                eTransMax[l]
            end)
        end
    else
        @expression(EP, eAvail_Trans_Cap[l = 1:L], eTransMax[l])
    end

    ## Objective Function Expressions ##

    if NetworkExpansion == 1
        if setup["DC_OPF"] == 1
            if setup["ptdf"] == 1
                @expression(EP,
                    eTotalCNetworkExp,
                    sum(
                        sum(vZ_BUILD[l, i] * inputs["pC_Line_Reinforcement"][l] * inputs["Line_Reinforcement_Cap_Size"][l] for i in 1:(inputs["Max_Trans_Cap"][l])
                        )
                    for l in EXPANSION_LINES)
                )
            elseif setup["SOS1"] == 1
                @expression(EP,
                    eTotalCNetworkExp,
                    sum(vNEW_TRANS_CAP_DECISION_INT[l] * inputs["pC_Line_Reinforcement"][l] * inputs["Line_Reinforcement_Cap_Size"][l]
                    for l in EXPANSION_LINES)
                )
            elseif setup["disaggregate"] == 1
                @expression(EP,
                eTotalCNetworkExp,
                sum(sum(vNEW_TRANS_CAP_DECISION_INT[l,i] * (i - 1) for i in 1:inputs["Max_Trans_Cap"][l]+1) * inputs["Line_Reinforcement_Cap_Size"][l]* inputs["pC_Line_Reinforcement"][l] 
                for l in EXPANSION_LINES))
            else
                @expression(EP,
                eTotalCNetworkExp,
                sum(sum(vNEW_TRANS_CAP_DECISION_INT[l,i] for i in 1:inputs["Max_Trans_Cap"][l]) * inputs["Line_Reinforcement_Cap_Size"][l]* inputs["pC_Line_Reinforcement"][l] 
                for l in EXPANSION_LINES))
            end
        elseif setup["IntegerInvestments"] == 1
            @expression(EP,
                eTotalCNetworkExp,
                sum(vNEW_TRANS_LINES[l] * inputs["Line_Reinforcement_Cap_Size"][l] * inputs["pC_Line_Reinforcement"][l]
                for l in EXPANSION_LINES))
        else
            @expression(EP,
                eTotalCNetworkExp,
                sum(vNEW_TRANS_CAP[l] * inputs["pC_Line_Reinforcement"][l]
                for l in EXPANSION_LINES))
        end
        if MultiStage == 1
            # OPEX multiplier to count multiple years between two model stages
            # We divide by OPEXMULT since we are going to multiply the entire objective function by this term later,
            # and we have already accounted for multiple years between stages for fixed costs.
            add_to_expression!(EP[:eObj], (1 / inputs["OPEXMULT"]), eTotalCNetworkExp)
        else
            add_to_expression!(EP[:eObj], eTotalCNetworkExp)
        end
    end

    ## End Objective Function Expressions ##

    ### Constraints ###

    if MultiStage == 1
        # Linking constraint for existing transmission capacity
        @constraint(EP, cExistingTransCap[l = 1:L], vTRANSMAX[l]==inputs["pTrans_Max"][l])
    end

    # If network expansion is used:
    
    if NetworkExpansion == 1
        # Transmission network related power flow and capacity constraints
        # If network expansion is used:
        if setup["DC_OPF"] == 1
            if setup["ptdf"] == 0 && setup["SOS1"] == 1
                @constraint(EP, cZ_SOS1_VAR[l in EXPANSION_LINES], vZ_SOS1_VAR[l,:] in SOS1())
                @constraint(EP, cZ_SOS1_VAR_SUM_COND[l in EXPANSION_LINES], sum(vZ_SOS1_VAR[l,i] for i in 1:(1+inputs["Max_Trans_Cap"][l])) == 1)
                @constraint(EP, cNEW_TRANS_CAP_DECISION[l in EXPANSION_LINES], vNEW_TRANS_CAP_DECISION_INT[l] == sum(vZ_SOS1_VAR[l,i].*EXPANSION_LEVELS[l][i] for i in 1:(1+inputs["Max_Trans_Cap"][l])))
                # Transmission network related power flow and capacity constraints
            end
        end
        if MultiStage == 1
            # Constrain maximum possible flow for lines eligible for expansion regardless of previous expansions
            @constraint(EP,
                cMaxFlowPossible[l in EXPANSION_LINES],
                eAvail_Trans_Cap[l]<=inputs["pTrans_Max_Possible"][l])
        end

        if setup["IntegerInvestments"] == 1 && setup["DC_OPF"] == 0
            # Constrain maximum single-stage line capacity reinforcement for lines eligible for expansion with integers
            @constraint(EP,
                cMaxLineReinforcement[l in EXPANSION_LINES],
                vNEW_TRANS_LINES[l]<=inputs["Line_Reinforcement_Cap_Size"][l]) 
        elseif setup["DC_OPF"] == 1
            if (setup["ptdf"] == 0 && setup["SOS1"] == 1)
                @constraint(EP,
                    cMaxLineReinforcement[l in EXPANSION_LINES],
                    vNEW_TRANS_CAP_DECISION_INT[l]<=inputs["Max_Trans_Cap"][l])
            end
        else        # Constrain maximum single-stage line capacity reinforcement for lines eligible for expansion
            @constraint(EP,
                cMaxLineReinforcement[l in EXPANSION_LINES],
                vNEW_TRANS_CAP[l]<=inputs["pMax_Line_Reinforcement"][l])
        end
    end
    #END network expansion contraints

end
