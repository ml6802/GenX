ENV["GENX_PRECOMPILE"] = "false"

using Revise
using JuMP
using GenX
using PowerSystemsInvestmentsPortfolios
using Gurobi
using TimeSeries
using CSV
using DataFrames
using Dates
using InfrastructureSystems
using PowerSystems
const PSIP = PowerSystemsInvestmentsPortfolios
const IS = InfrastructureSystems
const PSY = PowerSystems
using Plots
import Pkg
using Distributed, ClusterManagers

# Pkg.activate("/home/ml6802/GenX")
# include("/home/ml6802/GenX/src/GenX.jl")

include((@__DIR__)*"/load_portfolio.jl")
include((@__DIR__)*"/../convert_input_dict_reconductoring.jl")

p.internal.ext["Rep_Periods"] = 1
p.internal.ext["Timesteps_per_Rep_Period"] = 168
p.internal.ext["hours_per_subperiod"] = 168
p.internal.ext["sub_weights"] = [8784/52 for i in 1:1]
#p.internal.ext["sub_weights"] = [8784/2190 for i in 1:1]
# p.internal.ext["Timesteps_per_Rep_Period"] = 3528
# p.internal.ext["hours_per_subperiod"] = 3528
# p.internal.ext["sub_weights"] = [8784/2 for i in 1:1]
# p.internal.ext["sub_weights"] = [8784/2 for i in 1:1]
# p.internal.ext["sub_weights"] = [8784/2 for i in 1:1]

buses = collect(get_components(Bus, p.base_system))
zones = []
zone_map = Dict{Int, Int}()
for i in 1:length(buses)
    if buses[i].area.name == "area1"
        push!(zones, 1)
        zone_map[i] = 1
    elseif buses[i].area.name == "area2"
        push!(zones, 2)
        zone_map[i] = 2
    elseif buses[i].area.name == "area3"
        push!(zones, 3)
        zone_map[i] = 3
    else
        error()
    end
end

benders_settings_path = GenX.get_settings_path(case, "benders_settings.yml")
mysetup_benders = GenX.configure_benders(benders_settings_path) 

genx_settings = GenX.get_settings_path(case, "genx_settings.yml") # Settings YAML file path
writeoutput_settings = GenX.get_settings_path(case, "output_settings.yml") # Write-output settings YAML file path
mysetup = GenX.configure_settings(genx_settings, writeoutput_settings) # mysetup dictionary stores settings and GenX-specific parameters
mysetup["ParameterScale"] = 0

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

using Random
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

myinputs["CAN_RETIRE_LINES"] = CAN_RETIRE_LINES
myinputs["CANNOT_RETIRE_LINES"] = CANNOT_RETIRE_LINES
myinputs["RECONDUCTOR_LINES"] = RECONDUCTOR_LINES
myinputs["existing_to_cand_map"] = existing_to_cand_map

myinputs["hours_per_subperiod"] = 168
myinputs["INTERIOR_SUBPERIODS"] = [i for i in 2:myinputs["hours_per_subperiod"]]
myinputs["T"] = 168


mysetup["NetworkExpansion"] = 1
mysetup["Benders"] = 0

#myinputs["pTrans_Max"][[5, 23,24, 70, 75]] .*= 1.25

#optimize!(m)


# myinputs["L_cand"] = 10
# myinputs["L"] = myinputs["L_exist"]
# myinputs["pNet_Map"] = myinputs["pNet_Map"][1:130, :]
# myinputs["CANDIDATE_LINES"] = [i for i in 121:130]
# myinputs["CAN_RETIRE_LINES"] = [i for i in 1:10]
# myinputs["CANNOT_RETIRE_LINES"] = [i for i in 11:120]
# myinputs["RECONDUCTOR_LINES"] = [i for i in 11:120]

for i in 1:10
    myinputs["existing_to_cand_map"][i] = 120 + i
end


mysetup["bilinear"] = 0
optimizer = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 30, "MIPGap" => 1e-4)
#m = GenX.generate_model(mysetup, myinputs, optimizer)

# for i in 121:240
#     fix(m[:vNEW_TRANS_CAP_DECISION_INT][i, 1], 0)
# end
#optimize!(m)




# benders_settings_path = GenX.get_settings_path(case, "benders_settings.yml")
# mysetup_benders = GenX.configure_benders(benders_settings_path) 

# genx_settings = GenX.get_settings_path(case, "genx_settings.yml") # Settings YAML file path
# writeoutput_settings = GenX.get_settings_path(case, "output_settings.yml") # Write-output settings YAML file path
# mysetup = GenX.configure_settings(genx_settings, writeoutput_settings) # mysetup dictionary stores settings and GenX-specific parameters

# mysetup["DC_OPF"] = 1
# mysetup["ptdf"] = 0
# mysetup["bilinear"] = 1
# mysetup["disaggregate"] = 0
# mysetup["unfix_slacks"] = 0
# mysetup["SOS1"] = 0
# mysetup = merge(mysetup,mysetup_benders);

# settings_path = GenX.get_settings_path(case)    
# mysetup["settings_path"] = settings_path;
# mysetup["NetworkExpansion"] = 1
# mysetup["Benders"] = 1
# #mysetup["BD_integer_routine"] = 1
# # mysetup["BD_Stab_Method"] = "int_level_set"

# myinputs_decomp = GenX.separate_inputs_subperiods(myinputs);
# # nodal_setup_Benders = deepcopy(nodal_setup)
# # nodal_setup_Benders["Benders"] = 1
# benders_inputs = GenX.generate_benders_inputs(mysetup,myinputs,myinputs_decomp)
# planning_problem1, planning_sol1, operational_sol1, LB_hist1,UB_hist1, cpu_time,feasibility_hist1, build_decisions1  = GenX.benders(benders_inputs,mysetup,myinputs);


# mysetup["bilinear"] = 1
# optimizer = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 300, "MIPGap" => 1e-4)
# mb = GenX.generate_model(mysetup, myinputs, optimizer)

