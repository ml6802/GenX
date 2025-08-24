@doc raw"""
    load_generators_variability!(setup::Dict, path::AbstractString, inputs::Dict)

Read input parameters related to hourly maximum capacity factors for generators, storage, and flexible demand resources
"""
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
                    println("########################################")
                    println("Resource: ", r.name, " (ID: ", rid, ")")
                    #IS.show_time_series(r)
                    println("########################################")
                    IS.get_time_series_array(IS.SingleTimeSeries, r, "capacity_factor")
                    println("########################################")

                    # Filter for capacity_factor time series only
                    capacity_factor_indices = findall(name -> name == "capacity_factor", names)
                    
                    if !isempty(capacity_factor_indices)
                        # Use first capacity_factor time series found
                        cf_idx = capacity_factor_indices[1]
                        cf_name = names[cf_idx]
                        cf_type = types[cf_idx]
                        cf_feat = feats[cf_idx]
                        
                        # Extract time series values for capacity_factor
                        if !isempty(cf_feat)
                            temp_first_feats = Dict(Symbol.(keys(cf_feat)) .=> values(cf_feat))
                            
                            ts_vals = IS.get_time_series_values(cf_type, r, cf_name; temp_first_feats...)
                            #ts_vals = PSIP.get_data(IS.get_time_series(d, keys_[1]))
                            
                            if !isempty(ts_vals)
                                var_data = reduce(vcat, ts_vals)
                                
                                # Only use time series if length >= T
                                if length(var_data) >= T
                                    # Take only the first T values if longer than T
                                    inputs["pP_Max"][row_idx, :] = var_data[1:T]
                                    @info "Capacity factor data loaded for resource $(r.name) (used first $T of $(length(var_data)) values)"
                                    IS.show_time_series(r)
                                else
                                    @info "Capacity factor time series too short for resource $(r.name). Expected at least $T, got $(length(var_data)). Using default availability of 1.0."
                                    IS.show_time_series(r)
                                end
                            else
                                @info "No capacity factor time series values found for resource $(r.name). Using default availability of 1.0."
                                IS.show_time_series(r)
                            end
                        else
                            @info "No features found for capacity factor time series for resource $(r.name). Using default availability of 1.0."
                            IS.show_time_series(r)
                        end
                    else
                        @info "No capacity_factor time series found for resource $(r.name). Using default availability of 1.0."
                        IS.show_time_series(r)
                    end
                else
                    @info "No time series keys found for resource $(r.name). Using default availability of 1.0."
                    IS.show_time_series(r)
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