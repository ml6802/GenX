using JuMP, Gurobi

m = read_from_file((@__DIR__)*"/../../subproblem__3.0.lp")

solve_times = []
got_duals = []
obj_scales = [1e-5, 1e-4, 1e-3, 1e-2, 1e-1, 1e1, 1e3, 1e5, 1e7, 1e8]

for obj_scale in obj_scales
    println("RUNNING $obj_scale")
    solver = optimizer_with_attributes(Gurobi.Optimizer, "QCPDual" => 1, "Method" => 2, "MIPGap" => 1e-3, "BarConvTol" => 1e-8, "Crossover" => 1, "ObjScale" => obj_scale, "ScaleFlag" => 2, "TimeLimit" => 160)

    set_optimizer(m, solver)

    t = @elapsed optimize!(m)

    if dual_status(m) == MOI.NO_SOLUTION
        push!(got_duals, 0)
    else
        push!(got_duals, 1)
    end

    push!(solve_times, t)
end





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