# for i in 121:240
#     fix(m[:vNEW_TRANS_CAP_DECISION_INT][i, 1], 0)
# end
# optimize!(mb)


# vflows = value.(m[:vFLOW])
# for i in 1:120
#     line_flows = vflows[i, :]
#     if maximum(line_flows) == myinputs["pTrans_Max"][i] || (-minimum(line_flows) == myinputs["pTrans_Max"][i])
#         println(maximum(line_flows), "   ", minimum(line_flows))
#         println(i)
#     end
# end



mysetup["bilinear"] = 0
mysetup["zonal"] = "waterflow" # set for waterflow or dcopf
mysetup["nodal"] = "dcopf" # set for waterflow or dcopf
## stuff from zonal_to_nodal_solve.jl
if !(haskey(mysetup, "ptdf"))
    mysetup["ptdf"] = 0
end
if !(haskey(mysetup, "disaggregate"))
    mysetup["disaggregate"] = 0
end
if !(haskey(mysetup, "bilinear"))
    mysetup["bilinear"] = 0
end
if !(haskey(mysetup, "SOS1"))
    mysetup["SOS1"] = 0
end
if !(haskey(mysetup, "unfix_slacks"))
    mysetup["unfix_slacks"] = 0
end
if !(haskey(mysetup, "tight_bigM"))
    mysetup["tight_bigM"] = false
end
z_inputs = build_zonal_inputs(myinputs, zone_map, 3)

solver = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 400, "MIPGap" => 1e-4)
###### ZONAL ######
zonal_setup = deepcopy(mysetup)
#zonal_setup["unfix_slacks"] = 1
#zonal_setup["DC_OPF"] = 1

optimizer = solver
###### ZONAL ######
zonal_setup["unfix_slacks"] = 0
zonal_setup["NetworkExpansion"] = 1
zonal_setup["IntegerInvestments"] = 1
zonal_setup["DC_OPF"] = 0



