@doc raw"""
	function DC_OPF_transmission!(EP::Model, inputs::Dict, setup::Dict)
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
Finally, we enforce the reference voltage phase angle constraint:
```math
\begin{aligned}
\theta_{1,t} = 0 \quad \forall t  \in \mathcal{T}
\end{aligned}
```

"""
function DC_OPF_transmission!(EP::Model, inputs::Dict, setup::Dict)
    println("DC-OPF Module")

    T = inputs["T"]     # Number of time steps (hours)
    Z = inputs["Z"]     # Number of zones
    L = inputs["L"]     # Number of transmission lines
    L_cand = inputs["L_cand"]     # Number of candidate transmission lines
    Z_cand = inputs["Z_cand"]     # Number of candidate zones
    NetworkExpansion = setup["NetworkExpansion"]
    BigM = 2.5.*inputs["pMax_Line_Reinforcement"]
    if NetworkExpansion == 1
        # Network lines and zones that are expandable have non-negative maximum reinforcement inputs
        EXPANSION_LINES = inputs["EXPANSION_LINES"]
        EXPANSION_LEVELS = inputs["EXPANSION_LEVELS"]
    end


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
            vPROX_ANGLE[l,t,i] <= BigM[l]*EP[:vZ_SOS1_VAR][l,i])
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
        end)

    @expression(EP,
        eNet_Export_Flows[z = 1:Z, t = 1:T],
        sum(inputs["pNet_Map"][l, z] * EP[:vFLOW][l, t] for l in 1:L))

    @expression(EP,
        eCand_Flow[l in EXPANSION_LINES, t = 1:T], EP[:vCANDFLOW][l, t])

    @expression(EP,
        eNet_Export_Cand_Flows[z = 1:Z, t = 1:T],
        sum(inputs["pNet_Map_cand"][l, z] * EP[:vCANDFLOW][l, t] for l in EXPANSION_LINES))

    # Export and import expressions
    @expression(EP, ePowerBalanceNetExportFlows[t = 1:T, z = 1:Z],
        -eNet_Export_Flows[z, t])
    @expression(EP, ePowerBalanceCandExportFlows[t = 1:T, z = 1:Z],
        -eNet_Export_Cand_Flows[z, t])

    add_similar_to_expression!(EP[:ePowerBalance], ePowerBalanceCandExportFlows)
    add_similar_to_expression!(EP[:ePowerBalance], ePowerBalanceNetExportFlows)

    # Slack Bus angle limit
    @constraint(EP, cANGLE_SLACK[t = 1:T], vANGLE[1, t]==0)
end
