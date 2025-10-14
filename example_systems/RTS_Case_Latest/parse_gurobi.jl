# Script to parse Gurobi output data from 6_month_monolithic.txt
function parse_gurobi_data(filename::String)
    # Initialize vectors to store the data
    iteration_counter = 0
    iterations = Int[]
    incumbent_values = Float64[]  # UB (Upper Bound)
    bestbd_values = Float64[]     # LB (Lower Bound) 
    gap_values = Float64[]        # Gap percentage
    time_values = Float64[]       # CPU Time in seconds
    
    # Read the file line by line
    lines = readlines(filename)
    
    println("Parsing Gurobi output from $filename...")
    
    for line in lines
        # Check if this is a regular optimization iteration line
        # Format: "     0     0 7.5409e+08    0   35 1.9972e+11 7.5409e+08   100%     - 13799s"
        regular_match = match(r"^\s+(\d+)\s+(\d+)\s+([\d\.e\+\-]+)\s+\d+\s+\d+\s+([\d\.e\+\-]+)\s+([\d\.e\+\-]+)\s+([\d\.%]+)\s+.*\s+(\d+)s\s*$", line)
        
        # Check if this is a heuristic solution line (marked with H)
        # Format: "H    0     0                    3.106884e+09 7.5849e+08  75.6%     - 41982s"
        heuristic_match = match(r"^H\s+\d+\s+\d+\s+\s+([\d\.e\+\-]+)\s+([\d\.e\+\-]+)\s+([\d\.%]+)\s+.*\s+(\d+)s\s*$", line)
        
        if regular_match !== nothing
            try
                # For regular lines: incumbent, bestbd, gap, time
                incumbent = parse(Float64, regular_match.captures[4])  # Incumbent (UB)
                bestbd = parse(Float64, regular_match.captures[5])     # BestBd (LB)
                gap_str = regular_match.captures[6]
                gap = parse(Float64, replace(gap_str, "%" => ""))     # Remove % and parse
                time = parse(Float64, regular_match.captures[7])      # Time
                
                iteration_counter += 1
                push!(iterations, iteration_counter)
                push!(incumbent_values, incumbent)
                push!(bestbd_values, bestbd)
                push!(gap_values, gap)
                push!(time_values, time)
                
                println("Parsed iteration $iteration_counter: UB=$incumbent, LB=$bestbd, Gap=$gap%, Time=$time s")
                
            catch e
                println("Warning: Could not parse regular line: $line")
                println("Error: $e")
            end
            
        elseif heuristic_match !== nothing
            try
                # For heuristic lines: incumbent, bestbd, gap, time
                incumbent = parse(Float64, heuristic_match.captures[1])  # Incumbent (UB)
                bestbd = parse(Float64, heuristic_match.captures[2])     # BestBd (LB)
                gap_str = heuristic_match.captures[3]
                gap = parse(Float64, replace(gap_str, "%" => ""))       # Remove % and parse
                time = parse(Float64, heuristic_match.captures[4])      # Time
                
                iteration_counter += 1
                push!(iterations, iteration_counter)
                push!(incumbent_values, incumbent)
                push!(bestbd_values, bestbd)
                push!(gap_values, gap)
                push!(time_values, time)
                
                println("Parsed heuristic iteration $iteration_counter: UB=$incumbent, LB=$bestbd, Gap=$gap%, Time=$time s")
                
            catch e
                println("Warning: Could not parse heuristic line: $line")
                println("Error: $e")
            end
        end
    end
    
    return (
        iteration = iterations,
        UB = incumbent_values,    # Upper Bound (Incumbent)
        LB = bestbd_values,       # Lower Bound (BestBd)
        gap = gap_values,         # Gap percentage
        time = time_values        # CPU Time in seconds
    )
end

# # Parse the data
# println("Parsing Gurobi data from 6_month_monolithic.txt...")
# data = parse_gurobi_data("6_month_monolithic.txt")

# if length(data.iteration) == 0
#     println("No Gurobi optimization data found!")
# else
#     # Display the results
#     println("\nParsed Gurobi Data:")
#     println("===================")
#     println("Number of iterations: ", length(data.iteration))
#     println()
    
#     println("Data vectors:")
#     println("Iteration = ", data.iteration)
#     println()
#     println("UB (Incumbent) = ", data.UB)
#     println()
#     println("LB (BestBd) = ", data.LB)
#     println()
#     println("Gap (%) = ", data.gap)
#     println()
#     println("Time (s) = ", data.time)
    
#     # Print summary statistics
#     println("\nSummary Statistics:")
#     println("===================")
#     println("Iterations: $(minimum(data.iteration)) to $(maximum(data.iteration))")
#     println("Final Upper Bound (Incumbent): $(data.UB[end])")
#     println("Final Lower Bound (BestBd): $(data.LB[end])")
#     println("Final Gap: $(data.gap[end])%")
#     println("Total CPU Time: $(data.time[end]) seconds")
#     println("Total CPU Time: $(data.time[end]/3600) hours")
    
#     # Also create a simple text file with the results
#     println("\nSaving data to gurobi_data.txt...")
#     open("gurobi_data.txt", "w") do f
#         println(f, "Gurobi Optimization Data Extracted from 6_month_monolithic.txt")
#         println(f, "="^60)
#         println(f, "Iteration,UB_Incumbent,LB_BestBd,Gap_Percent,Time_Seconds")
#         for i in 1:length(data.iteration)
#             println(f, "$(data.iteration[i]),$(data.UB[i]),$(data.LB[i]),$(data.gap[i]),$(data.time[i])")
#         end
#     end
#     println("Data saved to gurobi_data.txt")
# end