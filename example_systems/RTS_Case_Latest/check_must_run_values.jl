mr = myinputs["MUST_RUN"]

cap_factors = myinputs["pP_Max"]

cap_factors[mr[1], :]

using Plots, Statistics

# Example data
data = cap_factors[mr[30], :]

# Separate
zeros_count = count(==(0), data)
nonzeros = filter(!=(0), data)

# Plot histogram
histogram(nonzeros, bins=100, label="Non-zero values", alpha=0.7, color=:steelblue)

# Add a bar for zeros
#bar!([0.0], [zeros_count], bar_width=0.02, color=:tomato, label="Zeros")

xlabel!("Value")
ylabel!("Count")
title!("Distribution of Capacity Factors for MustRun")
xlims!(-0.05, 1.0)



demands = myinputs["pD"]


using Plots, Statistics

bus_num = 8
# Example data
data = demands[:, bus_num]

# Separate
zeros_count = count(==(0), data)
nonzeros = filter(!=(0), data)

# Plot histogram
histogram(nonzeros, bins=100, label="Non-zero values", alpha=0.7, color=:steelblue)

# Add a bar for zeros
#bar!([0.0], [zeros_count], bar_width=0.02, color=:tomato, label="Zeros")

xlabel!("Value")
ylabel!("Count")
title!("Distribution of Demands at Bus $bus_num")


rs = myinputs["RESOURCES"]

must_run_node1 = parent(rs[mr[1]])[:region]

for i in 1:length(rs)
    if parent(rs[i])[:region] == must_run_node1
        println(parent(rs[i])[:resource])
    end
end



mtest = JuMP.read_from_file((@__DIR__)*"/subproblem_2.lp")

solver = optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 300, "QCPDual" => 1, "Crossover" => 1, "Method" => 2)

set_optimizer(mtest, solver)

optimize!(mtest)