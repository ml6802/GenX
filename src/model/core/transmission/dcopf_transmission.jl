@doc raw"""
	function DC_OPF_transmission!(EP::Model, inputs::Dict, setup::Dict)
    dcopf_transmission!(EP::Model, inputs::Dict, setup::Dict)
The addtional constraints imposed upon the line flows in the case of DC-OPF are as follows:
For the definition of the line flows, in terms of the voltage phase angles:
```math
\begin{aligned}
        & \Phi_{l,t}=\mathcal{B}_{l} \times (\sum_{z\in \mathcal{Z}}{(\varphi^{map}_{l,z} \times \theta_{z,t})}) \quad \forall l \in \mathcal{L}, \; \forall t  \in \mathcal{T}\\
\end{aligned}
```
For imposing the constraint of maximum allowed voltage phase angle difference across lines:
```math
\begin{aligned}
    & \sum_{z\in \mathcal{Z}}{(\varphi^{map}_{l,z} \times \theta_{z,t})} \leq \Delta \theta^{\max}_{l} \quad \forall l \in \mathcal{L}, \forall t  \in \mathcal{T}\\
	& \sum_{z\in \mathcal{Z}}{(\varphi^{map}_{l,z} \times \theta_{z,t})} \geq -\Delta \theta^{\max}_{l} \quad \forall l \in \mathcal{L}, \forall t  \in \mathcal{T}\\
\end{aligned}
```
Finally, we enforce the reference voltage phase angle constraint (for the slack bus/reference bus):
```math
\begin{aligned}
\theta_{1,t} = 0 \quad \forall t  \in \mathcal{T}
\end{aligned}
```

"""
function DC_OPF_transmission!(EP::Model, inputs::Dict, setup::Dict)
    println("DC-OPF Transmission Flows Module")

    scale_factor = setup["ParameterScale"] == 1 ? ModelScalingFactor : 1

    T = inputs["T"]     # Number of time steps (hours)
    Z = inputs["Z"]     # Number of zones
    L = inputs["L"]     # Number of transmission lines
    L_cand = inputs["L_cand"]     # Number of candidate transmission lines
    Z_cand = inputs["Z_cand"]     # Number of candidate zones
    NetworkExpansion = setup["NetworkExpansion"]
    BigM_vec = inputs["pMax_Line_Reinforcement"] # length of number of lines
    quant_val = inputs["Line_Reinforcement_Cap_Size"]
    num_steps = BigM_vec ./ quant_val
    num_cols = maximum(num_steps)
    if !(haskey(setup, "tight_bigM"))
        setup["tight_bigM"] = false
    end
    if setup["tight_bigM"]
        BigM = quant_val#.1 .*inputs["pMax_Line_Reinforcement"]
    else
        BigM = 2.5 * inputs["pMax_Line_Reinforcement"]
    end

    #for i in 1:length(BigM_vec)
    #    for j in 1:Int(num_steps[i]+1)
    #        # if j == 1
    #            # BigM[i, j] = 300
    #        # else
    #            # BigM[i, j] = (j - 1) * quant_val[i]
    #        # end
    #        BigM[i, j] = (j - 1) * quant_val[i]
    #    end
    #end
    inputs["BigM"] = BigM


    if NetworkExpansion == 1
        # Network lines and zones that are expandable have non-negative maximum reinforcement inputs
        EXPANSION_LINES = inputs["EXPANSION_LINES"]
        EXPANSION_LEVELS = inputs["EXPANSION_LEVELS"]
        if setup["DC_OPF"] == 1
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


    

    if setup["ptdf"] == 0 && setup["SOS1"] == 1
            ### DC-OPF variables ###
        # Note, these are definable without overwriting the existing variables in the model because transmission.jl is not called when this file is called.
        # Power flow on each existing transmission line "l" at hour "t"
        @variable(EP, vFLOW[l = 1:L, t = 1:T])

        # Power flow on each candidate transmission line "l" at hour "t"
        @variable(EP, vCANDFLOW[l = 1:L_cand, t = 1:T])

        # Voltage angle variables of each zone "z" at hour "t" 
        @variable(EP, vANGLE[z = 1:Z, t = 1:T])

        @variable(EP, vPROX_ANGLE[l in EXPANSION_LINES, t = 1:T, i in 1:(1+inputs["Max_Trans_Cap"][l])])

        ### DC-OPF constraints ###

        # Power flow constraint existing lines:: vFLOW = DC_OPF_coeff * (vANGLE[START_ZONE] - vANGLE[END_ZONE])
        @constraint(EP,
            cPOWER_FLOW_OPF[l = 1:L, t = 1:T],
            EP[:vFLOW][l,
                t]==inputs["pDC_OPF_coeff"][l] *
                    sum(inputs["pNet_Map"][l, z] * vANGLE[z, t] for z in 1:Z))

        #Power Flow in the candidate expansion lines
        @constraint(EP,
                    cPOWER_FLOW_OPF_EXPANSION[l in EXPANSION_LINES, t = 1:T],
                    EP[:vCANDFLOW][l,t]==inputs["pDC_OPF_coeff_cand"][l] * sum(vPROX_ANGLE[l,t,i]*EXPANSION_LEVELS[l][i] for i in 1:(1+inputs["Max_Trans_Cap"][l])))
        # SOS1 Constraints for Voltage Phase Angle
        @constraint(EP,
                cPOWER_FLOW_OPF_ANGLE_SOS1_1[l in EXPANSION_LINES, t = 1:T, i in 1:(1+inputs["Max_Trans_Cap"][l])], 
                vPROX_ANGLE[l,t,i] >= 0)
        @constraint(EP,
                cPOWER_FLOW_OPF_ANGLE_SOS1_2[l in EXPANSION_LINES, t = 1:T, i in 1:(1+inputs["Max_Trans_Cap"][l])], 
                sum(inputs["pNet_Map_cand"][l, z] * vANGLE[z, t] for z in 1:Z)-vPROX_ANGLE[l,t,i] <= BigM[l]*(1-EP[:vZ_SOS1_VAR][l,i]))
        @constraint(EP,
                cPOWER_FLOW_OPF_ANGLE_SOS1_3[l in EXPANSION_LINES, t = 1:T, i in 1:(1+inputs["Max_Trans_Cap"][l])],
                sum(inputs["pNet_Map_cand"][l, z] * vANGLE[z, t] for z in 1:Z)-vPROX_ANGLE[l,t,i] >= 0)
        @constraint(EP,
                cPOWER_FLOW_OPF_ANGLE_SOS1_4[l in EXPANSION_LINES, t = 1:T, i in 1:(1+inputs["Max_Trans_Cap"][l])], 
                vPROX_ANGLE[l,t,i] <= 3.14*EP[:vZ_SOS1_VAR][l,i])
         # Bus angle limits (except slack bus)
        @constraints(EP,
            begin
                cANGLE_ub[l = 1:L, t = 1:T],
                sum(inputs["pNet_Map"][l, z] * vANGLE[z, t] for z in 1:Z) <=
                inputs["Line_Angle_Limit"][l]
                cANGLE_lb[l = 1:L, t = 1:T],
                sum(inputs["pNet_Map"][l, z] * vANGLE[z, t] for z in 1:Z) >=
                -inputs["Line_Angle_Limit"][l]
            end)

        # Export and import limits
        @constraints(EP,
            begin
                cMaxFlow_out_existing[l = 1:L, t = 1:T], EP[:vFLOW][l, t] <= EP[:eTransMax][l]
                cMaxFlow_in_existing[l = 1:L, t = 1:T], EP[:vFLOW][l, t] >= -EP[:eTransMax][l]
            end)

        @constraints(EP,
            begin
                cMaxFlow_out_candidate[l in EXPANSION_LINES, t = 1:T], EP[:vCANDFLOW][l, t] <= EP[:vNEW_TRANS_CAP_DECISION_INT][l]*inputs["Line_Reinforcement_Cap_Size"][l]
                cMaxFlow_in_candidate[l in EXPANSION_LINES, t = 1:T], EP[:vCANDFLOW][l, t] >= -EP[:vNEW_TRANS_CAP_DECISION_INT][l]*inputs["Line_Reinforcement_Cap_Size"][l]
            end
        )
        # Slack Bus angle limit
        @constraint(EP, cANGLE_SLACK[t = 1:T], vANGLE[1, t]==0)

        @expression(EP,
            eCand_Flow[l in EXPANSION_LINES, t = 1:T], EP[:vCANDFLOW][l, t])

        @expression(EP,
            eNet_Export_Cand_Flows[z = 1:Z, t = 1:T],
            sum(inputs["pNet_Map_cand"][l, z] * EP[:vCANDFLOW][l, t] for l in EXPANSION_LINES))
    elseif setup["ptdf"] == 1 #PTDF constraints
            ### DC-OPF variables ###
        # Note, these are definable without overwriting the existing variables in the model because transmission.jl is not called when this file is called.
        # Power flow on each existing transmission line "l" at hour "t"
        @variable(EP, vFLOW[l = 1:L, t = 1:T])

        # Power flow on each candidate transmission line "l" at hour "t"
        @variable(EP, vCANDFLOW[l = 1:L_cand, t = 1:T])

        ptdf_nodal, ptdf_by_line = calculate_ptdf_matrices(inputs) #TODO: Add slack bus to inputs if we go this route of doing ptdf
        inputs["ptdf_by_line"] = ptdf_by_line
        
        @variable(EP, p_bus[1:Z, 1:T])
        @constraint(EP, cBUS_INJECTION[z = 1:Z, t = 1:T], p_bus[z, t] == EP[:eGenerationByZone][z, t] + sum(EP[:vNSE][:, t, z]) - inputs["pD"][t, z])
