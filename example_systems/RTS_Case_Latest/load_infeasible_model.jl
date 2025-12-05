using JuMP, Gurobi

m = read_from_file((@__DIR__)*"/subproblem__6.0.lp")

solver = optimizer_with_attributes(Gurobi.Optimizer, "QCPDual" => 1, "Method" => 2, "MIPGap" => 1e-3, "BarConvTol" => 1e-8, "Crossover" => 1, "ObjScale" => 1e-3, "ScaleFlag" => 2)

set_optimizer(m, solver)

optimize!(m)





var_om_cost_only = [0.]
fixed_cost_only = [0.]
no_costs = [0.]

var_om_cost_only_vre = [0.]
fixed_cost_only_vre = [0.]
no_costs_vre = [0.]

var_om_cost_only_new_cap = [0.]
fixed_cost_only_new_cap = [0.]
no_costs_new_cap = [0.]

var_om_cost_only_new_cap_vre = [0.]
fixed_cost_only_new_cap_vre = [0.]
no_costs_new_cap_vre = [0.]

for i in 1:length(myinputs["RESOURCES"])
    r = myinputs["RESOURCES"][i]
    if GenX.var_om_cost_per_mwh(r) == 0 && GenX.fixed_om_cost_per_mwyr(r) > 0
        fixed_cost_only[1] += 1
        if i in myinputs["NEW_CAP"]
            fixed_cost_only_new_cap[1] += 1
            if isa(r, GenX.Vre)
                fixed_cost_only_new_cap_vre[1] += 1
            end
        end
        if isa(r, GenX.Vre)
            fixed_cost_only_vre[1] += 1
        end
    elseif GenX.var_om_cost_per_mwh(r) > 0 && GenX.fixed_om_cost_per_mwyr(r) == 0
        var_om_cost_only[1] += 1
        if i in myinputs["NEW_CAP"]
            var_om_cost_only_new_cap[1] += 1
            if isa(r, GenX.Vre)
                var_om_cost_only_new_cap_vre[1] += 1
            end
        end
        if isa(r, GenX.Vre)
            var_om_cost_only_vre[1] += 1
        end
    else
        no_costs[1] += 1
        if i in myinputs["NEW_CAP"]
            no_costs_new_cap[1] += 1
            println(r)
            if isa(r, GenX.Vre)
                no_costs_new_cap_vre[1] += 1
            end
        end
        if isa(r, GenX.Vre)
            no_costs_vre[1] += 1
        end
    end
end


for t in techs
    println(IS.get_proportional_term(IS.get_vom_cost(PSY.get_variable(get_operation_costs(t)))))
end


using SQLite
db = SQLite.DB((@__DIR__)*"/sys_DA.sqlite")

table_names = DBInterface.execute(db, "SELECT name FROM sqlite_master WHERE type='table';") |> DataFrame

supply_tech = DBInterface.execute(db, "SELECT * FROM supply_technologies") |> DataFrame

time_series_assoc = DBInterface.execute(db, "SELECT * FROM time_series_associations") |> DataFrame

attributes = DBInterface.execute(db, "SELECT * FROM attributes") |> DataFrame
