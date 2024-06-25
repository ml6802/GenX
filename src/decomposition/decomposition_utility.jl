
function separate_inputs_subperiods(inputs::Dict)

    inputs_all=Dict();
    number_periods = inputs["REP_PERIOD"];
    hours_per_subperiod = inputs["hours_per_subperiod"];
    
    ####### entries_to_be_changed = ["omega","REP_PERIOD",","INTERIOR_SUBPERIODS","START_SUBPERIODS","pP_Max","T","fuel_costs","Weights","pD","C_Start"];

    for w in 1:number_periods
        inputs_all[w] = deepcopy(inputs);
        Tw = (w-1)*hours_per_subperiod+1:w*hours_per_subperiod;
        inputs_all[w]["omega"] = inputs["omega"][Tw];
        inputs_all[w]["REP_PERIOD"]=1;
        STARTS = 1:hours_per_subperiod:hours_per_subperiod;
        INTERIORS = setdiff(1:hours_per_subperiod,STARTS);   
        inputs_all[w]["INTERIOR_SUBPERIODS"] = INTERIORS;
        inputs_all[w]["START_SUBPERIODS"] = STARTS;
        inputs_all[w]["pP_Max"] = inputs["pP_Max"][:,Tw];
        inputs_all[w]["T"] = hours_per_subperiod;
        for ks in keys(inputs["fuel_costs"])
            inputs_all[w]["fuel_costs"][ks] = inputs["fuel_costs"][ks][Tw];
        end
        inputs_all[w]["Weights"] = [inputs["Weights"][w]];
        inputs_all[w]["pD"] = inputs["pD"][Tw,:];
        inputs_all[w]["C_Start"] = inputs["C_Start"][:,Tw]; 
        inputs_all[w]["SubPeriod"] = w;
		if haskey(inputs,"Period_Map")
			inputs_all[w]["SubPeriod_Index"] = inputs["Period_Map"].Rep_Period[findfirst(inputs["Period_Map"].Rep_Period_Index.==w)];
		end

    end

    return inputs_all

end