vflow1 = [379.00063811621203
307.81932601591916
194.85404549607745
209.0280046538776
394.09242124234925
363.65875486292396
366.72351381827116
352.4872705543089
331.71600750210155
318.0984294145437
309.43162253257583
303.67688409085304
300.34950432484015
297.33017125182846
297.1970932477865
299.4083314585182
312.07015542637805
311.8525929926383
308.67517418090983
319.7995307087872
316.64573819313773
306.8945163383162
298.52304405135646
300.04878916806535
301.74326488277757
181.15997292732482
308.4787036647955
316.0518833583137
242.1559763634433
351.6223076942864
352.9603478669785
338.1767408448759
321.45972132094323
311.3409493553477
302.5077283457392
297.8801596781241
295.0035862240147
240.8440333487515
290.31644418883775
293.013978440388
305.3433530554041
292.0808675407958
299.9864443464694
315.3519500665003
310.9673873527022
302.41212807007753
295.7113298263806
363.7643037327341
298.7430500836713
169.3547813162147
302.2219178829346
309.17182971365435
324.29860080779986
344.8458070217073
347.3211228798185
336.1431859037897
319.48545520266157
311.2520844831529
303.8439861392951
297.0090857678938
249.93083082905048
291.51978911194806
289.9561471602242
291.23440326988157
302.25985483139436
299.159944836367
312.5263279514277
309.79045528025495
309.8509708811346
305.43547427903945
299.62804884831667
297.40362165532724
378.7659928985702
301.23367028261566
305.31219784084
309.32585356097445
394.17361359812026
328.81757378245027
337.17287078236564
340.7197489205672
334.092723782764
264.05185954913304
319.0390283943934
312.83047722408503
308.31605925816496
305.6386294444451
305.75591963872
205.55192038958285
361.58854499598147
329.2519506362835
319.848326627701
316.7008573045032
311.8853443888711
304.7066453160917
299.1056296954257
365.3924244469699
300.3606297603669
302.04385453081795
304.55800412103747
309.10479330598946
396.9426096145405
328.4639730761311
338.8500542949282
343.43957616588614
337.10112835833036
329.8370580375538
320.86591776123737
315.1195558266901
310.3269376641522
378.24174848354846
306.63385788042433
309.44921416868533
323.4324639805636
334.86334885823317
330.269532550656
326.4089430864133
317.85397239195834
306.8849952451146
357.1367913250351
300.2769962449124
303.59101830535917
305.9169144739701
310.85975859064206
401.76823616341915
340.81325588872687
369.5038788793047
374.7759281260917
352.90603058744773
331.8914025227375
319.07117106037117
309.129466177552
302.0740274533082
297.42177098979505
293.0955227188256
292.9070938058867
295.92165625832695
290.37237955488126
318.9971810234931
323.55969154957063
329.2954289755628
323.272464874893
310.57800090511114
304.54590440358834
304.43843399086813
386.3212015558729
313.3056907474131
318.4338446603649
326.8628736090393
349.3004138134472
378.04999811544417
382.3617161352572
359.2328328458227
334.6484426494676
319.6298050299031
306.96707211372313
300.44791784986774
298.4075385889205
292.82083787478905
290.83919968116186
294.38162947529213
309.4310863796827
325.6296915495718
330.1852943791123
329.832120960883
320.6697098503746
311.60942456068256
304.1466390636042
235.56264552262508]
vflow2 = [-121.34059633502721
24.95483532152852
-29.78993221603119
-35.642261726520616
-120.81158419661313
-59.964407713657295
-84.0472548315123
-73.32607640352711
-55.27702396382415
-44.56491718381264
-35.99747562973994
-29.88522014884859
-24.10028124587444
-19.75402543860804
-17.51920292832881
-18.59041856930955
-42.539954525143116
-83.41397160220113
-75.12605995518537
-74.68861925796105
-60.876985098882884
-31.98927482371613
-0.7716450899992537
17.136114891568468
26.834572400862186
-24.211022094967035
28.019946614284237
19.415284596534462
-44.002527716220044
-42.32949844983915
-63.868711858370716
-50.83172343843643
-38.91809503288607
-33.35845811653925
-28.4890115467918
-27.037207256814497
-24.515974684951715
-43.969952817107014
-21.005739541498315
-20.69735686039536
-41.35759238732766
-81.84980862678127
-74.10719639568907
-67.43332219531808
-52.026949591511595
-24.274623395312716
6.015437336812823
-105.50357963968382
32.98352431254699
-17.3849004153129
38.087813798318024
30.31384935950979
8.228066309680685
-30.301200014020623
-52.78641007354895
-45.00995331471569
-36.94575832755723
-33.73626381831474
-32.184273170047504
-29.237781660469892
-46.304165065064296
-24.753818615830028
-22.62610701257705
-21.038254536340958
-28.8697556024934
-77.36309000580029
-63.2212350906739
-50.29964144513153
-38.82582237037278
-20.014526705923117
4.226797120727269
22.73628617366208
-118.41587637966148
36.986336587434096
35.994381105799164
33.363068753815924
-124.60435959943376
1.795625827509582
-15.823129326697625
-20.802299801349847
-21.18694391941915
-45.91708935049306
-15.055196914267384
-7.755394232010417
-2.1538105846921383
5.1631372253507095
7.380102034650463
-39.28350780363854
-95.86262866378084
-56.18839855346394
-49.655876120239924
-40.14967536965918
-26.793693527350285
-7.964596421773024
12.321106463440145
-102.8455561527552
33.12315406695103
36.749065527378065
36.711803163149426
32.14834967978493
-132.23261558179206
4.310581762883714
-13.492763870936699
-16.929243451020483
-13.833176970885148
-9.924976502585537
-1.9416086084608537
3.664568910459991
9.702489851418676
-122.31203997213487
14.617951586258755
12.090553962506903
-14.540584692065494
-58.505663327031755
-59.86319759405052
-52.29324983760533
-34.503849563564415
-8.533029025928755
-93.37856585342271
28.90597948452401
34.44199680014833
35.30726478485087
31.940905843145686
-137.33160662052973
-12.085708794637469
-62.59197987893647
-91.64834054854325
-70.52318304132098
-51.403782452094106
-42.08213794382047
-35.66282123904915
-29.945195799763184
-22.34786595403591
-16.05315915281065
-15.802641954576444
-16.843425276950427
-50.10072657747784
-86.25649441578153
-79.33032840721252
-77.51077017015484
-65.54305741841834
-35.25207005805083
-4.551299787766283
12.450074220202282
-125.34182847024935
21.588639106650106
18.019073093429995
6.547781874855076
-27.17964290432417
-77.93004980136323
-106.22863996909848
-83.15754014666612
-57.485539353106375
-42.33575905421554
-25.559935134314628
-26.076984039845627
-23.581233634184372
-15.774208628646932
-13.098966126620894
-15.397236007091749
-40.08628415360613
-82.31273715481868
-77.90751446740049
-75.86686854626592
-63.37534256689571
-36.3588438138911
-4.558407557580296
-22.17970356597135]
vflow3 = [-50.66422791216411
48.47574482371181
25.581493239338215
20.571238946687345
-50.79613339618999
-5.285820723936581
-16.78667716111886
-10.311833173155549
0.98206394871562
8.733821208884024
12.540535186292573
16.254116208661458
20.37627217661509
22.410989217889096
23.634787077890223
23.24186996123035
8.888964646582792
-5.144863260349837
1.6973651244621237
0.09752066605085474
8.126541465860555
23.907439243753515
39.548101757376116
46.88858099590175
50.737259502246275
30.319865551710564
50.044209791008825
44.22765053089961
13.356961440425948
6.914660476282393
-2.3626664445463916
5.1180062940916855
12.456185287536186
15.400398330246503
18.143539198951885
18.5727461508518
19.308938712959048
12.211571353678778
20.842048820964465
20.664441156845896
11.365131544267399
-4.2206811281446335
1.3722804837869376
4.884103120665998
13.869696016745934
28.45202195983893
44.04290190280847
-37.41645753186276
55.228029428348805
36.2488172909716
57.196604004174446
52.08976770941979
38.30108801216102
16.008251768265154
6.416262260370502
9.734057141174674
14.588462567894453
15.923072594185442
16.07424498685475
17.0447673892279
10.274048616466928
18.28395860280898
19.38171779030847
19.977017184432384
10.357485883282152
-3.5386206970037506
5.595026489933559
13.95393998720499
19.895299151691688
30.0289262393469
43.1512358569056
51.69829705917948
-48.061447432916566
57.55605927703391
56.46891022799514
54.39505694096442
-53.2771751219085
35.215882910301275
25.051441745316083
19.906748667278407
20.314003397803845
11.353652138397365
23.814898186692403
27.030368484901715
31.75248672062662
35.97598252568639
37.13360267289647
16.98983662551268
-30.295557305213833
8.70479500688424
13.425392192393247
18.77676563754096
26.101102707327982
36.5719866041145
47.411127248493244
-35.09957692333552
55.893967674691226
57.14648092416235
56.01259428345463
52.81762449375685
-59.57339376694051
35.433214808876755
24.482818305383034
20.432039160699674
23.52723673886294
27.02868701537591
32.508147993345574
35.795962196708615
39.56477365246894
-51.630998905742445
41.781309742523604
39.996023508777625
26.038238526464966
6.523221492869084
6.671874384445516
11.147383398725594
20.690701311706107
35.150749061222086
-27.412677056804625
53.16963163130049
55.157455839602676
55.07365201080529
52.054967799427345
-63.8802158213187
23.338848117828093
-7.221003351428692
-21.22326754728965
-8.405892999779894
4.676605525441687
10.262099082183
14.69098729710663
18.00827997741976
21.092519751507666
23.154250694057964
24.04567430512634
22.967337310500625
7.083408899886251
-7.716979760767799
-1.502538657880109
-2.4011137023820766
6.987775490017839
24.831500980577857
38.928533623468866
46.102712842542246
-54.0014189983811
46.3182402617407
43.68927339320999
36.19469243153776
14.861140149154721
-15.016283502650595
-28.86550530640136
-14.209262409618077
1.0054649786638947
9.357814084600477
12.799547112767414
19.861676018297885
20.33674204125873
24.513309920558413
25.260561983861976
23.80163456821674
12.095690098602518
-6.011560728615336
-5.034686863163131
-1.5065497589964707
9.399627955885194
24.69741781598782
39.551800585069714
31.904562041541]
vflow4 = [-32.7322389916618
41.94969147859808
13.715386519669437
9.610358301379847
-36.91521783331683
-6.99763472646066
-17.677999301160867
-12.44637905525343
-2.774733878337713
3.9259499881118245
6.862975285887217
10.050738556332817
13.886522896158112
15.6310972153899
16.802209733271297
16.583494123707396
3.4530203388233076
-9.905273049724599
-3.9995436852111084
-3.5239547267395324
4.10231550677463
18.676044100770923
33.190601927171315
40.12106178529905
43.8244958572144
17.567479294667805
43.45768899276902
38.23278687441723
4.42009062725532
4.220457088786361
-4.377024596440947
1.8996289930583998
8.003437501650069
10.222659487241344
12.337767377358887
12.423796270310163
12.890488235344833
3.097859926273088
14.03761790865633
14.015798809626403
6.035524293456149
-10.135525028377117
-4.436476584741513
1.116347651353749
9.554622931179551
22.993456519458277
37.48322229721066
-22.246984340015956
48.06932517400037
22.750010038845858
50.121486841445176
45.56205252729376
33.08247993583552
12.790631336366914
3.9589232990036294
6.351230340766961
10.036930602547727
10.779894768555778
10.381428530344238
10.867508442146232
1.6172205256202687
11.480725868958473
12.41829169041307
13.063088285205254
3.8196707332485857
-8.694747105733825
1.0493689757481093
9.091791004876029
14.970887518250493
24.43802261981159
36.65579034835264
44.628884690364316
-29.730183539318034
50.092459922166995
49.20830562515846
47.38671117925662
-34.70362243749281
29.96448622403841
20.632872224610765
15.650737061511677
15.727161043672936
3.3185272961023315
18.22738554434727
20.931308783539407
25.42811119808971
29.352237152975817
30.590268570295848
5.623268643520589
-22.021440137318848
5.049292764781967
9.412933939961931
14.406672743338959
21.140610129117476
30.863919680739286
40.92204903422203
-20.194459170367566
48.80007655642976
50.05701217328942
48.992091530228095
46.12867769935053
-39.304139462960734
30.37955898355392
20.399057711370915
16.551248604874672
19.293097678053527
22.39566684090562
27.209810015864264
30.053949202111653
33.41206306736558
-34.84016911284675
35.269057077805655
33.59897706064919
20.999925607907926
3.1630742691120304
3.1040953341332624
7.22082443998454
16.101269348359438
29.44583199537533
-15.364373913287295
46.197290943298526
48.20432618873804
48.217929200241315
45.534082973109776
-42.73894591398573
19.335863880212628
-8.565117511628898
-21.27618989013797
-10.476658481868867
1.081231586360616
5.7305577421985845
9.470124471542931
12.238074798800994
14.802691563320536
16.396856777643052
17.303173171349954
16.410059409365658
1.0297833176402378
-11.487549729566638
-5.846043733293584
-5.25448123578758
3.6998222660573674
20.227492822871113
33.1850380536398
39.88765371112015
-35.5311526664791
40.1847646969245
37.92191528192279
31.12849423595287
11.727166157847023
-15.442403692604216
-27.76942970130625
-15.533041868753742
-2.289951710567152
4.836052681532976
6.849437165556424
13.907342440831599
14.141653622106446
17.811049891521634
18.34272680430115
17.147714143468875
6.990070377230552
-9.008776016109664
-7.959887553428814
-4.340983663657482
5.995034170802398
20.22008284813171
33.82187830544353
22.480861071017557]
vflow5 = [500.0
500.0
315.7818452387098
325.8986309898261
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
483.84129393687545
487.6883071010942
500.0
500.0
500.0
500.0
500.0
500.0
307.30237080563575
500.0
500.0
358.9860662916244
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
421.814762659303
500.0
500.0
500.0
466.3347886359286
480.9842912031006
500.0
500.0
500.0
500.0
500.0
500.0
297.29183372944215
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
430.1688520596275
500.0
500.0
500.0
500.0
476.07775671320087
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
403.6823693760133
500.0
500.0
500.0
500.0
500.0
338.17343318618634
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
467.53096428859465
491.27430952607733
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
500.0
387.3037434507221]

