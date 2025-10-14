# Script to parse iteration data from test_output_parsing.txt
using DelimitedFiles


function parse_iteration_data(filename::String)
    # Initialize vectors to store the data
    k_values = Int[]
    LB_values = Float64[]
    UB_values = Float64[]
    gap_values = Float64[]
    cpu_time_values = Float64[]
    
    # Set to keep track of already processed k values (to handle duplicates)
    processed_k = Set{Int}()
    
    # Read the file line by line
    open(filename, "r") do file
        for line in eachline(file)
            # Check if line starts with "k = "
            if startswith(line, "k = ")
                try
                    # Split the line by whitespace and extract values
                    parts = split(line)
                    
                    # Extract k value (should be after "k = ")
                    k_val = parse(Int, parts[3])
                    
                    # Skip if we've already processed this k value
                    if k_val in processed_k
                        continue
                    end
                    
                    # Extract LB value (should be after "LB = ")
                    lb_idx = findfirst(x -> x == "LB", parts)
                    lb_val = parse(Float64, parts[lb_idx + 2])
                    
                    # Extract UB value (should be after "UB = ")
                    ub_idx = findfirst(x -> x == "UB", parts)
                    ub_val = parse(Float64, parts[ub_idx + 2])
                    
                    # Extract Gap value (should be after "Gap = ")
                    gap_idx = findfirst(x -> x == "Gap", parts)
                    gap_val = parse(Float64, parts[gap_idx + 2])
                    
                    # Extract CPU Time value (should be after "CPU Time = ")
                    cpu_idx = findfirst(x -> x == "CPU", parts)
                    cpu_val = parse(Float64, parts[cpu_idx + 3])  # Skip "Time" and "="
                    
                    # Store the values
                    push!(k_values, k_val)
                    push!(LB_values, lb_val)
                    push!(UB_values, ub_val)
                    push!(gap_values, gap_val)
                    push!(cpu_time_values, cpu_val)
                    
                    # Mark this k value as processed
                    push!(processed_k, k_val)
                    
                catch e
                    println("Warning: Could not parse line: $line")
                    println("Error: $e")
                end
            end
        end
    end
    
    # Sort by k values to ensure proper order
    sort_indices = sortperm(k_values)
    
    return (
        k = k_values[sort_indices],
        LB = LB_values[sort_indices],
        UB = UB_values[sort_indices],
        gap = gap_values[sort_indices],
        cpu_time = cpu_time_values[sort_indices]
    )
end

include((@__DIR__)*"/parse_gurobi.jl")


# Parse the data
println("Parsing iteration data from test_output_parsing.txt...")

# Display the results
println("\nParsed Data:")
println("============")
println("Number of iterations: ", length(data.k))
println()

println("Iteration vectors:")
println("k = ", data.k)
println()
println("LB = ", data.LB)
println()
println("UB = ", data.UB)
println()
println("Gap = ", data.gap)
println()
println("CPU Time = ", data.cpu_time)

data1 = parse_iteration_data((@__DIR__)*"/3_month_benders_model1.txt")
data2 = parse_iteration_data((@__DIR__)*"/3_month_benders_model2.txt")
data3 = parse_iteration_data((@__DIR__)*"/3_month_benders_model3.txt")
data_mono1 = parse_gurobi_data((@__DIR__)*"/3_month_monolithic_model1.txt")
data_mono2 = parse_gurobi_data((@__DIR__)*"/3_month_monolithic_model2.txt")
data_mono3 = parse_gurobi_data((@__DIR__)*"/3_month_monolithic_model3.txt")
using Plots
cputimes1 = data1.cpu_time ./ 3600
cputimes2 = data2.cpu_time ./ 3600
cputimes3 = data3.cpu_time ./ 3600
cputimes_mono1 = data_mono1.time ./ 3600
cputimes_mono2 = data_mono2.time ./ 3600
cputimes_mono3 = data_mono3.time ./ 3600

