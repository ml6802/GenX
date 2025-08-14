
# Load packages
using CSV, DataFrames, FilePathsBase
using Glob

target_dirs = Set(["system", "resources"])

function empty_like(df::DataFrame)
    return DataFrame([Vector{eltype(col)}() for col in eachcol(df)], names(df))
end

function process_network_like_file(file_path::String, zone_to_bus_map, bus_to_zone_map, base_output_dir)
    df_raw = CSV.read(file_path, DataFrame)
    zone_bus_renumber_map = Dict{Int, Dict{Int, Int}}()

    # Extract the folder key (e.g., "system", "inputs", "resources") from the file path
    path_parts = splitpath(file_path)
    folder_key = findfirst(p -> p in target_dirs, path_parts)
    if isnothing(folder_key)
        error("Could not infer folder name (e.g., 'system') from path: $file_path")
    end
    file_key = path_parts[folder_key]  # this is "system", "inputs", etc.

    num_zones = length(zone_to_bus_map)
    # Step 1: Create partition + interzone containers
    partition_dfs = Dict(i => empty_like(df_raw) for i in 1:num_zones)
    interzone_df = empty_like(df_raw)

    # Step 2: Partition rows
    for row in eachrow(df_raw)
        s = row.Start_Zone
        e = row.End_Zone

        s_zone = get(bus_to_zone_map, s, missing)
        e_zone = get(bus_to_zone_map, e, missing)

        if ismissing(s_zone) || ismissing(e_zone)
            @warn "Start or end bus not found in bus_to_zone_map: $s, $e"
            continue
        end

        if s_zone == e_zone
            push!(partition_dfs[s_zone], row)
        else
            push!(interzone_df, row)
        end
    end


    # Step 3: Rename + relabel partition DataFrames
    for (zone_id, df) in partition_dfs
        buses = zone_to_bus_map[zone_id]
        old_to_new = Dict(buses[i] => i for i in eachindex(buses))
        zone_bus_renumber_map[zone_id] = old_to_new

        original_starts = df.Start_Zone
        original_ends = df.End_Zone

        df.transmission_path_name = [
            "BUS$(old_to_new[s])_to_BUS$(old_to_new[e])"
            for (s, e) in zip(original_starts, original_ends)
        ]

        df.Start_Zone = [old_to_new[s] for s in original_starts]
        df.End_Zone   = [old_to_new[e] for e in original_ends]

        num_buses = length(buses)
        num_edges = nrow(df)

        df.Column1 = [i <= num_buses ? "BUS$(i)" : missing for i in 1:num_edges]
        df.Network_zones = [i <= num_buses ? "z$(i)" : missing for i in 1:num_edges]
        df.Network_Lines = 1:num_edges

        # Save the updated df
        subfolder = joinpath(base_output_dir, "zone_$zone_id", file_key)
        mkpath(subfolder)
        CSV.write(joinpath(subfolder, basename(file_path)), df)
    end

    # Step 4: Process interzone/aggregated case
    interzone_df.transmission_path_name = [
        "BUS$(bus_to_zone_map[row.Start_Zone])_to_BUS$(bus_to_zone_map[row.End_Zone])"
        for row in eachrow(interzone_df)
    ]

    interzone_df.Start_Zone = [bus_to_zone_map[row.Start_Zone] for row in eachrow(interzone_df)]
    interzone_df.End_Zone   = [bus_to_zone_map[row.End_Zone] for row in eachrow(interzone_df)]

    interzone_df.Column1 = ["BUS$(s)" for s in interzone_df.Start_Zone]
    interzone_df.Network_zones = ["z$(s)" for s in interzone_df.Start_Zone]
    interzone_df.Network_Lines = 1:nrow(interzone_df)

    agg_subfolder = joinpath(base_output_dir, "aggregated", file_key)
    mkpath(agg_subfolder)
    CSV.write(joinpath(agg_subfolder, basename(file_path)), interzone_df)

    return zone_bus_renumber_map
end