#
        @constraint(EP, SYSTEM_BALANCE[t = 1:T], sum(p_bus[z, t] for z in 1:Z) == 0)
        #TODO: currently, there is no support for candidate lines in corridors where there is not an existing line

        line_map = inputs["Line_Map"]
        cand_line_map = inputs["Cand_Line_Map"]
        @variable(EP, p_virtual[l in EXPANSION_LINES, i in 1:(inputs["Max_Trans_Cap"][l]), t in 1:T])

        # The following constraints assume EXPANSION_LINES == existing lines
        @expression(EP, 
            eFLOW_LINES[l in EXPANSION_LINES, t in 1:T],
            sum(get_ptdf_vector(ptdf_by_line, l, 0, line_map)[z] * p_bus[z, t] for z in 1:Z) + 
            sum(
                (get_ptdf_line_diff(ptdf_by_line, l, 0, ll, line_map)) * p_virtual[ll, i, t] 
                for ll in EXPANSION_LINES, i in 1:(inputs["Max_Trans_Cap"][ll])
            )
        )
        F_existing = inputs["pTrans_Max"]
        @constraint(EP, 
            cEXISTING_LINE_FLOWS[l in EXPANSION_LINES, t in 1:T],
            -F_existing[l] <= eFLOW_LINES[l, t] <= F_existing[l]
        ) # 18 for existing lines in paper https://ietresearch.onlinelibrary.wiley.com/doi/epdf/10.1049/iet-gtd.2015.1573

        @expression(EP, 
            eCAND_FLOW_LINES[l in EXPANSION_LINES, i in 1:(inputs["Max_Trans_Cap"][l]), t in 1:T],
            p_virtual[l, i, t] -
            sum(get_ptdf_vector(ptdf_by_line, l, i, cand_line_map)[z] * p_bus[z, t] for z in 1:Z) - 
            sum(get_ptdf_line_diff(ptdf_by_line, l, i, ll, cand_line_map) * p_virtual[ll, ii, t] for ll in EXPANSION_LINES, ii in 1:(inputs["Max_Trans_Cap"][ll]))
        )

        F_cand = inputs["Line_Reinforcement_Cap_Size"]
        @constraint(EP, 
            cCAND_LINE_FLOWS_LOWER[l in EXPANSION_LINES, i in 1:(inputs["Max_Trans_Cap"][l]), t in 1:T],
            eCAND_FLOW_LINES[l, i, t] >= -F_cand[l] * EP[:vZ_BUILD][l, i]
        ) # 19 for existing lines in paper https://ietresearch.onlinelibrary.wiley.com/doi/epdf/10.1049/iet-gtd.2015.1573

        @constraint(EP, 
            cCAND_LINE_FLOWS_UPPER[l in EXPANSION_LINES, i in 1:(inputs["Max_Trans_Cap"][l]), t in 1:T],
            eCAND_FLOW_LINES[l, i, t] <= F_cand[l] * EP[:vZ_BUILD][l, i]
        ) # 19 for existing lines in paper https://ietresearch.onlinelibrary.wiley.com/doi/epdf/10.1049/iet-gtd.2015.1573
        
        M = 10 .* F_cand
        @constraint(EP, 
            cBIGM_PTDF_LOWER[l in EXPANSION_LINES, i in 1:(inputs["Max_Trans_Cap"][l]), t in 1:T],
            p_virtual[l, i, t] >= -M[l] * (1 - EP[:vZ_BUILD][l, i])
        ) # 20 for existing lines in paper https://ietresearch.onlinelibrary.wiley.com/doi/epdf/10.1049/iet-gtd.2015.1573

        @constraint(EP, 
            cBIGM_PTDF_UPPER[l in EXPANSION_LINES, i in 1:(inputs["Max_Trans_Cap"][l]), t in 1:T],
            p_virtual[l, i, t] <= M[l] * (1 - EP[:vZ_BUILD][l, i])
        ) # 20 for existing lines in paper https://ietresearch.onlinelibrary.wiley.com/doi/epdf/10.1049/iet-gtd.2015.1573


        @constraint(EP, [l in EXPANSION_LINES, t in 1:T],
            EP[:vFLOW][l, t] == eFLOW_LINES[l, t]
        )

        @constraint(EP, [l in EXPANSION_LINES, t in 1:T],
            EP[:vCANDFLOW][l, t] == sum(sum(get_ptdf_vector(ptdf_by_line, l, i, cand_line_map)[z] * p_bus[z, t] for z in 1:Z) + 
            sum(get_ptdf_line_diff(ptdf_by_line, l, i, ll, cand_line_map) * p_virtual[ll, ii, t] for ll in EXPANSION_LINES, ii in 1:(inputs["Max_Trans_Cap"][ll])) for i in 1:(inputs["Max_Trans_Cap"][l]))
        )

        @expression(EP,
        eCand_Flow[l in EXPANSION_LINES, t = 1:T], EP[:vCANDFLOW][l, t])

        @expression(EP,
            eNet_Export_Cand_Flows[z = 1:Z, t = 1:T],
            sum(inputs["pNet_Map_cand"][l, z] * EP[:vCANDFLOW][l, t] for l in EXPANSION_LINES))

        # for existing line corridors, define (1)

        # for all lines, define 19
        # for all lines, define 20

        # for candidate lines, define 21


        # define balance variables
        # define virtual inputs for each node
        # define x1 >= x2 >= x3 >= ...
    elseif setup["bilinear"] == 1
        @variable(EP, vFLOW[l = 1:L, t = 1:T])
        @variable(EP, vCANDFLOW[l = 1:L_cand, t = 1:T])
        @variable(EP, vANGLE[z = 1:Z, t = 1:T])

        @constraint(EP,
            cPOWER_FLOW_OPF[l = 1:L, t = 1:T],
            EP[:vFLOW][l,
                t]==inputs["pDC_OPF_coeff"][l] *
                    sum(inputs["pNet_Map"][l, z] * vANGLE[z, t] for z in 1:Z))

        @constraints(EP,
        begin
            cMaxFlow_out_existing[l = 1:L, t = 1:T], EP[:vFLOW][l, t] <= EP[:eTransMax][l]
            cMaxFlow_in_existing[l = 1:L, t = 1:T], EP[:vFLOW][l, t] >= -EP[:eTransMax][l]
        end
        )

        @constraint(EP,
            cCANDFLOW[l in EXPANSION_LINES, t = 1:T],
            vCANDFLOW[l, t] == inputs["pDC_OPF_coeff_cand"][l] *
                        sum(inputs["pNet_Map_cand"][l, z] * vANGLE[z, t] for z in 1:Z) * EP[:vNEW_TRANS_CAP_DECISION_INT][l]
        )

        # Slack Bus angle limit
        @constraint(EP, cANGLE_SLACK[t = 1:T], vANGLE[1, t]==0)
        
        @expression(EP,
            eCand_Flow[l in EXPANSION_LINES, t = 1:T], EP[:vCANDFLOW][l, t])

        @expression(EP,
            eNet_Export_Cand_Flows[z = 1:Z, t = 1:T],
            sum(inputs["pNet_Map_cand"][l, z] * EP[:vCANDFLOW][l, t] for l in EXPANSION_LINES))

    elseif setup["disaggregate"] == 1
        @variable(EP, vFLOW[l = 1:L, t = 1:T])

        # Power flow on each candidate transmission line "l" at hour "t"
        @variable(EP, vCANDFLOW[l = 1:L_cand, t = 1:T, i in 1:inputs["Max_Trans_Cap"][l]+1])

        # Voltage angle variables of each zone "z" at hour "t" 
        @variable(EP, vANGLE[z = 1:Z, t = 1:T])

        @variable(EP, vCANDFLOW_TOTAL[l = 1:L_cand, t = 1:T])
        @variable(EP, vCANDPROX[l = 1:L_cand, t = 1:T])

        # Power FLow on existing lines
        @constraint(EP,
            cPOWER_FLOW_OPF[l = 1:L, t = 1:T],
            EP[:vFLOW][l,
                t]==inputs["pDC_OPF_coeff"][l] *
                    sum(inputs["pNet_Map"][l, z] * vANGLE[z, t] for z in 1:Z)
        )

        @constraints(EP,
        begin
            cMaxFlow_out_existing[l = 1:L, t = 1:T], EP[:vFLOW][l, t] <= EP[:eTransMax][l]
            cMaxFlow_in_existing[l = 1:L, t = 1:T], EP[:vFLOW][l, t] >= -EP[:eTransMax][l]
        end)

        # lower and upper bounds on vCANDFLOW <= EP[vZ] * inputs["Line_Reinforcemnet_CAPSIZE][l]
        # vcand_tot = 
        # vcand_total = sum(i * vcandflow)
        # add note to other file that says only one x and be one at a time
        # 

        # #Power Flow in the candidate expansion lines
        # @constraint(EP,
        #     cPOWER_FLOW_OPF_EXPANSION_FORWARD[l in EXPANSION_LINES, t = 1:T, i in 1:inputs["Max_Trans_Cap"][l]+1],
        #         EP[:vCANDFLOW][l,t,i]-inputs["pDC_OPF_coeff_cand"][l] *
        #                 sum(inputs["pNet_Map_cand"][l, z] * vANGLE[z, t] for z in 1:Z) <= BigM[l]*(1-EP[:vNEW_TRANS_CAP_DECISION_INT][l,i])
        # )
        # @constraint(EP,
        #     cPOWER_FLOW_OPF_EXPANSION_REVERSE[l in EXPANSION_LINES, t = 1:T, i in 1:inputs["Max_Trans_Cap"][l]],
        #         EP[:vCANDFLOW][l,t,i]-inputs["pDC_OPF_coeff_cand"][l] *
        #                 sum(inputs["pNet_Map_cand"][l, z] * vANGLE[z, t] for z in 1:Z) >= -BigM[l]*(1-EP[:vNEW_TRANS_CAP_DECISION_INT][l,i])
        # )

        @constraints(EP,
        begin
            cMaxFlow_out_candidate[l in EXPANSION_LINES, t = 1:T, i in 1:inputs["Max_Trans_Cap"][l]+1], EP[:vCANDFLOW][l, t, i] <= EP[:vNEW_TRANS_CAP_DECISION_INT][l,i]*inputs["Line_Reinforcement_Cap_Size"][l]
            cMaxFlow_in_candidate[l in EXPANSION_LINES, t = 1:T, i in 1:inputs["Max_Trans_Cap"][l]+1], EP[:vCANDFLOW][l, t, i] >= -EP[:vNEW_TRANS_CAP_DECISION_INT][l,i]*inputs["Line_Reinforcement_Cap_Size"][l]
        end)

        # These two constraints ensure that one of the vCANDFLOWs takes a value of the angle difference * reactance
        @constraint(EP,
            cPROX_CANDFLOW1[l in EXPANSION_LINES, t = 1:T],
            vCANDPROX[l, t] == sum(vCANDFLOW[l, t, i] for i in 1:inputs["Max_Trans_Cap"][l]+1)
        )

        @constraint(EP,
            cPROX_CANDFLOW2[l in EXPANSION_LINES, t = 1:T],
            vCANDPROX[l, t] == inputs["pDC_OPF_coeff_cand"][l] *
                        sum(inputs["pNet_Map_cand"][l, z] * vANGLE[z, t] for z in 1:Z)
        )

        @constraint(EP, 
            cTOTAL_CANDFLOW[l = 1:L_cand, t = 1:T],
            vCANDFLOW_TOTAL[l, t] == sum((i - 1) * vCANDFLOW[l, t, i] for i in 1:inputs["Max_Trans_Cap"][l]+1)
        )

        # Slack Bus angle limit
        @constraint(EP, cANGLE_SLACK[t = 1:T], vANGLE[1, t]==0)

        @expression(EP,
        eCand_Flow[l in EXPANSION_LINES, t = 1:T], EP[:vCANDFLOW_TOTAL][l, t])

        @expression(EP,
            eNet_Export_Cand_Flows[z = 1:Z, t = 1:T],
            sum(inputs["pNet_Map_cand"][l, z] * EP[:eCand_Flow][l, t] for l in EXPANSION_LINES)
        )
    else
            ### DC-OPF variables ###
        # Note, these are definable without overwriting the existing variables in the model because transmission.jl is not called when this file is called.
        # Power flow on each existing transmission line "l" at hour "t"
        @variable(EP, vFLOW[l = 1:L, t = 1:T])

        # Power flow on each candidate transmission line "l" at hour "t"
        @variable(EP, vCANDFLOW[l = 1:L_cand, t = 1:T, i in 1:inputs["Max_Trans_Cap"][l]])

        # Voltage angle variables of each zone "z" at hour "t" 
        @variable(EP, vANGLE[z = 1:Z, t = 1:T])

        @variable(EP, vPROX_ANGLE[l in EXPANSION_LINES, t = 1:T, i in 1:(1+inputs["Max_Trans_Cap"][l])])

        ### DC-OPF constraints ###

        # Power flow constraint existing lines:: vFLOW = DC_OPF_coeff * (vANGLE[START_ZONE] - vANGLE[END_ZONE])
        @constraint(EP,
            cPOWER_FLOW_OPF[l = 1:L, t = 1:T],
            EP[:vFLOW][l,
                t]==inputs["pDC_OPF_coeff"][l] *
                    sum(inputs["pNet_Map"][l, z] * vANGLE[z, t] for z in 1:Z))

        #Power Flow in the candidate expansion lines
        @constraint(EP,
            cPOWER_FLOW_OPF_EXPANSION_FORWARD[l in EXPANSION_LINES, t = 1:T, i in 1:inputs["Max_Trans_Cap"][l]],
                EP[:vCANDFLOW][l,t,i]-inputs["pDC_OPF_coeff_cand"][l] *
                        sum(inputs["pNet_Map_cand"][l, z] * vANGLE[z, t] for z in 1:Z) <= BigM[l]*(1-EP[:vNEW_TRANS_CAP_DECISION_INT][l,i]))
        @constraint(EP,
            cPOWER_FLOW_OPF_EXPANSION_REVERSE[l in EXPANSION_LINES, t = 1:T, i in 1:inputs["Max_Trans_Cap"][l]],
                EP[:vCANDFLOW][l,t,i]-inputs["pDC_OPF_coeff_cand"][l] *
                        sum(inputs["pNet_Map_cand"][l, z] * vANGLE[z, t] for z in 1:Z) >= -BigM[l]*(1-EP[:vNEW_TRANS_CAP_DECISION_INT][l,i]))

        @constraints(EP,
        begin
            cMaxFlow_out_existing[l = 1:L, t = 1:T], EP[:vFLOW][l, t] <= EP[:eTransMax][l]
            cMaxFlow_in_existing[l = 1:L, t = 1:T], EP[:vFLOW][l, t] >= -EP[:eTransMax][l]
        end)

        @constraints(EP,
        begin
            cMaxFlow_out_candidate[l in EXPANSION_LINES, t = 1:T, i in 1:inputs["Max_Trans_Cap"][l]], EP[:vCANDFLOW][l, t, i] <= EP[:vNEW_TRANS_CAP_DECISION_INT][l,i]*inputs["Line_Reinforcement_Cap_Size"][l]
            cMaxFlow_in_candidate[l in EXPANSION_LINES, t = 1:T, i in 1:inputs["Max_Trans_Cap"][l]], EP[:vCANDFLOW][l, t, i] >= -EP[:vNEW_TRANS_CAP_DECISION_INT][l,i]*inputs["Line_Reinforcement_Cap_Size"][l]
        end)

        @expression(EP,
        eCand_Flow[l in EXPANSION_LINES, t = 1:T],
        sum(EP[:vCANDFLOW][l, t, i] for i in 1:inputs["Max_Trans_Cap"][l]))

        @expression(EP,
            eNet_Export_Cand_Flows[z = 1:Z, t = 1:T],
            sum(inputs["pNet_Map_cand"][l, z] * EP[:eCand_Flow][l, t] for l in EXPANSION_LINES))

        # Slack Bus angle limit
        @constraint(EP, cANGLE_SLACK[t = 1:T], vANGLE[1, t]==0)

    end


    @expression(EP,
        eNet_Export_Flows[z = 1:Z, t = 1:T],
        sum(inputs["pNet_Map"][l, z] * EP[:vFLOW][l, t] for l in 1:L))

    

    # Export and import expressions
    @expression(EP, ePowerBalanceNetExportFlows[t = 1:T, z = 1:Z],
        -eNet_Export_Flows[z, t])
    @expression(EP, ePowerBalanceCandExportFlows[t = 1:T, z = 1:Z],
        -eNet_Export_Cand_Flows[z, t])

    add_similar_to_expression!(EP[:ePowerBalance], ePowerBalanceCandExportFlows)
    add_similar_to_expression!(EP[:ePowerBalance], ePowerBalanceNetExportFlows)

end