plot([],[], yaxis = :log, color = "black", label="Benders Multicut", linewidth = 2)
plot!([],[], yaxis = :log, color = "blue", label="Monolithic (Gurobi)", linewidth = 2)
plot!([],[], yaxis = :log, color = "grey", label="Upper Bound", linewidth = 2)
plot!([],[], yaxis = :log, color = "grey", label="Lower Bound", linewidth = 2, linestyle = :dash)
scatter!([],[],color="grey", label = "Point of Convergence", marker = :circle, markersize = 5)
plot!(cputimes1, data1.UB, color = "black", label = :none, linewidth = 2)
plot!(cputimes1, data1.LB, color = "black", label = :none, linewidth = 2, linestyle = :dash)
plot!(cputimes_mono1, data_mono1.UB, yaxis = :log, color = "blue", label = :none, linewidth = 2)
plot!(cputimes_mono1, data_mono1.LB, color = "blue", label = :none, linewidth = 2, linestyle = :dash)
scatter!([cputimes1[end]], [data1.UB[end]], color = "black", marker=:circle, markersize = 5, label=:none)
scatter!([cputimes_mono1[end]], [data_mono1.UB[end]], color = "blue", marker=:circle, markersize = 5, label=:none)
xlabel!("Time (hrs")
ylabel!("Objective Value (USD)")
title!("Zone 1")
#savefig((@__DIR__)*"/3_month_model1_comp.png")


plot([],[], yaxis = :log, color = "black", label="Benders Multicut", linewidth = 2)
plot!([],[],color = "blue", label="Monolithic (Gurobi)", linewidth = 2)
plot!([],[],color = "grey", label="Upper Bound", linewidth = 2)
plot!([],[], color = "grey", label="Lower Bound", linewidth = 2, linestyle = :dash)
scatter!([],[],color="grey", label = "Point of Convergence", marker = :circle, markersize = 5)
plot!(cputimes2, data2.UB, color = "black", label = :none, linewidth = 2)
plot!(cputimes2, data2.LB, color = "black", label = :none, linewidth = 2, linestyle = :dash)
plot!(cputimes_mono2, data_mono2.UB, color = "blue", label = :none, linewidth = 2)
plot!(cputimes_mono2, data_mono2.LB, color = "blue", label = :none, linewidth = 2, linestyle = :dash)
scatter!([cputimes2[end]], [data2.UB[end]], color = "black", marker=:circle, markersize = 5, label=:none)
scatter!([cputimes_mono2[end]], [data_mono2.UB[end]], color = "blue", marker=:circle, markersize = 5, label=:none)
xlabel!("Time (hrs")
ylabel!("Objective Value (USD)")
title!("Zone 2")
#savefig((@__DIR__)*"/3_month_model2_comp.png")


plot([],[], yaxis = :log, color = "black", label="Benders Multicut", linewidth = 2)
plot!([],[], yaxis = :log, color = "blue", label="Monolithic (Gurobi)", linewidth = 2)
plot!([],[], yaxis = :log, color = "grey", label="Upper Bound", linewidth = 2)
plot!([],[], yaxis = :log, color = "grey", label="Lower Bound", linewidth = 2, linestyle = :dash)
scatter!([],[],color="grey", label = "Point of Convergence", marker = :circle, markersize = 5)
plot!(cputimes3, data3.UB, color = "black", label = :none, linewidth = 2)
plot!(cputimes3, data3.LB, color = "black", label = :none, linewidth = 2, linestyle = :dash)
plot!(cputimes_mono3, data_mono3.UB, yaxis = :log, color = "blue", label = :none, linewidth = 2)
plot!(cputimes_mono3, data_mono3.LB, color = "blue", label = :none, linewidth = 2, linestyle = :dash)
scatter!([cputimes3[end]], [data3.UB[end]], color = "black", marker=:circle, markersize = 5, label=:none)
scatter!([cputimes_mono3[end]], [data_mono3.UB[end]], color = "blue", marker=:circle, markersize = 5, label=:none)
xlabel!("Time (hrs")
ylabel!("Objective Value (USD)")
title!("Zone 3")
#savefig((@__DIR__)*"/3_month_model3_comp.png")