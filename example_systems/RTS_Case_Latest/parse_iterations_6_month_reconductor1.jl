# Script to parse iteration data from test_output_parsing.txt
using DelimitedFiles


function parse_iteration_data(filename::String)
    # Initialize vectors to store the data
    k_values = Int[]
    LB_values = Float64[]
    UB_values = Float64[]
    gap_values = Float64[]
    cpu_time_values = Float64[]
    planning_time_values = Float64[]
    subproblem_time_values = Float64[]
    
    # Set to keep track of already processed k values (to handle duplicates)
    processed_k = Set{Int}()
    
    # Read the file line by line
    open(filename, "r") do file
        # Track the most recently seen per-iteration timings prior to a "k = " line
        current_planning_sec = NaN
        current_subprob_sec = NaN
        for line in eachline(file)
            # Capture planning problem time (already in seconds)
            if startswith(line, "Solving the planning problem required")
                try
                    # Extract first numeric value (supports scientific notation)
                    if (m = match(r"([0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)", line)) !== nothing
                        current_planning_sec = parse(Float64, m.captures[1])
                    end
                catch e
                    println("Warning: Could not parse planning time line: $line")
                    println("Error: $e")
                end
                continue
            end

            # Capture distributed subproblems time (reported in minutes -> convert to seconds)
            if startswith(line, "Time to run distributed subproblems is")
                try
                    if (m = match(r"([0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)", line)) !== nothing
                        current_subprob_sec = 60.0 * parse(Float64, m.captures[1])
                    end
                catch e
                    println("Warning: Could not parse subproblem time line: $line")
                    println("Error: $e")
                end
                continue
            end

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
                    push!(planning_time_values, current_planning_sec)
                    push!(subproblem_time_values, current_subprob_sec)
                    
                    # Mark this k value as processed
                    push!(processed_k, k_val)

                    # Reset trackers for next iteration block
                    current_planning_sec = NaN
                    current_subprob_sec = NaN
                    
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
        cpu_time = cpu_time_values[sort_indices],
        planning_time = planning_time_values[sort_indices],
        subproblem_time = subproblem_time_values[sort_indices]
    )
end

include((@__DIR__)*"/parse_gurobi.jl")


# Parse the data
println("Parsing iteration data from test_output_parsing.txt...")
data = parse_iteration_data((@__DIR__)*"/6_month_multicut_results_reconductor_full.txt")
#data2 = parse_iteration_data((@__DIR__)*"/6_month_benders_initialize.txt")
#data2 = parse_iteration_data((@__DIR__)*"/6_month_multicut_fixedmustruns.txt")
data2 = parse_gurobi_data((@__DIR__)*"/6_month_monolithic_reconductor_full.txt")
#data4 = parse_iteration_data((@__DIR__)*"/6_month_multicut_results_warmstart.txt")
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
println()
println("Planning Time (s) = ", data.planning_time)
println()
println("Subproblem Time (s) = ", data.subproblem_time)


#data2.cpu_time .+= 4800
using Plots
cputimes = data.cpu_time ./ 3600
cputimes2 = data2.time ./ 3600


plot([],[], yaxis = :log, color = "black", label="Genearlized Benders", linewidth = 2)
# plot!([], [], yaxis = :log, color = "orange", label = "Benders Multicut, warmstart", linewidth = 2)
plot!([],[], yaxis = :log, color = "blue", label="Monolithic (Gurobi)", linewidth = 2)
plot!([],[], yaxis = :log, color = "grey", label="Upper Bound", linewidth = 2)
plot!([],[], yaxis = :log, color = "grey", label="Lower Bound", linewidth = 2, linestyle = :dash)
plot!([],[], yaxis = :log, color = "red", label="Waterflow Objective", linewidth = 2)
plot!(cputimes, data.UB, color = "black", label = :none, linewidth = 2)
plot!(cputimes, data.LB, color = "black", label = :none, linewidth = 2, linestyle = :dash)
plot!([cputimes2[1], cputimes2[end]], [7.476e8, 7.476e8], color = "red", label = :none, linewidth = 3, linestyle = :dash)
plot!(cputimes2, data2.UB, yaxis = :log, color = "blue", label = :none, linewidth = 2)
plot!(cputimes2, data2.LB, yaxis = :log, color = "blue", label = :none, linewidth = 2)
# plot!(cputimes3, data3.UB, yaxis = :log, color = "blue", label = :none, linewidth = 2)
# plot!(cputimes3, data3.LB, color = "blue", label = :none, linewidth = 2, linestyle = :dash)
# plot!(cputimes4, data4.UB, color = "orange", label = :none, linewidth = 2)
# plot!(cputimes4, data4.LB, color = "orange", label = :none, linewidth = 2, linestyle = :dash)
xlabel!("Time (hrs)")
ylabel!("Objective Value (USD)")
#ylims!(3e8, 3e12)
#   savefig((@__DIR__)*"/6_month_monolithic_Benders_reconductor_full.png")

plot(data.k, data.cpu_time ./ 3600, label = :none, color = "black", linewidth = 2)
xlabel!("Iteration")
ylabel!("Total Solution Time (hr)")

tperiter = [data.cpu_time[i+1] - data.cpu_time[i] for i in 1:length(data.k)-1]

plot(1:length(data.k)-1, tperiter ./ 60, label = :none, color = "black", linewidth = 2)
xlabel!("Iteration")
ylabel!("Solution Time of Iteration (min)")

# Also save to a CSV file for easy access
println("\nSaving data to iterations_data.csv...")
using CSV, DataFrames

df = DataFrame(
    iteration = data.k,
    lower_bound = data.LB,
    upper_bound = data.UB,
    gap = data.gap,
    cpu_time = data.cpu_time,
    planning_time = data.planning_time,
    subproblem_time = data.subproblem_time
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




plot([],[], yaxis = :log, color = "black", label="Benders Multicut", linewidth = 2)
plot!([],[], yaxis = :log, color = "red", label="Benders Multicut, filtered lines", linewidth = 2)
plot!([], [], yaxis = :log, color = "orange", label = "Benders Multicut, warmstart", linewidth = 2)
plot!([],[], yaxis = :log, color = "grey", label="Upper Bound", linewidth = 2)
plot!([],[], yaxis = :log, color = "grey", label="Lower Bound", linewidth = 2, linestyle = :dash)
plot!(data.k, data.UB, color = "black", label = :none, linewidth = 2)
plot!(data.k, data.LB, color = "black", label = :none, linewidth = 2, linestyle = :dash)
plot!(data2.k, data2.UB, yaxis = :log, color = "red", label = :none, linewidth = 2)
#plot!([cputimes2[1], cputimes2[end]], [9.89e8, 9.89e8], color = "red", label = :none, linewidth = 2, linestyle = :dash)
plot!(data4.k, data4.UB, color = "orange", label = :none, linewidth = 2)
plot!(data4.k, data4.LB, color = "orange", label = :none, linewidth = 2, linestyle = :dash)
xlabel!("Iteration")
ylabel!("Objective Value (USD)")