function process_resource_file(file_path::String, zone_to_bus_map, bus_to_zone_map, zone_bus_renumber_map, base_output_dir)
    df = CSV.read(file_path, DataFrame)

    # Determine folder name (e.g., "resources")
    path_parts = splitpath(file_path)
    folder_key = findfirst(p -> p in target_dirs, path_parts)
    if isnothing(folder_key)
        error("Could not infer folder name (e.g., 'resources') from path: $file_path")
    end
    file_key = path_parts[folder_key]

    resource_to_zone = Dict{String, Int}()
    resource_to_bus  = Dict{String, Int}()

    for (zone_id, buses) in zone_to_bus_map
        old_to_new = zone_bus_renumber_map[zone_id]

        # Filter resources that belong to this zone
        df_zone = filter(row -> row.Zone in buses, df)

        # Relabel Zone to local bus number
        df_zone.Zone = [old_to_new[row.Zone] for row in eachrow(df_zone)]

        # Update mappings
        for row in eachrow(df_zone)
            resource_to_zone[row.Resource] = zone_id
            resource_to_bus[row.Resource]  = row.Zone
        end

        # Save file
        if nrow(df_zone) > 0
            subfolder = joinpath(base_output_dir, "zone_$zone_id", file_key)
            mkpath(subfolder)
            CSV.write(joinpath(subfolder, basename(file_path)), df_zone)
        end
    end

    # Aggregated version
    df_agg = deepcopy(df)
    df_agg.Zone = [bus_to_zone_map[row.Zone] for row in eachrow(df_agg)]
    for row in eachrow(df_agg)
        resource_to_zone[row.Resource] = row.Zone
    end

    agg_subfolder = joinpath(base_output_dir, "aggregated", file_key)
    mkpath(agg_subfolder)
    CSV.write(joinpath(agg_subfolder, basename(file_path)), df_agg)

    return resource_to_zone, resource_to_bus
end

function copy_fuels_file(fuel_path, zone_to_bus_map, base_output_dir)

    #fuel_path = fuel_file[1]
    num_zones = length(zone_to_bus_map)

    # Determine original folder (e.g., "inputs", "resources", etc.)
    path_parts = splitpath(fuel_path)
    folder_key_index = findfirst(p -> p in target_dirs, path_parts)
    if isnothing(folder_key_index)
        error("Could not infer folder name (e.g., 'resources') from path: $fuel_path")
    end
    file_key = path_parts[folder_key_index]

    # Copy to each partitioned zone
    for zone_id in 1:num_zones
        dest_dir = joinpath(base_output_dir, "zone_$zone_id", file_key)
        mkpath(dest_dir)
        cp(fuel_path, joinpath(dest_dir, basename(fuel_path)), force=true)
    end

    # Copy to aggregated zone
    agg_dir = joinpath(base_output_dir, "aggregated", file_key)
    mkpath(agg_dir)
    cp(fuel_path, joinpath(agg_dir, basename(fuel_path)), force=true)

    return nothing
end


function process_generators_variability(file_path::String, zone_to_bus_map, all_resource_to_zone, base_output_dir)
    df = CSV.read(file_path, DataFrame)
    num_zones = length(zone_to_bus_map)

    # Extract the original folder name
    path_parts = splitpath(file_path)
    folder_key_index = findfirst(p -> p in target_dirs, path_parts)
    if isnothing(folder_key_index)
        error("Could not infer folder name (e.g., 'inputs') from path: $file_path")
    end
    file_key = path_parts[folder_key_index]

    # Separate Time_Index and resource columns
    resource_cols = setdiff(names(df), [:Time_Index])

    # For each zone, extract Time_Index + resources belonging to that zone
    for zone_id in 1:num_zones
        resources_in_zone = [r for r in resource_cols if haskey(all_resource_to_zone, r) && all_resource_to_zone[r] == zone_id]

        if isempty(resources_in_zone)
            @info "No resources found in zone $zone_id for $file_path"
            continue
        end

        df_zone = select(df, Cols(:Time_Index, resources_in_zone...))

        output_dir = joinpath(base_output_dir, "zone_$zone_id", file_key)
        mkpath(output_dir)
        CSV.write(joinpath(output_dir, basename(file_path)), df_zone)
    end

    # For aggregated case, just copy the full file
    agg_dir = joinpath(base_output_dir, "aggregated", file_key)
    mkpath(agg_dir)
    cp(file_path, joinpath(agg_dir, basename(file_path)), force=true)
    return nothing
