

benders_settings_path = GenX.get_settings_path(case, "benders_settings.yml")
mysetup_benders = GenX.configure_benders(benders_settings_path) 

genx_settings = GenX.get_settings_path(case, "genx_settings.yml") # Settings YAML file path
writeoutput_settings = GenX.get_settings_path(case, "output_settings.yml") # Write-output settings YAML file path
mysetup = GenX.configure_settings(genx_settings, writeoutput_settings) # mysetup dictionary stores settings and GenX-specific parameters

mysetup["DC_OPF"] = 1
myinputs = GenX.load_inputs(mysetup, case, p)
mysetup["ptdf"] = 0
mysetup["bilinear"] = 0
mysetup["disaggregate"] = 0
mysetup["unfix_slacks"] = 0
mysetup["SOS1"] = 0
mysetup = merge(mysetup,mysetup_benders);

settings_path = GenX.get_settings_path(case)    
mysetup["settings_path"] = settings_path;

# myinputs["pTrans_Max"] .*= 2
# myinputs["pTrans_Max"][[5,23,24,70,75]] .*= 1/2
#myinputs["pD"] .*= 1
# myinputs["Voll"] .*= 10

L = myinputs["L"]
L_cand = myinputs["L"]
myinputs["L_cand"] = L_cand
myinputs["Z_cand"] = myinputs["Z"]
myinputs["pNet_Map_cand"] = copy(myinputs["pNet_Map"])
myinputs["pDC_OPF_coeff_cand"] = copy(myinputs["pDC_OPF_coeff"]) .* 2
myinputs["Line_Angle_Limit"] = [6.282 for i in 1:L]
myinputs["Line_Angle_Limit_cand"] = myinputs["Line_Angle_Limit"]

# one level of expansion for each line
# equal to half of existing capacity for any given line pTrans_Max
myinputs["Line_Reinforcement_Cap_Size"] = [i for i in myinputs["pTrans_Max"]] .* 1.5
myinputs["Max_Trans_Cap"] = [2 for i in myinputs["pTrans_Max"]]
myinputs["pMax_Line_Reinforcement"] = [myinputs["Line_Reinforcement_Cap_Size"][i] * myinputs["Max_Trans_Cap"][i] for i in 1:L_cand]
myinputs["pTrans_Max_Possible"] = myinputs["pTrans_Max"] .+ myinputs["pMax_Line_Reinforcement"]

EXPANSION_LEVELS = Dict{Int, Vector}()
for i in 1:L_cand
    EXPANSION_LEVELS[i] = (0:1:myinputs["Max_Trans_Cap"][i])
end
#EXPANSION_LEVELS = [[1] for i in 1:L_cand] # needs to be a dictionary
EXPANSION_LINES = [i for i in 1:L_cand]

myinputs["EXPANSION_LINES"] = EXPANSION_LINES
myinputs["EXPANSION_LEVELS"] = EXPANSION_LEVELS

lines = collect(get_technologies(TransmissionTechnology, p));
myinputs["pC_Line_Reinforcement"] = zeros(length(lines))

scale_factor = mysetup["ParameterScale"] == 1 ? GenX.ModelScalingFactor : 1

using Random
Random.seed!(1)
for i in 1:length(lines)
    distance = 60 * rand()
    cap_val = distance * 1200
    myinputs["pC_Line_Reinforcement"][i] = cap_val * (0.044) / (1 - (1 + 0.044)^(-60))
end


myinputs["hours_per_subperiod"] = 4368
myinputs["INTERIOR_SUBPERIODS"] = [i for i in 2:myinputs["hours_per_subperiod"]]
myinputs["T"] = 4368

mysetup["NetworkExpansion"] = 1
mysetup["Benders"] = 0

# go through candidate lines and remove duplicates
line_list_cand = Vector{Tuple}()
pNet_Map_cand = myinputs["pNet_Map_cand"]
for i in 1:size(pNet_Map_cand)[1]
    from_bus = findfirst(x -> x == 1, pNet_Map_cand[i, :])
    to_bus = findfirst(x -> x == -1, pNet_Map_cand[i, :])
    push!(line_list_cand, (from_bus, to_bus))
end

idx_to_keep = []
line_sizes = []
new_line_list_cand = []
for i in 1:length(line_list_cand)
    if line_list_cand[i] in new_line_list_cand
        old_idx = findfirst(x -> x == line_list_cand[i], new_line_list_cand)
        line_sizes[old_idx] += myinputs["pTrans_Max"][i]
    else
        push!(idx_to_keep, i)
        push!(line_sizes, myinputs["pTrans_Max"][i])
        push!(new_line_list_cand, line_list_cand[i])
    end
end


myinputs["pNet_Map_cand"] = myinputs["pNet_Map_cand"][idx_to_keep, :]
myinputs["L_cand"] = length(idx_to_keep)
L_cand = myinputs["L_cand"]
myinputs["pDC_OPF_coeff_cand"] = myinputs["pDC_OPF_coeff_cand"][idx_to_keep]
myinputs["Line_Angle_Limit_cand"] = myinputs["Line_Angle_Limit_cand"][idx_to_keep]
myinputs["Line_Reinforcement_Cap_Size"] = myinputs["Line_Reinforcement_Cap_Size"][idx_to_keep]
myinputs["Max_Trans_Cap"] = myinputs["Max_Trans_Cap"][idx_to_keep]
myinputs["pMax_Line_Reinforcement"] = myinputs["pMax_Line_Reinforcement"][idx_to_keep]
myinputs["pTrans_Max_Possible"] = myinputs["pTrans_Max_Possible"][idx_to_keep]
EXPANSION_LEVELS = Dict{Int, Vector}()
for i in 1:L_cand
    EXPANSION_LEVELS[i] = (0:1:myinputs["Max_Trans_Cap"][i])
end
myinputs["EXPANSION_LEVELS"] = EXPANSION_LEVELS
myinputs["EXPANSION_LINES"] = [i for i in 1:myinputs["L_cand"]]
myinputs["pC_Line_Reinforcement"] = myinputs["pC_Line_Reinforcement"][idx_to_keep]



GenX.build_expansion_information!(myinputs)

mysetup["DC_OPF"] = 0
mysetup["IntegerInvestments"] = 0

#mz = run_zonal_model!(z_inputs, zonal_setup, optimizer)

#println("OPTIMIZING ZONAL MODEL")
#optimize!(mz)
#
#println("Objective value zonal: ", objective_value(mz))
#for v in mz[:vNEW_TRANS_CAP_DECISION_INT]
#    if value(v) > 0
#        println(v)
#    end
#end

#println("vP = ", sum(value.(mz[:vP])))
#println("vNSE = ", sum(value.(mz[:vNSE])))
#println("OverProduction = ", sum(value.(mz[:vOverProduction])))
#println("vCAP = ", sum(value.(mz[:vCAP])))

solver_monolithic = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 36000, "MIPGap" => 1e-3)

m = GenX.generate_model(mysetup, myinputs, solver_monolithic)

println("OPTIMIZING MONOLITHIC MODEL")

optimize!(m)
println("Objective value: ", objective_value(m))

for v in m[:vNEW_TRANS_CAP]
    if value(v) > 0
        println(v)
    end
end

println("vP = ", sum(value.(m[:vP])))
println("vNSE = ", sum(value.(m[:vNSE])))
println("OverProduction = ", sum(value.(m[:vOverProduction])))
println("vCAP = ", sum(value.(m[:vCAP])))
