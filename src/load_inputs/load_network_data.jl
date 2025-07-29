@doc raw"""
    load_network_data!(setup::Dict, path::AbstractString, inputs_nw::Dict)

Function for reading input parameters related to the electricity transmission network
"""
function load_network_data!(setup::Dict, path::AbstractString, inputs_nw::Dict, filename::AbstractString)
    scale_factor = setup["ParameterScale"] == 1 ? ModelScalingFactor : 1
    println("Sacling setup: ", setup["ParameterScale"])
    println("Scaling factor: ", scale_factor)
    network_var = load_dataframe(joinpath(path, filename))

    as_vector(col::Symbol) = collect(skipmissing(network_var[!, col]))
    to_floats(col::Symbol) = convert(Array{Float64}, as_vector(col))

    # Number of zones in the network
    Z = maximum([length(as_vector(:Network_zones)), maximum(as_vector(:End_Zone))])
    inputs_nw["Z"] = Z
    # Number of lines in the network
    L = length(as_vector(:Network_Lines))
    inputs_nw["L"] = L

    candidate_flag = false
    if setup["DC_OPF"] == 1
        if isfile(joinpath(path, "Candidate_line.csv"))
            # Read candidate line data if it exists
            candidate_network_path = joinpath(path, "Candidate_line.csv")
            candidate_network_var = load_dataframe(candidate_network_path)
            candidate_flag = true
        else
            @warn("Candidate line data not found. Proceeding with existing network data. 
            Because the DC_OPF flag is active and Candidate_line.csv is nissing, GenX will not allow any transmission capacity expansion. 
            Set the DC_OPF flag to 0 if you want to optimize tranmission capacity expansion.")
        end
    end

    if candidate_flag
        as_vector_cand(col::Symbol) = collect(skipmissing(candidate_network_var[!, col]))
        to_floats_cand(col::Symbol) = convert(Array{Float64}, as_vector_cand(col))
        # Number of zones in the candidate network
        Z_cand = maximum([length(as_vector_cand(:Network_zones)), maximum(as_vector_cand(:End_Zone))])
        inputs_nw["Z_cand"] = Z_cand
        # Number of lines in the network
        L_cand = length(as_vector_cand(:Network_Lines))
        inputs_nw["L_cand"] = L_cand
        inputs_nw["pNet_Map_cand"] = load_network_map(candidate_network_var, Z_cand, L_cand)
    end

    # Topology of the network source-sink matrix
    inputs_nw["pNet_Map"] = load_network_map(network_var, Z, L)

    # Transmission capacity of the network (in MW)
    if !candidate_flag
        inputs_nw["pTrans_Max"] = to_floats(:Line_Max_Flow_MW) / scale_factor  # convert to GW
    else
        inputs_nw["pTrans_Max"] = create_extended_max_flow_vector(network_var, candidate_network_var)
    end

    if candidate_flag
        as_vector_cand(col::Symbol) = collect(skipmissing(candidate_network_var[!, col]))
        to_floats_cand(col::Symbol) = convert(Array{Float64}, as_vector_cand(col))
        # Number of zones in the candidate network
        Z_cand = length(as_vector_cand(:Network_zones))
        inputs_nw["Z_cand"] = Z_cand
        # Number of lines in the network
        L_cand = length(as_vector_cand(:Network_Lines))
        inputs_nw["L_cand"] = L_cand
        inputs_nw["pNet_Map_cand"] = load_network_map(candidate_network_var, Z_cand, L_cand)
    end

    # Transmission capacity of the network (in MW)
    #inputs_nw["pTrans_Max"] = zeros(Float64, L_cand)
    if !candidate_flag
        inputs_nw["pTrans_Max"] = to_floats(:Line_Max_Flow_MW) / scale_factor  # convert to GW
    else
        inputs_nw["pTrans_Max"] = create_extended_max_flow_vector(network_var, candidate_network_var) / scale_factor
    end
    
    # Loss of the existing lines in the network (in MW)
    if setup["Trans_Loss_Segments"] == 1
            # Line percentage Loss - valid for case when modeling losses as a fixed percent of absolute value of power flows
        inputs_nw["pPercent_Loss"] = to_floats(:Line_Loss_Percentage)
    elseif setup["Trans_Loss_Segments"] >= 2
        # Transmission line voltage (in kV)
        inputs_nw["kV"] = to_floats(:Line_Voltage_kV)
        # Transmission line resistance (in Ohms) - Used when modeling quadratic transmission losses
        inputs_nw["Ohms"] = to_floats(:Line_Resistance_Ohms)
    end
    if candidate_flag
        # Loss of the candidate lines in the network (in MW)
        if setup["Trans_Loss_Segments"] == 1
            # Line percentage Loss - valid for case when modeling losses as a fixed percent of absolute value of power flows
            inputs_nw["pPercent_Loss_cand"] = to_floats_cand(:Line_Loss_Percentage)
        elseif setup["Trans_Loss_Segments"] >= 2
            # Transmission line voltage (in kV)
            inputs_nw["kV_cand"] = to_floats_cand(:Line_Voltage_kV)
            # Transmission line resistance (in Ohms) - Used when modeling quadratic transmission losses
            inputs_nw["Ohms_cand"] = to_floats_cand(:Line_Resistance_Ohms)
        end
    end

    ## Inputs for the DC-OPF 
    if setup["DC_OPF"] == 1
        #if setup["NetworkExpansion"] == 1
        #    @warn("Because the DC_OPF flag is active, GenX will not allow any transmission capacity expansion. Set the DC_OPF flag to 0 if you want to optimize tranmission capacity expansion.")
        #    setup["NetworkExpansion"] = 0
        #end
        println("Reading DC-OPF values...")
        
        # Transmission line voltage (in kV)
        line_voltage_kV = to_floats(:Line_Voltage_kV)
        # Transmission line reactance (in Ohms)
        line_reactance_Ohms = to_floats(:Line_Reactance_Ohms)
        # Line angle limit (in radians)
        inputs_nw["Line_Angle_Limit"] = to_floats(:Angle_Limit_Rad)
        # DC-OPF coefficient for each line (in MW when not scaled, in GW when scaled) 
        # MW = (kV)^2/Ohms 
        if setup["ParameterScale"] == 1
            # DC-OPF coefficient for each line (in MW when not scaled, in GW when scaled) 
            # MW = (kV)^2/Ohms 
            inputs_nw["pDC_OPF_coeff"] = ((line_voltage_kV .^ 2) ./ line_reactance_Ohms) /
                                        scale_factor
        else
            # DC-OPF coefficient for each line (in MW when not scaled, in GW when scaled) 
            # MW = (kV)^2/Ohms 
            inputs_nw["pDC_OPF_coeff"] = (1 ./ line_reactance_Ohms)
        end
        if candidate_flag
            # Transmission line voltage (in kV)
            line_voltage_kV_cand = to_floats_cand(:Line_Voltage_kV)
            # Transmission line reactance (in Ohms)
            line_reactance_Ohms_cand = to_floats_cand(:Line_Reactance_Ohms)
            # Line angle limit (in radians)
            inputs_nw["Line_Angle_Limit_cand"] = to_floats_cand(:Angle_Limit_Rad)
            # DC-OPF coefficient for each line (in MW when not scaled, in GW when scaled) 
            # MW = (kV)^2/Ohms 
            if setup["ParameterScale"] == 1
                # DC-OPF coefficient for each line (in MW when not scaled, in GW when scaled) 
                # MW = (kV)^2/Ohms 
                inputs_nw["pDC_OPF_coeff_cand"] = ((line_voltage_kV_cand .^ 2) ./ line_reactance_Ohms_cand) /
                                        scale_factor
            else
                # DC-OPF coefficient for each line (in MW when not scaled, in GW when scaled) 
                # MW = (kV)^2/Ohms 
                inputs_nw["pDC_OPF_coeff_cand"] = (1 ./ line_reactance_Ohms_cand)
            end
            # Transmission line candidate expansion capacity (in MW)
            # DC-OPF transmission capacity (in MW) expansion data:
            inputs_nw["Line_Reinforcement_Cap_Size"] = to_floats_cand(:pMax_quantized_MW) /
                                                                                        scale_factor # convert to GW
            inputs_nw["Max_Trans_Cap"] = calculate_integer_quotients(candidate_network_var)
        end
        
        println("DC-OPF values successfully read!")
        println("DC-OPF Coefficients: ", inputs_nw["Max_Trans_Cap"])
        println("DC-OPF Coefficients: ", inputs_nw["pDC_OPF_coeff"])
        println("DC-OPF Coefficients (cand): ", inputs_nw["pDC_OPF_coeff_cand"])
        println("Maximum Transmission Capacity: ", inputs_nw["pTrans_Max"])
        println("Candidate Line Number Quantized: ", inputs_nw["Max_Trans_Cap"])
        
    end

    # Maximum possible flow after reinforcement for use in linear segments of piecewise approximation
    inputs_nw["pTrans_Max_Possible"] = inputs_nw["pTrans_Max"]

    if setup["NetworkExpansion"] == 1 && !candidate_flag
        # Read between zone network reinforcement costs per peak MW of capacity added
        inputs_nw["pC_Line_Reinforcement"] = to_floats_cand(:Line_Reinforcement_Cost_per_MWyr) /
                                             scale_factor # convert to million $/GW/yr with objective function in millions
        # Maximum reinforcement allowed in MW
        #NOTE: values <0 indicate no expansion possible
        inputs_nw["pMax_Line_Reinforcement"] = map(x -> max(0, x),
            to_floats(:Line_Max_Reinforcement_MW)) / scale_factor # convert to GW
        inputs_nw["pTrans_Max_Possible"] += inputs_nw["pMax_Line_Reinforcement"]
    elseif setup["NetworkExpansion"] == 1 && candidate_flag
            # Read between zone network reinforcement costs per peak MW of capacity added
            inputs_nw["pC_Line_Reinforcement"] = to_floats_cand(:Line_Reinforcement_Cost_per_MWyr) /
                                                 scale_factor # convert to million $/GW/yr with objective function in millions
            # Maximum reinforcement allowed in MW
            #NOTE: values <0 indicate no expansion possible
            inputs_nw["pMax_Line_Reinforcement"] = map(x -> max(0, x),
                to_floats_cand(:Line_Max_Reinforcement_MW)) / scale_factor # convert to GW
            println("Maximum line reinforcement (in GW): ", inputs_nw["pMax_Line_Reinforcement"])
            # Maximum possible flow after reinforcement for use in linear segments of piecewise approximation
            inputs_nw["pTrans_Max_Possible"] += inputs_nw["pMax_Line_Reinforcement"]
    end
    #println("Maximum possible flow after reinforcement (in GW): ", inputs_nw["pTrans_Max_Possible"])

    # Multi-Stage
    if setup["MultiStage"] == 1
        # Weighted Average Cost of Capital for Transmission Expansion
        if setup["NetworkExpansion"] >= 1
            inputs_nw["transmission_WACC"] = to_floats(:WACC)
            inputs_nw["Capital_Recovery_Period_Trans"] = to_floats(:Capital_Recovery_Period)
        end

        # Max Flow Possible on Each Line
        inputs_nw["pLine_Max_Flow_Possible_MW"] = to_floats(:Line_Max_Flow_Possible_MW) /
                                                  scale_factor # Convert to GW
    end

    # Transmission line (between zone) loss coefficient (resistance/voltage^2)
    inputs_nw["pTrans_Loss_Coef"] = zeros(Float64, L)
    if setup["Trans_Loss_Segments"] == 1
        inputs_nw["pTrans_Loss_Coef"] = inputs_nw["pPercent_Loss"]
    elseif setup["Trans_Loss_Segments"] >= 2
        # If zones are connected, loss coefficient is R/V^2 where R is resistance in Ohms and V is voltage in Volts
        inputs_nw["pTrans_Loss_Coef"] = (inputs_nw["Ohms"] / 10^6) ./
                                        (inputs_nw["kV"] / 10^3)^2 * scale_factor # 1/GW ***
    end

    ## Sets and indices for transmission losses and expansion
    inputs_nw["TRANS_LOSS_SEGS"] = setup["Trans_Loss_Segments"] # Number of segments used in piecewise linear approximations quadratic loss functions
    inputs_nw["LOSS_LINES"] = findall(inputs_nw["pTrans_Loss_Coef"] .!= 0) # Lines for which loss coefficients apply (are non-zero);

    if setup["NetworkExpansion"] == 1
        println("Reading Network Expansion values...")
        println(inputs_nw["pMax_Line_Reinforcement"])
        # Network lines and zones that are expandable have non-negative maximum reinforcement inputs
        inputs_nw["EXPANSION_LINES"] = findall(inputs_nw["pMax_Line_Reinforcement"] .> 0)
        inputs_nw["NO_EXPANSION_LINES"] = findall(inputs_nw["pMax_Line_Reinforcement"] .<= 0)
    end

    println(filename * " Successfully Read!")

    return network_var, candidate_network_var
end 

function calculate_integer_quotients(df::DataFrame)
    quotients = Int[] # Initialize an empty vector of Ints
    quotient = convert(Array{Float64}, collect(skipmissing(df.Line_Max_Reinforcement_MW))) ./ convert(Array{Float64}, collect(skipmissing(df.pMax_quantized_MW)))
    foreach(x -> push!(quotients, floor(Int, x)), quotient) # Approximate to nearest integer <= quotient
    return quotients
end


@doc raw"""
    load_network_map_from_list(network_var::DataFrame, Z, L, list_columns)

Loads the network map from a list-style interface
```
..., Network_Lines, Start_Zone, End_Zone, ...
                 1,           1,       2,
                 2,           1,       3,
```
"""
function load_network_map_from_list(network_var::DataFrame, Z, L, list_columns)
    start_col, end_col = list_columns
    mat = zeros(L, Z)
    start_zones = collect(skipmissing(network_var[!, start_col]))
    end_zones = collect(skipmissing(network_var[!, end_col]))
    for l in 1:L
        mat[l, start_zones[l]] = 1
        mat[l, end_zones[l]] = -1
    end
    mat
end

function calculate_integer_quotients(df::DataFrame)
    quotients = Int[] # Initialize an empty vector of Ints
    for row in eachrow(df)
        quotient = row.Line_Max_Reinforcement_MW / row.pMax_quantized_MW
        integer_quotient = floor(Int, quotient) # Approximate to nearest integer <= quotient
        push!(quotients, integer_quotient)
    end
    return quotients
end



@doc raw"""
    load_network_map_from_matrix(network_var::DataFrame, Z, L)

Loads the network map from a matrix-style interface
```
..., Network_Lines, z1, z2, z3, ...
                 1,  1, -1,  0,
                 2,  1,  0, -1,
```
This is equivalent to the list-style interface where the zone zN with entry +1 is the
starting zone of the line and the zone with entry -1 is the ending zone of the line.
"""
function load_network_map_from_matrix(network_var::DataFrame, Z, L)
    # Topology of the network source-sink matrix
    network_map_matrix_format_deprecation_warning()
    col = findall(s -> s == "z1", names(network_var))[1]
    mat = Matrix{Float64}(network_var[1:L, col:(col + Z - 1)])

    # Check if the matrix is square
    if size(mat, 1) != L || size(mat, 2) != Z
        error("The network map matrix is not square. Please check the input data.")
    end

    # Check if the matrix contains only 0, 1, -1 values
    if any(x -> x != 0 && x != 1 && x != -1, mat)
        error("The network map matrix contains invalid values. Please check the input data.")
    end

    # Convert to Float64
    mat = Float64.(mat)
end

function load_network_map(network_var::DataFrame, Z, L)
    columns = names(network_var)

    list_columns = ["Start_Zone", "End_Zone"]
    has_network_list = all([c in columns for c in list_columns])

    zones_as_strings = ["z" * string(i) for i in 1:Z]
    has_network_matrix = all([c in columns for c in zones_as_strings])

    instructions = """The transmission network should be specified in the form of a matrix
           (with columns z1, z2, ... zN) or in the form of lists (with Start_Zone, End_Zone),
           but not both. See the documentation for examples."""

    if has_network_list && has_network_matrix
        error("two types of transmission network map were provided.\n" * instructions)
    elseif !(has_network_list || has_network_matrix)
        error("no transmission network map was detected.\n" * instructions)
    elseif has_network_list
        load_network_map_from_list(network_var, Z, L, list_columns)
    elseif has_network_matrix
        load_network_map_from_matrix(network_var, Z, L)
    end
end

function network_map_matrix_format_deprecation_warning()
    @warn """Specifying the network map as a matrix is deprecated as of v0.4
  and will be removed in v0.5. Instead, use the more compact list-style format.

  ..., Network_Lines, Start_Zone, End_Zone, ...
                   1,          1,        2,
                   2,          1,        3,
                   3,          2,        3,
  """ maxlog=1
end

function create_extended_max_flow_vector(network_df::DataFrame, candidate_df::DataFrame)

    # Check if Line_Max_Flow_MW column exists in network_df
    if !("Line_Max_Flow_MW" in names(network_df))
        error("Column 'Line_Max_Flow_MW' not found in Network.csv.")
    end
### Mike's original code
    #=Extract the Line_Max_Flow_MW values from network_df
    max_flow_values = network_df.Line_Max_Flow_MW

    # Calculate the number of additional rows
    additional_rows = nrow(candidate_df) - nrow(network_df)=#
### Mike's original code
    as_vector(col::Symbol) = collect(skipmissing(network_df[!, col]))

    as_vector_cand(col::Symbol) = collect(skipmissing(candidate_df[!, col]))
    to_floats(col::Symbol) = convert(Array{Float64}, as_vector(col))
    # Extract the Line_Max_Flow_MW values from network_df
    #max_flow_values = network_df.Line_Max_Flow_MW
    max_flow_values = convert(Array{Float64}, as_vector(:Line_Max_Flow_MW))

    # Calculate the number of additional rows
    #additional_rows = nrow(candidate_df) - nrow(network_df)
    additional_rows =  length(as_vector_cand(:Network_Lines)) #- length(as_vector(:Network_Lines))
    println("Number of rows in candidate_df: ", length(as_vector_cand(:Network_Lines)))
    println("Number of rows in network_df: ", length(as_vector(:Network_Lines)))
    println("Number of additional rows: ", additional_rows)
    # Check if the number of additional rows is positive
    if additional_rows < 0
        error("The candidate DataFrame has fewer rows than the network DataFrame.")
    end

    # Append 0.0 for the additional rows
    append!(max_flow_values, zeros(Float64, additional_rows))

    return max_flow_values
end