end

function process_demand_data(file_path::String, zone_to_bus_map, bus_to_zone_map, zone_bus_renumber_map, base_output_dir)
    df = CSV.read(file_path, DataFrame)

    # Get first 9 columns (always preserved)
    meta_cols = names(df)[1:9]
    time_index_col = :Time_Index  # assumed to be in column 9
    demand_cols = names(df)[10:end]

    # Extract bus numbers from column names
    demand_col_buses = Dict(col => parse(Int, match(r"Demand_MW_z(\d+)", col).captures[1]) for col in demand_cols)

    # Determine folder key (e.g., "inputs", "resources", etc.)
    path_parts = splitpath(file_path)
    folder_key_index = findfirst(p -> p in target_dirs, path_parts)
    if isnothing(folder_key_index)
        error("Could not infer folder name (e.g., 'inputs') from path: $file_path")
    end
    file_key = path_parts[folder_key_index]

    # === Per-Zone Partitioning ===
    for (zone_id, buses) in zone_to_bus_map
        # Filter column names that match this zone's buses
        demand_cols_zone = [col for (col, bus) in demand_col_buses if bus in buses]

        if isempty(demand_cols_zone)
            @info "No demand columns for zone $zone_id"
            continue
        end

        # Select meta columns and zone-specific demand columns
        df_zone = select(df, Cols(meta_cols..., demand_cols_zone...))

        # Rename demand columns based on new local bus numbers
        old_to_new_bus = zone_bus_renumber_map[zone_id]
        new_names = Dict(
            col => Symbol("Demand_MW_z$(old_to_new_bus[demand_col_buses[col]])")
            for col in demand_cols_zone
        )
        rename!(df_zone, new_names)
        # Sort demand columns by new bus number (z1, z2, ..., zM)
        sorted_demand_cols = sort(collect(values(new_names)), by = x -> parse(Int, match(r"Demand_MW_z(\d+)", String(x)).captures[1]))
                    
        # Reorder columns: keep meta_cols first, then sorted demand columns
        df_zone = select(df_zone, Cols(meta_cols..., sorted_demand_cols...))

        # Write out the partitioned CSV
        dest_dir = joinpath(base_output_dir, "zone_$zone_id", file_key)
        mkpath(dest_dir)
        CSV.write(joinpath(dest_dir, basename(file_path)), df_zone)
    end
    # === Aggregated case ===
    agg_df = select(df, meta_cols...)  # base frame with metadata + Time_Index

    # Compute and store zone demand vectors first
    zone_demands = Dict{Symbol, Vector{Float64}}()

    for zone_id in sort(collect(keys(zone_to_bus_map)))  # ensure order z1, z2, ...
        buses = zone_to_bus_map[zone_id]
        demand_cols_zone = [col for (col, bus) in demand_col_buses if bus in buses]

        if isempty(demand_cols_zone)
            continue
        end

        zone_demand = reduce(+, eachcol(select(df, demand_cols_zone)))
        col_name = Symbol("Demand_MW_zone$zone_id")
        zone_demands[col_name] = zone_demand
    end

    # Append columns to agg_df in order
    for col_name in sort(collect(keys(zone_demands)))  # ensures zone1, zone2, ...
        agg_df[!, col_name] = zone_demands[col_name]
    end


    agg_dir = joinpath(base_output_dir, "aggregated", file_key)
    mkpath(agg_dir)
    CSV.write(joinpath(agg_dir, basename(file_path)), agg_df)
    return nothing
end