mz = run_zonal_model!(z_inputs, zonal_setup, optimizer)


vflows = [vflow1, vflow2, vflow3, vflow4, vflow5]
vCAP_builds = [47, 60, 72, 98, 129, 132]
#vCAP_sizes = [1402.2309, 386.694, 1402.2309, 386.694, 401.5993, 401.5993]
vCAP_sizes = [1301.1189,425.529167,1301.1189,425.529167,411.947196,411.947196]
vCAP_names = ["CT36", "CT35", "CC33", "CC32", "CT34", "CC31"]

for i in 1:5
    for (j, v) in enumerate(mz[:vFLOW][i, :])
        fix(v, vflows[i][j], force = true)
    end
end

for (i, v) in enumerate(vCAP_builds)
    for (j, r) in enumerate(myinputs["RESOURCES"])
        if parent(r)[:resource] == vCAP_names[i]
            fix(mz[:vCAP][j], vCAP_sizes[i], force = true)
            println(j)
            break
        end
    end
end

# for i in 6:10
#     fix(mz[:vNEW_TRANS_LINES][i, 1], 0, force = true)
# end

optimize!(mz)

println("VNSE = ", sum(value.(mz[:vNSE])))
println("Num builds = ", sum(value.(mz[:vNEW_TRANS_LINES])))
println("vCAP = ", sum(value.(mz[:vCAP])))
println("voverproduction = ", sum(value.(mz[:vOverProduction])))



