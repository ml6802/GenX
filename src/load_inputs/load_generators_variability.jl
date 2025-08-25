@doc raw"""
    load_generators_variability!(setup::Dict, path::AbstractString, inputs::Dict)

Read input parameters related to hourly maximum capacity factors for generators, storage, and flexible demand resources
"""
const PSIP = PowerSystemsInvestmentsPortfolios
function load_generators_variability!(setup::Dict, path::AbstractString, inputs::Dict)

    # Hourly capacity factors
    TDR_directory = joinpath(path, setup["TimeDomainReductionFolder"])
    # if TDR is used, my_dir = TDR_directory, else my_dir = "system"
    my_dir = get_systemfiles_path(setup, TDR_directory, path)

    filename = "Generators_variability.csv"
    gen_var = load_dataframe(joinpath(my_dir, filename))

    all_resources = inputs["RESOURCE_NAMES"]

    existing_variability = names(gen_var)
    for r in all_resources
        if r ∉ existing_variability
            @info "assuming availability of 1.0 for resource $r."
            ensure_column!(gen_var, r, 1.0)
        end
    end

    # Reorder DataFrame to R_ID order
    select!(gen_var, [:Time_Index; Symbol.(all_resources)])

    # Maximum power output and variability of each energy resource
    inputs["pP_Max"] = transpose(Matrix{Float64}(gen_var[1:inputs["T"],
        2:(inputs["G"] + 1)]))

    println(filename * " Successfully Read!")
end

@doc raw"""
    load_generators_variability!(setup::Dict, p::Portfolio, inputs::Dict)

Read input parameters from portfolio related to hourly maximum capacity factors for generators, storage, and flexible demand resources
"""
function load_generators_variability!(setup::Dict, p::Portfolio, inputs::Dict)

    # Collect all resources that need variability data
    resources = Vector{Any}()
    gen = collect(get_technologies(SupplyTechnology, p))
    storage = collect(get_technologies(StorageTechnology, p))
    append!(resources, gen)
    append!(resources, storage)
    
    # Sort resources by ID for consistent ordering
    sort!(resources, by = r -> r.id)
    
    T = inputs["T"]
    G = inputs["G"]
    
    # Initialize the pP_Max matrix (G resources x T time steps)
    inputs["pP_Max"] = ones(Float64, G, T)
    
    # Create mapping from resource ID to matrix row index
    all_resources = inputs["RESOURCE_NAMES"]
    resource_id_to_index = Dict{Int, Int}()
    for (idx, resource_name) in enumerate(all_resources)
        # Find the resource with this name to get its ID
        for r in resources
            if r.name == resource_name
                resource_id_to_index[r.id] = idx
                break
            end
        end
    end
    
    # Process each resource's time series data
    for r in resources
        rid = r.id
        if haskey(resource_id_to_index, rid)
            row_idx = resource_id_to_index[rid]
            
            # Try to get time series data for this resource
            try
                var_data = Float64[]
                keys_ = IS.get_time_series_keys(r)
                
                if !isempty(keys_)
                    # Extract time series metadata
                    names = [x.name for x in keys_]
                    types = [x.time_series_type for x in keys_]
                    feats = [x.features for x in keys_]

                    # Filter for capacity_factor time series only
                    capacity_factor_indices = findall(name -> name == "capacity_factor", names)
                    
                    if !isempty(capacity_factor_indices)
                        # Use first capacity_factor time series found
                        cf_idx = capacity_factor_indices[1]
                        cf_name = names[cf_idx]
                        cf_type = types[cf_idx]
                        
                        # Extract time series values for capacity_factor
                        ts_vals = IS.get_time_series_values(cf_type, r, cf_name)
                        if !isempty(ts_vals)
                            var_data = reduce(vcat, ts_vals)
                            
                            # Only use time series if length >= T
                            if length(var_data) >= T
                                # Take only the first T values if longer than T
                                inputs["pP_Max"][row_idx, :] = var_data[1:T]
                                @info "Capacity factor data loaded for resource $(r.name) (used first $T of $(length(var_data)) values)"
                            else
                                @info "Capacity factor time series too short for resource $(r.name). Expected at least $T, got $(length(var_data)). Using default availability of 1.0."
                            end
                        else
                            @info "No capacity factor time series values found for resource $(r.name). Using default availability of 1.0."
                        end
                    else
                        @info "No capacity_factor time series found for resource $(r.name). Using default availability of 1.0."
                    end
                else
                    @info "No time series keys found for resource $(r.name). Using default availability of 1.0."
                end
                
                # If var_data is all zeros or empty, try to load from CSV files
                if isempty(var_data) || all(x -> x == 0.0, var_data)
                    @info "Attempting to load time series from CSV files for resource $(r.name) (ID: $rid)"
                    
                    # Define the timeseries data files and their paths
                    timeseries_files = [
                        "CSP/DAY_AHEAD_Natural_Inflow.csv",
                        "Hydro/DAY_AHEAD_hydro.csv", 
                        "PV/DAY_AHEAD_pv.csv",
                        "RTPV/DAY_AHEAD_rtpv.csv",
                        "WIND/DAY_AHEAD_wind.csv"
                    ]
                    
                    # Try to find the resource ID in the CSV files
                    data_loaded = false
                    for ts_file in timeseries_files
                        try
                            # Construct the full path to the timeseries file
                            ts_path = joinpath(dirname(dirname(@__DIR__)), "example_systems", "RTS_Case_Latest", "RTS_Data", "timeseries_data_files", ts_file)
                            
                            if isfile(ts_path)
                                # Load the CSV file
                                ts_df = load_dataframe(ts_path)
                                
                                # Check if resource ID exists as a column (convert to string to match column names)
                                rid_str = string(rid)
                                if rid_str in names(ts_df)
                                    # Extract the time series data for this resource
                                    csv_var_data = ts_df[!, rid_str]
                                    
                                    # Remove any missing values and convert to Float64
                                    csv_var_data = Float64.(filter(!ismissing, csv_var_data))
                                    
                                    if length(csv_var_data) >= T
                                        # Take only the first T values
                                        inputs["pP_Max"][row_idx, :] = csv_var_data[1:T]
                                        @info "Successfully loaded time series from $ts_file for resource $(r.name) (ID: $rid) - used first $T of $(length(csv_var_data)) values"
                                        data_loaded = true
                                        break
                                    elseif length(csv_var_data) > 0
                                        @warn "Time series in $ts_file for resource $(r.name) (ID: $rid) too short: $(length(csv_var_data)) < $T. Using default availability of 1.0."
                                    end
                                end
                            end
                        catch csv_error
                            @debug "Error reading $ts_file for resource $(r.name): $csv_error"
                        end
                    end
                    
                    if !data_loaded
                        @info "No suitable time series data found in CSV files for resource $(r.name) (ID: $rid). Using default availability of 1.0."
                    end
                end
                
            catch e
                @warn "Error loading time series for resource $(r.name): $e. Using default availability of 1.0."
            end
        else
            @warn "Resource ID $rid not found in resource mapping. Skipping."
        end
    end

    println("Variable Generation Data Successfully Read!")
end