function partition_genx_system(zone_to_bus_map::Dict{Int, Vector{Int}}, bus_to_zone_map::Dict{Int, Int}; base_dir::String = @__DIR__)
    # All logic goes here as one encapsulated script
    # We'll call your above code internally, modularized and self-contained

    # === Setup ===
    println("Sorting files")
    target_dirs = Set(["system", "resources"])
    base_output_dir = joinpath(base_dir, "partitioned_systems")
    mkpath(base_output_dir)

    # Scan input directories
    files_by_folder = Dict{String, Vector{String}}()
    for (root, _, files) in walkdir(base_dir)
        folder_name = splitpath(root)[end]
        if folder_name in target_dirs
            full_paths = [joinpath(root, f) for f in files if isfile(joinpath(root, f))]
            files_by_folder[folder_name] = get(files_by_folder, folder_name, String[]) ∪ full_paths
        end
    end

    # Gather all files
    all_files = reduce(vcat, values(files_by_folder))

    # Setup zone/partition directories
    num_zones = length(zone_to_bus_map)
    for i in 1:num_zones
        for sub in target_dirs
            mkpath(joinpath(base_output_dir, "zone_$i", sub))
        end
    end
    for sub in target_dirs
        mkpath(joinpath(base_output_dir, "aggregated", sub))
    end

    # Define helper methods and process logic from your previous code
    # -- You don’t have to paste these here again, I can do that part if you confirm --

    # Main file handlers, in order of dependency
    network_files = filter(f -> occursin("network", lowercase(basename(f))), all_files)
    candidate_files = filter(f -> occursin("candidate", lowercase(basename(f))), all_files)
    resource_files = filter(f -> occursin.(r"(hydro|storage|thermal|vre)", lowercase(basename(f))), all_files)
    fuel_file = filter(f -> lowercase(basename(f)) == "fuels_data.csv", all_files)
    variability_file = filter(f -> lowercase(basename(f)) == "generators_variability.csv", all_files)
    demand_file = filter(f -> lowercase(basename(f)) == "demand_data.csv", all_files)

    # --- Main Processing ---
    println("Processing Network Data")
    # 1. Process network & candidate line files
    zone_bus_renumber_map = process_network_like_file(network_files[1], zone_to_bus_map, bus_to_zone_map, base_output_dir)
    process_network_like_file(candidate_files[1], zone_to_bus_map, bus_to_zone_map, base_output_dir)

    # 2. Process resource files
    println("Processing Resource Data")
    all_resource_to_zone = Dict{String, Int}()
    all_resource_to_bus = Dict{String, Int}()
    for f in resource_files
        r_to_z, r_to_b = process_resource_file(f, zone_to_bus_map, bus_to_zone_map, zone_bus_renumber_map, base_output_dir)
        merge!(all_resource_to_zone, r_to_z)
        merge!(all_resource_to_bus, r_to_b)
    end

    # 3. Copy fuel file
    println("Copying Fuels Data")
    if length(fuel_file) == 1
        copy_fuels_file(fuel_file[1], zone_to_bus_map, base_output_dir)
    else
        @warn "Fuels_data.csv not found or ambiguous"
    end

    # 4. Process variability file
    println("Processing Generator Variability Data")
    if length(variability_file) == 1
        process_generators_variability(variability_file[1], zone_to_bus_map, all_resource_to_zone, base_output_dir)
    else
        @warn "Generators_variability.csv not found"
    end

    # 5. Process demand file
    println("Processing Demand Data")
    if length(demand_file) == 1
        process_demand_data(demand_file[1], zone_to_bus_map, bus_to_zone_map, zone_bus_renumber_map, base_output_dir)
    else
        @warn "Demand_data.csv not found"
    end

    println("Finished Processing!")
    return nothing
end

bus_to_zone_map = Dict(1 => 1, 2 => 1, 3 => 2, 4 => 2)
zone_to_bus_map = Dict(1 => [1,2], 2 => [3,4])
base_dir = (@__DIR__)*"/Simple_four_bus_DC_OPF_v10"

partition_genx_system(zone_to_bus_map, bus_to_zone_map; base_dir = base_dir)

# need to run the aggregated case with no SOS constraints
# get the flow lines across all connecting transmission lines; existing flow and candidate flows
# Add thermal generator or load to each? 
# fill in information from results of aggregated case; 