optimizer = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 60, "MIPGap" => 5e-3)

n2z_map = zone_map
num_zones = 3
# build the nodal inputs
n_inputs = build_nodal_inputs(myinputs, n2z_map, num_zones)

nodal_setup = deepcopy(mysetup)
nodal_setup["DC_OPF"] = 1
nodal_setup["bilinear"] = 0
nodal_setup["unfix_slacks"] = 0
nodal_setup["NetworkExpansion"] = 1
nodal_setup["IntegerInvestments"] = 1

# for (key, value) in z_inputs["interzonal_node_flows"]
#     z_inputs["interzonal_node_flows"][key] = zeros(168)
# end

# add to the nodal inputs the interzonal transmission time series
nts = get_interzonal_node_time_series(z_inputs, mz)
cap_decisions = get_capacity_solutions(z_inputs, mz)
z_inputs["interzonal_node_flows"] = nts
z_inputs["capacity_decisions"] = cap_decisions

add_interzonal_data!(z_inputs, n_inputs)

# for i in 1:3
#     delete!(n_inputs[i], "zonal_capacity_decision")
# end
println("RUNNING MODEL 1")
nodal_setup["bilinear"] = 0
nodal_setup["unfix_slacks"] = 0
# solve nodal models
# m1 = GenX.generate_model(nodal_setup, n_inputs[1], optimizer)
m1 = build_nodal_resolution_model(nodal_setup, n_inputs[1], optimizer)

optimize!(m1)

# obj_func_a = objective_function(m1)
# obj_func_b = objective_function(m1b)
# for i in 1:length(n_inputs[1]["l2l_map_cand"])
#     vara = m1[:vNEW_TRANS_CAP_DECISION_INT][i,1]
#     varb = m1b[:vNEW_TRANS_CAP_DECISION_INT][i, 1]
#     value_a = value(m1[:vNEW_TRANS_CAP_DECISION_INT][i, 1])
#     value_b = value(m1b[:vNEW_TRANS_CAP_DECISION_INT][i, 1])
    

#     if value_a == value_b
#         vcand_flow_a = [value(m1[:vCANDFLOW][i, k, 1]) for k in 1:myinputs["T"]]
#         vcand_flow_b = [value(m1b[:vCANDFLOW][i, k, 1]) for k in 1:myinputs["T"]]
#         println("max a = ", maximum(vcand_flow_a), "  max b = ", maximum(vcand_flow_b))
#     end
# end


println("vcap in zone 1: ", sum(value.(m1[:vCAP])))
println("new transmission in zone 1: ", sum(value.(m1[:vNEW_TRANS_CAP_DECISION_INT])))

println("RUNNING MODEL 2")
# m2 = GenX.generate_model(nodal_setup, n_inputs[2], optimizer)
m2 = build_nodal_resolution_model(nodal_setup, n_inputs[2], optimizer)
optimize!(m2)

println("vcap in zone 2: ", sum(value.(m2[:vCAP])))
println("new transmission in zone 2: ", sum(value.(m2[:vNEW_TRANS_CAP_DECISION_INT])))

# obj_func = objective_function(m2)
# obj_val = [0.]
# for v in keys(obj_func.terms)
#     if value(v) != 0 && !occursin("Fuel", name(v))
#         println(v, "   ", value(v), "  ", obj_func.terms[v])
#         obj_val[1] += value(v) * obj_func.terms[v]
#     end
# end




println("RUNNING MODEL 3")

# m3 = GenX.generate_model(nodal_setup, n_inputs[3], optimizer)
m3 = build_nodal_resolution_model(nodal_setup, n_inputs[3], optimizer)

optimize!(m3)

println("vcap in zone 3: ", sum(value.(m3[:vCAP])))
println("new transmission in zone 3: ", sum(value.(m3[:vNEW_TRANS_CAP_DECISION_INT])))

println("Zonal objective is : ", objective_value(mz))
println("Nodal objective is : ", objective_value(m1) + objective_value(m2) + objective_value(m3))
println("Zonal NSE is : ", sum(value(mz[:vNSE])))
println("Nodal NSE is : ", sum(value(m1[:vNSE])) + sum(value(m2[:vNSE])) + sum(value(m3[:vNSE])))

println("Zonal Builds: ", sum(value(mz[:vNEW_TRANS_LINES])))
println("Nodal Builds: ", sum(value(m1[:vNEW_TRANS_CAP_DECISION_INT])) + sum(value(m2[:vNEW_TRANS_CAP_DECISION_INT])) + sum(value(m3[:vNEW_TRANS_CAP_DECISION_INT])))



# plot results
using PlasmoData, PlasmoDataPlots
fadjlist = z_inputs["adj_list"]
dg = DataGraph{Int, Any, Any, Any, Matrix{Any}, Matrix{Any}}()
for i in 1:73
    add_node!(dg, i)
    if zone_map[i] == 1
        add_node_data!(dg, i, 1, "partition")
        add_node_data!(dg, i, "red", "color")
    elseif zone_map[i] == 2
        add_node_data!(dg, i, 2, "partition")
        add_node_data!(dg, i, "orange", "color")
    else
        add_node_data!(dg, i, 3, "partition")
        add_node_data!(dg, i, "blue", "color")
    end
    #add_node_data!(dg, i, part9[i], "partition_metis")
    #add_node_data!(dg, i, my_colors[part9[i]], "color")
    add_node_data!(dg, i, 6, "nodesize")
end
for (src, dst) in fadjlist
    add_edge!(dg, src, dst)
    add_edge_data!(dg, src, dst, "black", "new_build")
    add_edge_data!(dg, src, dst, 2, "linewidth_new_build")
    add_edge_data!(dg, src, dst, "black", "retirement")
    add_edge_data!(dg, src, dst, 2, "linewidth_retirement")
    add_edge_data!(dg, src, dst, "black", "reconductored")
    add_edge_data!(dg, src, dst, 2, "linewidth_reconductor")
    add_edge_data!(dg, src, dst, "black", "status")
    add_edge_data!(dg, src, dst, 2, "linewidth_status")
