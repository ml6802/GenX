using GenX, JLD2, Gurobi

#load in myinputs, mysetup
# build JuMP model
data = JLD2.load((@__DIR__)*"/inputs_and_settings.jld2")

myinputs = data["inputs"]
mysetup = data["setup"]

# add candidate data
L_cand = myinputs["L"]
myinputs["L_cand"] = L_cand
myinputs["pNet_Map_cand"] = copy(myinputs["pNet_Map"])
myinputs["pDC_OPF_coeff_cand"] = copy(myinputs["pDC_OPF_coeff"])
myinputs["LineAngle_Limit"] = [6.282 for i in 1:L_cand]
myinputs["Line_Angle_Limit_cand"] = myinputs["Line_Angle_Limit"]

# one level of expansion for each line
# equal to half of existing capacity for any given line pTrans_Max
myinputs["Line_Reinforcement_Cap_Size"] = [i for i in myinputs["pTrans_Max"]]
myinputs["Max_Trans_Cap"] = [1 for i in myinputs["pTrans_Max"]]
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

nlines = 120
myinputs["pC_Line_Reinforcement"] = zeros(nlines)
using Random
Random.seed!(1)
for i in 1:nlines
    distance = 60 * rand()
    size_mw = myinputs["Line_Reinforcement_Cap_Size"][i]
    myinputs["pC_Line_Reinforcement"][i] = distance * size_mw * 2#000
end

solver = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 600)



EP = GenX.generate_model(mysetup, myinputs, solver)


#= #to instead run with Benders: 

myinputs_decomp = GenX.separate_inputs_subperiods(myinputs);
    
benders_inputs = GenX.generate_benders_inputs(mysetup,myinputs,myinputs_decomp)
    println(mysetup)

planning_problem, planning_sol,operational_sol, LB_hist,UB_hist,cpu_time,feasibility_hist, build_decisions  = GenX.benders(benders_inputs,mysetup,myinputs);
=#

