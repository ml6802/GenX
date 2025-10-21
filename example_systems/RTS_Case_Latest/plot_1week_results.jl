using Plots

data = CSV.read((@__DIR__)*"/1week_zone1_with_retirements_bilinear_only.csv", DataFrame)
data_ws = CSV.read((@__DIR__)*"/1week_zone1_with_retirements_bilinear_doublewarmstart.csv", DataFrame)

cputimes = data[:, "TIME"] ./ 60
cputimes_ws = data_ws[:, "TIME"] ./ 60


plot([],[], yaxis = :log, color = "black", label="Benders Warm Start", linewidth = 2)
plot!([],[], yaxis = :log, color = "red", label="Benders", linewidth = 2)
plot!([],[], yaxis = :log, color = "grey", label="Upper Bound", linewidth = 2)
plot!([],[], yaxis = :log, color = "grey", label="Lower Bound", linewidth = 2, linestyle = :dash)
plot!(cputimes_ws[59:end], data_ws[:, "UB"][59:end], color = "black", label = :none, linewidth = 2)
plot!(cputimes_ws[59:end], data_ws[:, "LB"][59:end], color = "black", label = :none, linewidth = 2, linestyle = :dash)
plot!(cputimes, data[:, "UB"], yaxis = :log, color = "red", label = :none, linewidth = 2)
plot!(cputimes, data[:, "LB"], color = "red", label = :none, linewidth = 2, linestyle = :dash)
#xlabel!("Time (min)")
xlabel!("Time (Min)")
ylabel!("Objective Value (USD)")
title!("Bilinear Formulation, Zone 1")
#savefig((@__DIR__)*"/bilinear_warmstart_comp_nowarmstart_shown.png")

cputimes = [i for i in 1:length(cputimes)]
cputimes_ws = [i for i in 1:length(cputimes_ws)]

plot([],[], yaxis = :log, color = "black", label="Benders Warm Start", linewidth = 2)
plot!([],[], yaxis = :log, color = "red", label="Benders", linewidth = 2)
plot!([],[], yaxis = :log, color = "grey", label="Upper Bound", linewidth = 2)
plot!([],[], yaxis = :log, color = "grey", label="Lower Bound", linewidth = 2, linestyle = :dash)
plot!(cputimes_ws[1:(length(cputimes_ws)-58)], data_ws[:, "UB"][59:end], color = "black", label = :none, linewidth = 2)
plot!(cputimes_ws[1:(length(cputimes_ws)-58)], data_ws[:, "LB"][59:end], color = "black", label = :none, linewidth = 2, linestyle = :dash)
plot!(cputimes, data[:, "UB"], yaxis = :log, color = "red", label = :none, linewidth = 2)
plot!(cputimes, data[:, "LB"], color = "red", label = :none, linewidth = 2, linestyle = :dash)
#xlabel!("Time (min)")
xlabel!("Iteration")
ylabel!("Objective Value (USD)")
# title!("Bilinear Formulation, Zone 1")
# savefig((@__DIR__)*"/bilinear_warmstart_comp_wsremoval.png")

# Also save to a CSV file for easy access
println("\nSaving data to iterations_data.csv...")
using CSV, DataFrames

df = DataFrame(
    iteration = data.k,
    lower_bound = data.LB,
    upper_bound = data.UB,
    gap = data.gap,
    cpu_time = data.cpu_time
)

CSV.write("iterations_data.csv", df)
println("Data saved to iterations_data.csv")

# Print summary statistics
println("\nSummary Statistics:")
println("===================")
println("Iterations: $(minimum(data.k)) to $(maximum(data.k))")
println("Final Lower Bound: $(data.LB[end])")
println("Final Upper Bound: $(data.UB[end])")
println("Final Gap: $(data.gap[end])%")
println("Total CPU Time: $(data.cpu_time[end]) seconds")
println("Total CPU Time: $(data.cpu_time[end]/3600) hours")