end



plot_graph(dg, nodecolor = get_node_data(dg, "color"), nodesize = 6, xdim = 500, ydim = 500, save_fig = false, linewidth=2, linecolor = "black", fig_name = (@__DIR__)*"/zonal_system.png")
add_node_data!(dg, 13, -0.52, "x_positions")
add_node_data!(dg, 13, 0.16, "y_positions")
plot_graph(dg, nodecolor = get_node_data(dg, "color"), nodesize = 6, xdim = 500, ydim = 500, save_fig = false, linewidth=2, linecolor = "black", fig_name = (@__DIR__)*"/zonal_system.png")

plot_graph(dg, nodecolor = "grey", nodesize = 6, xdim = 500, ydim = 500, save_fig = false, linewidth=2, linecolor = "black", fig_name = (@__DIR__)*"/zonal_system_plain.png")



l2z_map = z_inputs["l2z_map"]
retire_lines = [z_inputs["existing_to_cand_map"][j] for j in z_inputs["CAN_RETIRE_LINES"]]
for k in keys(l2z_map)
    new_line = l2z_map[k]
    #add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "white", "zonal_line")
    if new_line in z_inputs["CANDIDATE_LINES"]
        if value(mz[:vNEW_TRANS_LINES][new_line, 1]) == 1
            add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "red", "new_build")
            add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], 5, "linewidth")
            if new_line in retire_lines
                add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "orange", "status")
                add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], 5, "linewidth_status")
            else
                add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "red", "status")
                add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], 5, "linewidth_status")
            end
        end
    end
end


models = [m1, m2, m3]
for i in 1:num_zones
    n_input = n_inputs[i]
    l2l_map = n_input["l2l_map"]
    model = models[i]
    retire_lines = [n_input["existing_to_cand_map"][j] for j in n_input["CAN_RETIRE_LINES"]]
    for k in keys(l2l_map)
        old_line = k
        new_line = l2l_map[k]
        if new_line in n_input["CANDIDATE_LINES"]
            if value(models[i][:vNEW_TRANS_CAP_DECISION_INT][new_line, 1]) == 1
                add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "red", "new_build")
                add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], 5, "linewidth")
                if new_line in retire_lines
                    add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "orange", "status")
                    add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], 5, "linewidth_status")
                else
                    add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "red", "status")
                    add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], 5, "linewidth_status")
                end
            end
        end
        if new_line in n_input["RECONDUCTOR_LINES"]
            if value(model[:vRECONDUCTOR_SLACK_LOW][new_line]) > 0
                if get_edge_data(dg, fadjlist[k][1], fadjlist[k][2], "status") == "red"
                    add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "purple", "status")
                    add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], 5, "linewidth_status")
                else
                    add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "teal", "status")
                    add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], 5, "linewidth_status")
                end
            end
        end
    end
end

for i in 1:num_zones
    n_input = n_inputs[i]
    n2n_map = n_input["n2n_map"]
    n2n_map_back = Dict()
    for j in keys(n2n_map)
        n2n_map_back[n2n_map[j]] = j
    end
    vcap_nodes = models[i][:vCAP].axes[1]
    for j in vcap_nodes
        println(j)
        if value(models[i][:vCAP][j]) > 0
            resource = n_input["RESOURCES"][j]
            println(parent(resource)[:resource])
            genx_zone = parent(resource)[:zone]
            node = n2n_map_back[genx_zone]
            add_node_data!(dg, node, "black", "color")
            add_node_data!(dg, node, 10, "nodesize")
            println(node)
        end
    end
end



plot_graph(dg, nodecolor = get_node_data(dg, "color"), nodesize = get_node_data(dg, "nodesize"), xdim = 500, ydim = 500, linewidth = get_edge_data(dg, "linewidth_status"), linecolor = get_edge_data(dg, "status"), save_fig = false, fig_name = (@__DIR__)*"/zonal_nodal_builds_RTS_repweek_benders.png")














a=1





#=

benders_settings_path = GenX.get_settings_path(case, "benders_settings.yml")
mysetup_benders = GenX.configure_benders(benders_settings_path) 

genx_settings = GenX.get_settings_path(case, "genx_settings.yml") # Settings YAML file path
writeoutput_settings = GenX.get_settings_path(case, "output_settings.yml") # Write-output settings YAML file path
mysetup = GenX.configure_settings(genx_settings, writeoutput_settings) # mysetup dictionary stores settings and GenX-specific parameters

mysetup["DC_OPF"] = 1
mysetup["ptdf"] = 0
mysetup["bilinear"] = 1
mysetup["disaggregate"] = 0
mysetup["unfix_slacks"] = 0
mysetup["SOS1"] = 0
mysetup = merge(mysetup,mysetup_benders);

settings_path = GenX.get_settings_path(case)    
mysetup["settings_path"] = settings_path;
mysetup["NetworkExpansion"] = 1
mysetup["Benders"] = 1
#mysetup["BD_integer_routine"] = 1
# mysetup["BD_Stab_Method"] = "int_level_set"


myinputs_decomp = GenX.separate_inputs_subperiods(n_inputs[1]);
# nodal_setup_Benders = deepcopy(nodal_setup)
# nodal_setup_Benders["Benders"] = 1
benders_inputs = GenX.generate_benders_inputs(mysetup,n_inputs[1],myinputs_decomp)
planning_problem1, planning_sol1, operational_sol1, LB_hist1,UB_hist1, cpu_time,feasibility_hist1, build_decisions1  = GenX.benders(benders_inputs,mysetup,n_inputs[1]);

# vals = [0.]
# for k in keys(planning_sol1.values)
#     if occursin("vNEW_TRANS_CAP", k)
#         vals[1] += planning_sol1.values[k]
#     end
# end

