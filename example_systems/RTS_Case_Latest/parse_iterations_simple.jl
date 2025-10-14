# Simple script to parse iteration data without external dependencies
function parse_iteration_data_simple(filename::String)
    # Initialize vectors to store the data
    k_values = Int[]
    LB_values = Float64[]
    UB_values = Float64[]
    gap_values = Float64[]
    cpu_time_values = Float64[]
    
    # Set to keep track of already processed k values (to handle duplicates)
    processed_k = Set{Int}()
    
    # Read the file line by line
    lines = readlines(filename)
    
    for line in lines
        # Check if line starts with "k = "
        if startswith(line, "k = ")
            try
                # Use regex to extract the numeric values
                k_match = match(r"k = (\d+)", line)
                lb_match = match(r"LB = ([\d\.e\+\-]+)", line)
                ub_match = match(r"UB = ([\d\.e\+\-]+)", line)
                gap_match = match(r"Gap = ([\d\.e\+\-]+)", line)
                cpu_match = match(r"CPU Time = ([\d\.e\+\-]+)", line)
                
                if k_match !== nothing && lb_match !== nothing && ub_match !== nothing && gap_match !== nothing && cpu_match !== nothing
                    k_val = parse(Int, k_match.captures[1])
                    
                    # Skip if we've already processed this k value
                    if k_val in processed_k
                        continue
                    end
                    
                    lb_val = parse(Float64, lb_match.captures[1])
                    ub_val = parse(Float64, ub_match.captures[1])
                    gap_val = parse(Float64, gap_match.captures[1])
                    cpu_val = parse(Float64, cpu_match.captures[1])
                    
                    # Store the values
                    push!(k_values, k_val)
                    push!(LB_values, lb_val)
                    push!(UB_values, ub_val)
                    push!(gap_values, gap_val)
                    push!(cpu_time_values, cpu_val)
                    
                    # Mark this k value as processed
                    push!(processed_k, k_val)
                end
                
            catch e
                println("Warning: Could not parse line: $line")
                println("Error: $e")
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

# Parse the data
println("Parsing iteration data from test_output_parsing.txt...")
data = parse_iteration_data_simple("test_output_parsing.txt")

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

# Print summary statistics
println("\nSummary Statistics:")
println("===================")
println("Iterations: $(minimum(data.k)) to $(maximum(data.k))")
println("Final Lower Bound: $(data.LB[end])")
println("Final Upper Bound: $(data.UB[end])")
println("Final Gap: $(data.gap[end])%")
println("Total CPU Time: $(data.cpu_time[end]) seconds")
println("Total CPU Time: $(data.cpu_time[end]/3600) hours")

# Also create a simple text file with the results
println("\nSaving data to iterations_data.txt...")
open("iterations_data.txt", "w") do f
    println(f, "Iteration Data Extracted from test_output_parsing.txt")
    println(f, "="^50)
    println(f, "k,LB,UB,Gap,CPU_Time")
    for i in 1:length(data.k)
        println(f, "$(data.k[i]),$(data.LB[i]),$(data.UB[i]),$(data.gap[i]),$(data.cpu_time[i])")
    end
end
println("Data saved to iterations_data.txt")