# df = DataFrame()
# df[!, "UB"] = UB_hist2
# df[!, "LB"] = LB_hist
# df[!, "TIME"] = cpu_time

#CSV.write((@__DIR__)*"/1week_zone2_with_retirements_bilinear_only.csv", df)


myinputs_decomp = GenX.separate_inputs_subperiods(n_inputs[2]);
# nodal_setup_Benders = deepcopy(nodal_setup)
# nodal_setup_Benders["Benders"] = 1
benders_inputs = GenX.generate_benders_inputs(mysetup,n_inputs[2],myinputs_decomp)
planning_problem2, planning_sol2, operational_sol2, LB_hist2,UB_hist2, cpu_time,feasibility_hist2, build_decisions2  = GenX.benders(benders_inputs,mysetup,n_inputs[2]);

myinputs_decomp = GenX.separate_inputs_subperiods(n_inputs[3]);
# nodal_setup_Benders = deepcopy(nodal_setup)
# nodal_setup_Benders["Benders"] = 1
benders_inputs = GenX.generate_benders_inputs(mysetup,n_inputs[3],myinputs_decomp)
planning_problem3, planning_sol3, operational_sol3, LB_hist,UB_hist3, cpu_time,feasibility_hist3, build_decisions3  = GenX.benders(benders_inputs,mysetup,n_inputs[3]);


#if UB_hist1[end] < objective_value(m1)
    #l2l_map = n_inputs[1]["l2l_map_rev"]
    #for k in keys(l2l_map)
        #old_line = k
        #new_line = l2l_map[k]
        #if new_line in n_inputs[1]["CANDIDATE_LINES"]
        for new_line in n_inputs[1]["CANDIDATE_LINES"]
            println(new_line)
            val1 = planning_sol1.values["vNEW_TRANS_CAP_DECISION_INT[$new_line,1]"]
            fix(m1[:vNEW_TRANS_CAP_DECISION_INT][new_line, 1], val1, force = true)
            #val2 = planning_sol1.values["vNEW_TRANS_CAP_DECISION_INT[$new_line,2]"]
            #fix(m1[:vNEW_TRANS_CAP_DECISION_INT][new_line, 2], val2, force = true)
        end
    #end
    optimize!(m1)
#end
#if UB_hist2[end] < objective_value(m2)
#    l2l_map = n_inputs[2]["l2l_map"]
#    for k in keys(l2l_map)
    for new_line in n_inputs[2]["CANDIDATE_LINES"]
        val = planning_sol2.values["vNEW_TRANS_CAP_DECISION_INT[$new_line,1]"]
        fix(m2[:vNEW_TRANS_CAP_DECISION_INT][new_line, 1], val, force = true)
    end
    optimize!(m2)
#end
# if UB_hist3[end] < objective_value(m3)
#     l2l_map = n_inputs[3]["l2l_map_cand"]
#     for k in keys(l2l_map)
#         old_line = k
#         new_line = l2l_map[k]
    for new_line in n_inputs[3]["CANDIDATE_LINES"]
        val = planning_sol3.values["vNEW_TRANS_CAP_DECISION_INT[$new_line,1]"]
        fix(m3[:vNEW_TRANS_CAP_DECISION_INT][new_line, 1], val, force = true)
    end
    optimize!(m3)
# end

println("Zonal objective is : ", objective_value(mz))
println("Nodal objective is : ", objective_value(m1) + objective_value(m2) + objective_value(m3))

#=
for i in 1:length(n_inputs[1]["adj_list_cand"])
    #println(value(m1[:vNEW_TRANS_CAP_DECISION_INT][i, 1]), "    ", planning_sol1.values["vNEW_TRANS_CAP_DECISION_INT[$i,1]"])
    println(value(m1[:vNEW_TRANS_CAP_DECISION_INT][i, 2]), "    ", planning_sol1.values["vNEW_TRANS_CAP_DECISION_INT[$i,2]"])
end














# plot results
using PlasmoData, PlasmoDataPlots
fadjlist = z_inputs["adj_list_cand"]
dg = DataGraph{Int, Any, Any, Any, Matrix{Any}, Matrix{Any}}()
for i in 1:73
    add_node!(dg, i)
    if zone_map[i] == 1
        add_node_data!(dg, i, 1, "partition")
        add_node_data!(dg, i, "red", "color")
    elseif zone_map[i] == 2
        add_node_data!(dg, i, 2, "partition")
        add_node_data!(dg, i, "orange", "color")
    else
        add_node_data!(dg, i, 3, "partition")
        add_node_data!(dg, i, "blue", "color")
    end
    add_node_data!(dg, i, part9[i], "partition_metis")
    add_node_data!(dg, i, my_colors[part9[i]], "color")
    add_node_data!(dg, i, 6, "nodesize")
end
for (src, dst) in fadjlist
    add_edge!(dg, src, dst)
    add_edge_data!(dg, src, dst, "black", "new_build")
    add_edge_data!(dg, src, dst, 2, "linewidth")
    add_edge_data!(dg, src, dst, "black", "new_build_monolithic")
    add_edge_data!(dg, src, dst, 2, "linewidth_monolithic")
    add_edge_data!(dg, src, dst, "black", "zonal_line")
end



plot_graph(dg, nodecolor = get_node_data(dg, "color"), nodesize = 6, xdim = 500, ydim = 500, save_fig = false, linewidth=2, linecolor = "black", fig_name = (@__DIR__)*"/zonal_system.png")
add_node_data!(dg, 13, -0.52, "x_positions")
add_node_data!(dg, 13, 0.16, "y_positions")
plot_graph(dg, nodecolor = get_node_data(dg, "color"), nodesize = 6, xdim = 500, ydim = 500, save_fig = false, linewidth=2, linecolor = "black", fig_name = (@__DIR__)*"/zonal_system.png")

plot_graph(dg, nodecolor = "grey", nodesize = 6, xdim = 500, ydim = 500, save_fig = false, linewidth=2, linecolor = "black", fig_name = (@__DIR__)*"/zonal_system_plain.png")



l2z_map = z_inputs["l2z_map_cand"]
for k in keys(l2z_map)
    new_line = l2z_map[k]
    add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "white", "zonal_line")
    if value(mz[:vNEW_TRANS_LINES][new_line, 1]) == 1
        add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "red", "new_build")
        add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], 5, "linewidth")
    end
end


models = [m1, m2, m3]
for i in 1:num_zones
    n_input = n_inputs[i]
    l2l_map = n_input["l2l_map_cand"]
    model = models[i]
    for k in keys(l2l_map)
        old_line = k
        new_line = l2l_map[k]
        if value(models[i][:vNEW_TRANS_CAP_DECISION_INT][new_line, 1]) == 1
            add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], "red", "new_build")
            add_edge_data!(dg, fadjlist[k][1], fadjlist[k][2], 5, "linewidth")
        end
    end
end

for i in 1:num_zones
    n_input = n_inputs[i]
    n2n_map = n_input["n2n_map"]
    n2n_map_back = Dict()
    for j in keys(n2n_map)
        n2n_map_back[n2n_map[j]] = j
    end
    vcap_nodes = models[i][:vCAP].axes[1]
    for j in vcap_nodes
        println(j)
        if value(models[i][:vCAP][j]) > 0
            resource = n_input["RESOURCES"][j]
            println(parent(resource)[:resource])
            genx_zone = parent(resource)[:zone]
            node = n2n_map_back[genx_zone]
            add_node_data!(dg, node, "black", "color")
            add_node_data!(dg, node, 10, "nodesize")
            println(node)
        end
    end
end



plot_graph(dg, nodecolor = get_node_data(dg, "color"), nodesize = get_node_data(dg, "nodesize"), xdim = 500, ydim = 500, linewidth = get_edge_data(dg, "linewidth"), linecolor = get_edge_data(dg, "new_build"), save_fig = false, fig_name = (@__DIR__)*"/zonal_nodal_builds_RTS_repweek_benders.png")

total_vNSE = sum(value.(m1[:vNSE])) + sum(value.(m2[:vNSE])) + sum(value.(m3[:vNSE]))

total_overproduction = sum(value.(m1[:vOverProduction])) + sum(value.(m2[:vOverProduction])) + sum(value.(m3[:vOverProduction]))

total_vCAP = sum(value.(m1[:vCAP])) + sum(value.(m2[:vCAP])) + sum(value.(m3[:vCAP]))

aggregated_vCAP = sum(value.(mz[:vCAP]))


vP_by_zone_zonal = zeros(3)
vP_by_zone_nodal = zeros(3)
# vP_by_zone_monolithic = zeros(3)
vCAP_by_zone_nodal = zeros(3)
vCAP_by_zone_zonal = zeros(3)

g2z_map = z_inputs["g2z_map"]

for k in keys(g2z_map)
    vP_by_zone_zonal[g2z_map[k]] += sum(value.(mz[:vP][k, :]))
    if k in mz[:vCAP].axes[1]
        vCAP_by_zone_zonal[g2z_map[k]] += sum(value.(mz[:vCAP][k]))
    end
    #vP_by_zone_monolithic[g2z_map[k]] += sum(value.(m[:vP][k, :]))
end

vP_by_zone_nodal[1] = sum(value.(m1[:vP]))
vP_by_zone_nodal[2] = sum(value.(m2[:vP]))
vP_by_zone_nodal[3] = sum(value.(m3[:vP]))

vCAP_by_zone_nodal[1] = sum(value.(m1[:vCAP]))
vCAP_by_zone_nodal[2] = sum(value.(m2[:vCAP]))
vCAP_by_zone_nodal[3] = sum(value.(m3[:vCAP]))
a=1



# benders_settings_path = GenX.get_settings_path(case, "benders_settings.yml")
# mysetup_benders = GenX.configure_benders(benders_settings_path) 

# genx_settings = GenX.get_settings_path(case, "genx_settings.yml") # Settings YAML file path
# writeoutput_settings = GenX.get_settings_path(case, "output_settings.yml") # Write-output settings YAML file path
# mysetup = GenX.configure_settings(genx_settings, writeoutput_settings) # mysetup dictionary stores settings and GenX-specific parameters

# mysetup["DC_OPF"] = 1
# # myinputs = GenX.load_inputs(mysetup, case, p)
# mysetup["ptdf"] = 0
# mysetup["bilinear"] = 1
# mysetup["disaggregate"] = 0
# mysetup["unfix_slacks"] = 0
# mysetup["SOS1"] = 0
# mysetup = merge(mysetup,mysetup_benders);

# settings_path = GenX.get_settings_path(case)    
# mysetup["settings_path"] = settings_path;
# mysetup["Benders"] = 1

# myinputs_decomp = GenX.separate_inputs_subperiods(myinputs);
# # nodal_setup_Benders = deepcopy(nodal_setup)
# # nodal_setup_Benders["Benders"] = 1
# benders_inputs = GenX.generate_benders_inputs(mysetup,myinputs,myinputs_decomp)

# planning_problem, planning_sol, operational_sol, LB_hist,UB_hist, cpu_time,feasibility_hist, build_decisions  = GenX.benders(benders_inputs,mysetup,myinputs);

# for i in keys(planning_sol.values)
#     if planning_sol.values[i] != 0
#         println(i, " = ", planning_sol.values[i])
#     end
# end

# df = DataFrame()

# df[!, "UBs"] = UB_hist
# df[!, "LBs"] = LB_hist
# df[!, "cpu_time"] = cpu_time

# #CSV.write((@__DIR__)*"/zonal_to_nodal_benders_1week_RTS.csv", df)
# optimizer = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 3600, "MIPGap" => 1e-3)

# m = GenX.generate_model(mysetup, myinputs, optimizer)

# optimize!(m)
mtest = JuMP.read_from_file((@__DIR__)*"/../../../subproblem_1.0.lp")
=#
=#