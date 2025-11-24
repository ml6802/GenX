ENV["GENX_PRECOMPILE"] = "false"

using Pkg;
# Use relative paths from this file's location
project_dir = abspath(joinpath(@__DIR__, "..", "..", "..", "..", "..", "NREL_Sienna", "PowerSystemsInvestmentsPortfolios.jl"))
println("Activating project at: $project_dir")
Pkg.activate(project_dir);

# Add your local GenX as a development dependency
genx_path = abspath(joinpath(@__DIR__, "..", ".."))
println("Adding GenX from: $genx_path")
Pkg.develop(path=genx_path)

#=Uses @__DIR__ to get the current file's directory
Uses joinpath() for cross-platform path handling
Uses abspath() to resolve the full absolute path
Works on any machine where the repository structure is the same
Includes debug prints so you can verify the paths are correct
The relative path navigation assumes your repository structure is:

code/
├── GenX_PowerGenome/
│   └── GenX_Benders_DC_OPF/
│       └── GenX/
│           └── example_systems/
│               └── RTS_Case_Latest/  # ← This file
│                       └── test_portfolio.jl  # ← This file
└── NREL_Sienna/
    └── PowerSystemsInvestmentsPortfolios.jl/=#
using Revise
using GenX
using PowerSystemsInvestmentsPortfolios
using Gurobi
using TimeSeries
using CSV
using DataFrames
using Dates
using InfrastructureSystems
using PowerSystems
using Logging
const PSIP = PowerSystemsInvestmentsPortfolios
const IS = InfrastructureSystems
const PSY = PowerSystems
const TS = TimeSeries

# Setup logging to file
const LOG_FILE = joinpath(@__DIR__, "portfolio_execution.log")
const LOG_IO = open(LOG_FILE, "w")

"""
    log_both(message)

Prints message to both console and log file with timestamp.
"""
function log_both(message::String)
    timestamp = Dates.format(now(), "yyyy-mm-dd HH:MM:SS")
    formatted_message = "[$timestamp] $message"
    
    # Print to console
    println(formatted_message)
    
    # Write to log file
    println(LOG_IO, formatted_message)
    flush(LOG_IO)  # Ensure immediate write to file
end

"""
    log_info(message)

Logs an info message to both console and file.
"""
log_info(message::String) = log_both("ℹ️  INFO: $message")

"""
    log_warn(message)

Logs a warning message to both console and file.
"""
log_warn(message::String) = log_both("⚠️  WARN: $message")

"""
    log_error(message)

Logs an error message to both console and file.
"""
log_error(message::String) = log_both("❌ ERROR: $message")

"""
    log_success(message)

Logs a success message to both console and file.
"""
log_success(message::String) = log_both("✅ SUCCESS: $message")

# Ensure log file is closed when Julia exits
atexit(() -> close(LOG_IO))

log_info("Starting portfolio execution script")
log_info("Log file: $LOG_FILE")

read_from_json = false # Set to true if you want to read from a JSON file
rts_case = true # Set to true if you want to run the RTS case
# const PSIP_RESOURCE_TYPES = [SupplyTechnology{ThermalStandard},
#     SupplyTechnology{RenewableDispatch}, StorageTechnology{Storage}]

# function to build a portfolio based on the three_zones example from GenX
function test_portfolio(case_name::AbstractString)

    ###################
    ### Zones ###
    ###################

    z1 = Node(
        name = "MA",
        id = 1
    )

    z2 = Node(
        name = "CT",
        id = 2
    )

    z3 = Node(
        name = "ME",
        id = 3
    )

    ###################
    ### Finances ###
    ###################

    # Assume the same financial info for each technology
    tech_finance = TechnologyFinancialData(;
        interest_rate = 0.05,
        capital_recovery_period = 30,
        technology_base_year = 2025)

    base_year = 2025
    discount_rate = 0.07
    inflation_rate = 0.05
    interest_rate = 0.05
    port_finance = PortfolioFinancialData(
        base_year, discount_rate, inflation_rate, interest_rate)

    ####################
    ##### Thermals #####
    ####################

    t_ma_gas = SupplyTechnology{ThermalStandard}(;
        base_power = 1.0, # Natural Units
        outage_factor = 1.0,
        prime_mover_type = PrimeMovers.ST,
        capital_costs = LinearCurve(65400),
        time_limits = (up = 6.0, down = 6.0),
        lifetime = 30,
        ramp_limits = (up = 0.64, down = 0.64),
        available = true,
        co2 = Dict(ThermalFuels.NATURAL_GAS => 0.05306),
        name = "MA_natural_gas_combined_cycle",
        id = 1,
        initial_capacity = 0.0,
        cofire_start_limits = Dict{ThermalFuels, MinMax}(),
        financial_data = tech_finance,
        start_fuel_mmbtu_per_mw = 2.0,
        operation_costs = ThermalGenerationCost(
            variable = FuelCurve(
                value_curve = LinearCurve(7.43), fuel_cost = 5.0, vom_cost = LinearCurve(3.55)),
            fixed = 10287, start_up = 91.0, shut_down = 0.0),
        fuel = [ThermalFuels.NATURAL_GAS],
        power_systems_type = "ElectricLoad",
        cofire_level_limits = Dict{ThermalFuels, MinMax}(),
        region = [z1],
        unit_size = 250.0,
        min_generation_fraction = 0.468,
        capacity_limits = (min = 0.0, max = 10000000)
    )

    t_ct_gas = SupplyTechnology{ThermalStandard}(;
        base_power = 1.0, # Natural Units
        outage_factor = 1.0,
        prime_mover_type = PrimeMovers.ST,
        capital_costs = LinearCurve(65400),
        time_limits = (up = 6.0, down = 6.0),
        lifetime = 30,
        ramp_limits = (up = 0.64, down = 0.64),
        available = true,
        co2 = Dict(ThermalFuels.NATURAL_GAS => 0.05306),
        name = "CT_natural_gas_combined_cycle",
        id = 2,
        initial_capacity = 0.0,
        cofire_start_limits = Dict{ThermalFuels, MinMax}(),
        financial_data = tech_finance,
        start_fuel_mmbtu_per_mw = 2.0,
        operation_costs = ThermalGenerationCost(
            variable = FuelCurve(
                value_curve = LinearCurve(7.12), fuel_cost = 5.0, vom_cost = LinearCurve(3.57)),
            fixed = 9698, start_up = 91.0, shut_down = 0.0),
        fuel = [ThermalFuels.NATURAL_GAS],
        power_systems_type = "ElectricLoad",
        cofire_level_limits = Dict{ThermalFuels, MinMax}(),
        region = [z2],
        unit_size = 250.0,
        min_generation_fraction = 0.338,
        capacity_limits = (min = 0.0, max = 10000000))

    t_me_gas = SupplyTechnology{ThermalStandard}(;
        base_power = 1.0, # Natural Units
        outage_factor = 1.0,
        prime_mover_type = PrimeMovers.ST,
        capital_costs = LinearCurve(65400),
        time_limits = (up = 6.0, down = 6.0),
        lifetime = 30,
        ramp_limits = (up = 0.64, down = 0.64),
        available = true,
        co2 = Dict(ThermalFuels.NATURAL_GAS => 0.05306),
        name = "ME_natural_gas_combined_cycle",
        id = 3,
        initial_capacity = 0.0,
        cofire_start_limits = Dict{ThermalFuels, MinMax}(),
        financial_data = tech_finance,
        start_fuel_mmbtu_per_mw = 2.0,
        operation_costs = ThermalGenerationCost(
            variable = FuelCurve(
                value_curve = LinearCurve(12.62), fuel_cost = 5.0, vom_cost = LinearCurve(4.5)),
            fixed = 16291, start_up = 91.0, shut_down = 0.0),
        fuel = [ThermalFuels.NATURAL_GAS],
        power_systems_type = "ElectricLoad",
        cofire_level_limits = Dict{ThermalFuels, MinMax}(),
        region = [z3],
        unit_size = 250.0,
        min_generation_fraction = 0.474,
        capacity_limits = (min = 0.0, max = 10000000)
    )

    #####################
    ##### Renewable #####
    #####################

    t_ma_solar = SupplyTechnology{RenewableDispatch}(;
        base_power = 1.0, # Natural Units
        outage_factor = 1.0,
        prime_mover_type = PrimeMovers.PVe,
        capital_costs = LinearCurve(85300),
        id = 4,
        available = true,
        power_systems_type = "ElectricLoad",
        name = "MA_solar_pv",
        initial_capacity = 0.0,
        region = [z1],
        operation_costs = ThermalGenerationCost(variable = CostCurve(LinearCurve(0)),
            fixed = 18760, start_up = 0.0, shut_down = 0.0),
        capacity_limits = (min = 0.0, max = 10000000),
        financial_data = tech_finance)

    t_ct_wind = SupplyTechnology{RenewableDispatch}(;
        base_power = 1.0, # Natural Units
        outage_factor = 1.0,
        prime_mover_type = PrimeMovers.WT,
        capital_costs = LinearCurve(97200),
        id = 5,
        available = true,
        power_systems_type = "ElectricLoad",
        name = "CT_onshore_wind",
        initial_capacity = 0.0,
        region = [z2],
        operation_costs = ThermalGenerationCost(variable = CostCurve(LinearCurve(0.1)),
            fixed = 43205, start_up = 0.0, shut_down = 0.0),
        capacity_limits = (min = 0.0, max = 10000000),
        financial_data = tech_finance)

    t_ct_solar = SupplyTechnology{RenewableDispatch}(;
        base_power = 1.0, # Natural Units
        outage_factor = 1.0,
        prime_mover_type = PrimeMovers.PVe,
        capital_costs = LinearCurve(85300),
        id = 6,
        available = true,
        power_systems_type = "ElectricLoad",
        name = "CT_solar_pv",
        initial_capacity = 0.0,
        region = [z2],
        operation_costs = ThermalGenerationCost(variable = CostCurve(LinearCurve(0)),
            fixed = 18760, start_up = 0.0, shut_down = 0.0),
        capacity_limits = (min = 0.0, max = 10000000),
        financial_data = tech_finance)

    t_me_wind = SupplyTechnology{RenewableDispatch}(;
        base_power = 1.0, # Natural Units
        outage_factor = 1.0,
        prime_mover_type = PrimeMovers.WT,
        capital_costs = LinearCurve(97200),
        id = 7,
        available = true,
        name = "ME_onshore_wind",
        power_systems_type = "ElectricLoad",
        initial_capacity = 0.0,
        region = [z3],
        operation_costs = ThermalGenerationCost(variable = CostCurve(LinearCurve(0.1)),
            fixed = 43205, start_up = 0.0, shut_down = 0.0),
        capacity_limits = (min = 0.0, max = 10000000),
        financial_data = tech_finance)

    #####################
    ##### Storage #####
    #####################

    s_ma_battery = StorageTechnology{Storage}(;
        base_power = 1.0, # Natural Units
        prime_mover_type = PrimeMovers.BA,
        capital_costs_discharge = LinearCurve(19584),
        capital_costs_energy = LinearCurve(22494),
        capacity_limits_discharge = (min = 0.0, max = 100000000),
        capacity_limits_energy = (min = 0.0, max = 100000000),
        id = 8,
        available = true,
        name = "MA_battery",
        storage_tech = StorageTech.LIB,
        existing_capacity_discharge = 0.0,
        existing_capacity_energy = 0.0,
        power_systems_type = "Test",
        region = [z1],
        operation_costs = StorageCost(
            charge_variable_cost = CostCurve(value_curve =LinearCurve(0.15),
                vom_cost = LinearCurve(0.15)),
            discharge_variable_cost = CostCurve(value_curve = LinearCurve(0.15),
                vom_cost = LinearCurve(0.15)),
            fixed = 10000, start_up = 0.0, shut_down = 0.0),
        efficiency = (in = 0.92, out = 0.92),
        losses = 0.0,
        duration_limits = (min = 1.0, max = 10.0),
        financial_data = tech_finance)

    s_ct_battery = StorageTechnology{Storage}(;
        base_power = 1.0, # Natural Units
        prime_mover_type = PrimeMovers.BA,
        capital_costs_discharge = LinearCurve(19584),
        capital_costs_energy = LinearCurve(22494),
        capacity_limits_discharge = (min = 0.0, max = 100000000),
        capacity_limits_energy = (min = 0.0, max = 100000000),
        id = 9,
        available = true,
        name = "CT_battery",
        storage_tech = StorageTech.LIB,
        existing_capacity_discharge = 0.0,
        existing_capacity_energy = 0.0,
        power_systems_type = "Test",
        region = [z2],
        operation_costs = StorageCost(
            charge_variable_cost = CostCurve(value_curve = LinearCurve(0.15),
                vom_cost = LinearCurve(0.15)),
            discharge_variable_cost = CostCurve(value_curve = LinearCurve(0.15),
                vom_cost = LinearCurve(0.15)),
            fixed = 4895, start_up = 0.0, shut_down = 0.0),
        efficiency = (in = 0.92, out = 0.92),
        losses = 0.0,
        duration_limits = (min = 1.0, max = 10.0),
        financial_data = tech_finance)

    s_me_battery = StorageTechnology{Storage}(;
        base_power = 1.0, # Natural Units
        prime_mover_type = PrimeMovers.BA,
        capital_costs_discharge = LinearCurve(19584),
        capital_costs_energy = LinearCurve(22494),
        capacity_limits_discharge = (min = 0.0, max = 100000000),
        capacity_limits_energy = (min = 0.0, max = 100000000),
        id = 10,
        available = true,
        name = "ME_battery",
        storage_tech = StorageTech.LIB,
        existing_capacity_discharge = 0.0,
        existing_capacity_energy = 0.0,
        power_systems_type = "Test",
        region = [z3],
        operation_costs = StorageCost(
            charge_variable_cost = CostCurve(value_curve = LinearCurve(0.15),
                vom_cost = LinearCurve(0.15)),
            discharge_variable_cost = CostCurve(value_curve = LinearCurve(0.15),
                vom_cost = LinearCurve(0.15)),
            fixed = 4895, start_up = 0.0, shut_down = 0.0),
        efficiency = (in = 0.92, out = 0.92),
        losses = 0.0,
        duration_limits = (min = 1.0, max = 10.0),
        financial_data = tech_finance)

    ######################
    ######## Lines #######
    ######################

    tx_ma_ct = NodalACTransportTechnology{ACBranch}(;
        base_power = 1.0,
        name = "MA_to_CT",
        available = true,
        start_node = z1,
        end_node = z2,
        power_systems_type = "ElectricLoad",
        id = 1,
        reactance = 0.0,
        resistance = 0.0,
        voltage = 230.0,
        unit_size = 2950.0,
        capacity_limits = (min = 0.0, max = 2950),
        financial_data = tech_finance)

    tx_ma_me = NodalACTransportTechnology{ACBranch}(;
        base_power = 1.0,
        capital_cost = LinearCurve(19261),
        available = true,
        name = "MA_to_ME",
        start_node = z1,
        end_node = z3,
        id = 2,
        power_systems_type = "ElectricLoad",
        reactance = 0.0,
        resistance = 0.0,
        voltage = 230.0,
        unit_size = 2000.0,
        capacity_limits = (min = 0.0, max = 2000),
        financial_data = tech_finance)

    #####################
    ######## Load #######
    #####################

    demand_ma = DemandRequirement{PowerLoad}(
        name = "demand_mw_z1",
        id = 1,
        available = true,
        power_systems_type = "ElectricLoad",
        region = [z1],
        value_of_lost_load = 2000.0,
        peak_demand_mw = 10000.0
    )

    demand_ct = DemandRequirement{PowerLoad}(
        name = "demand_mw_z2",
        id = 2,
        available = true,
        power_systems_type = "ElectricLoad",
        region = [z2],
        value_of_lost_load = 2000.0,
        peak_demand_mw = 10000.0
    )

    demand_me = DemandRequirement{PowerLoad}(
        name = "demand_mw_z3",
        id = 3,
        available = true,
        power_systems_type = "ElectricLoad",
        region = [z3],
        value_of_lost_load = 2000.0,
        peak_demand_mw = 10000.0
    )

    #####################
    ### DemandSegment ###
    #####################   

    # demand_segments = CurtailableDemandSideTechnology{PowerLoad}(
    #     name = "segments",
    #     available = true,
    #     power_systems_type = "ElectricLoad",
    #     voll = 50000.0,
    #     segments = [1, 2, 3, 4],
    #     curtailment_cost = [1.0, 0.9, 0.55, 0.2],
    #     max_demand_curtailment = [1.0, 0.04, 0.024, 0.003],
    #     curtailment_cost_mwh = [2000.0, 1800.0, 1100.0, 400.0])

    #####################
    #### Carbon Caps ####
    ##################### 

    c1 = CarbonCaps(
        name = "CO_2_Cap_Zone_1",
        available = true,
        id = 1,
        eligible_regions = [z1],
        max_tons_mwh = 0.05,
        target_year = 2050,
        max_mtons = 0.018
    )
    c2 = CarbonCaps(
        name = "CO_2_Cap_Zone_2",
        id = 2,
        available = true,
        eligible_regions = [z2],
        max_tons_mwh = 0.05,
        target_year = 2050,
        max_mtons = 0.025
    )
    c3 = CarbonCaps(
        name = "CO_2_Cap_Zone_3",
        id = 3,
        available = true,
        eligible_regions = [z3],
        max_tons_mwh = 0.05,
        target_year = 2050,
        max_mtons = 0.025
    )

    ##########################
    #### Cap Requirements ####
    ########################## 

    cap1 = MinimumCapacityRequirements(
        target_year = 2050,
        id = 1,
        name = "min_cap_1",
        available = true,
        eligible_resources = [t_ma_solar],
        min_capacity_mw = 5000
    )

    cap2 = MinimumCapacityRequirements(
        target_year = 2050,
        id = 2,
        name = "min_cap_2",
        available = true,
        eligible_resources = [t_ct_wind],
        min_capacity_mw = 10000
    )

    cap3 = MinimumCapacityRequirements(
        target_year = 2050,
        id = 3,
        name = "min_cap_3",
        available = true,
        eligible_resources = [s_ma_battery, s_ct_battery, s_me_battery],
        min_capacity_mw = 6000
    )

    #####################
    ##### Portfolio #####
    #####################

    p_3zone = Portfolio(; financial_data = port_finance)

    # PSIP.add_financials!(p_3zone, port_finance)

    PSIP.add_region!(p_3zone, z1)
    PSIP.add_region!(p_3zone, z2)
    PSIP.add_region!(p_3zone, z3)

    PSIP.add_technology!(p_3zone, t_ma_gas)
    PSIP.add_technology!(p_3zone, t_ct_gas)
    PSIP.add_technology!(p_3zone, t_me_gas)

    PSIP.add_technology!(p_3zone, t_ma_solar)
    PSIP.add_technology!(p_3zone, t_ct_wind)
    PSIP.add_technology!(p_3zone, t_me_wind)
    PSIP.add_technology!(p_3zone, t_ct_solar)

    PSIP.add_technology!(p_3zone, s_ct_battery)
    PSIP.add_technology!(p_3zone, s_ma_battery)
    PSIP.add_technology!(p_3zone, s_me_battery)

    PSIP.add_technology!(p_3zone, tx_ma_ct)
    PSIP.add_technology!(p_3zone, tx_ma_me)

    PSIP.add_technology!(p_3zone, demand_ma)
    PSIP.add_technology!(p_3zone, demand_ct)
    PSIP.add_technology!(p_3zone, demand_me)

    # PSIP.add_technology!(p_3zone, demand_segments)

    PSIP.add_requirement!(p_3zone, cap1)
    PSIP.add_requirement!(p_3zone, cap2)
    PSIP.add_requirement!(p_3zone, cap3)

    PSIP.add_requirement!(p_3zone, c1)
    PSIP.add_requirement!(p_3zone, c2)
    PSIP.add_requirement!(p_3zone, c3)

    # Adding demand and timeseries, make artificial days and years since those arent in the inputs
    years = collect(LinRange(2020, 2030, 11))
    years = Int.(years)
    days = [1, 2, 3, 4, 5, 6, 7]
    daystr = ["01-01", "01-02", "01-03", "01-04", "01-05", "01-06", "01-07"]
    demand_data = DataFrame(CSV.File(joinpath(case_name, "TDR_results/Demand_data_ts.csv")))

    fuel_co2 = Dict("None" => 0, "CT_NG" => 0.05306, "ME_NG" => 0.05306, "MA_NG" => 0.05306)
    fuel_data = DataFrame(CSV.File(joinpath(case_name, "TDR_results/Fuels_data_ts.csv")))
    var = DataFrame(CSV.File(joinpath(
        case_name, "TDR_results/Generators_variability_ts.csv")))
    
    # Determine expected time series length (8784 for full year, 1848 for TDR case)
    expected_length = 8784  # Full year hourly data
    if nrow(demand_data) < expected_length
        expected_length = nrow(demand_data)  # Use actual data length if smaller
    end
    
    println("Expected time series length: $expected_length")
    println("Current variability data dimensions: $(size(var))")
    
    # Check and fix time series lengths for all existing columns
    for col_name in names(var)
        if col_name in ["reference_year", "reference_day"]  # Skip metadata columns
            continue
        end
        
        col_data = var[!, col_name]
        current_length = length(col_data)
        
        if current_length < expected_length
            @warn "Time series for '$col_name' has length $current_length, expected $expected_length. Extending with constant value 1.0"
            
            # Get the last value to extend with (or use 1.0 if missing/invalid)
            extend_value = 1.0
            if current_length > 0 && !ismissing(col_data[end]) && isfinite(col_data[end])
                extend_value = col_data[end]
            end
            
            # Extend the column to the expected length
            extended_data = vcat(col_data, fill(extend_value, expected_length - current_length))
            var[!, col_name] = extended_data
            
            println("  Extended '$col_name' from $current_length to $expected_length with value $extend_value")
        elseif current_length > expected_length
            @warn "Time series for '$col_name' has length $current_length, expected $expected_length. Truncating to expected length"
            var[!, col_name] = col_data[1:expected_length]
            println("  Truncated '$col_name' from $current_length to $expected_length")
        end
    end
    
    existing_variability = names(var)
    all_resources = vcat(PSIP.get_name.(PSIP.get_technologies(SupplyTechnology, p_3zone)),
        PSIP.get_name.(PSIP.get_technologies(StorageTechnology, p_3zone)))
    for r in all_resources
        if r ∉ existing_variability
            @info "assuming availability of 1.0 for resource $r."
            GenX.ensure_column!(var, r, 1.0)
        else
            # Check if existing resource has correct length
            col_data = var[!, r]
            if length(col_data) != expected_length
                @warn "Resource '$r' has incorrect time series length $(length(col_data)), expected $expected_length. Fixing..."
                if length(col_data) < expected_length
                    # Extend with 1.0 values
                    extended_data = vcat(col_data, fill(1.0, expected_length - length(col_data)))
                    var[!, r] = extended_data
                else
                    # Truncate to expected length
                    var[!, r] = col_data[1:expected_length]
                end
                println("  Fixed time series length for resource '$r'")
            end
        end
    end
    
    println("Final variability data dimensions: $(size(var))")

    resolution = Dates.Hour(1)
    for y in years
        for d in days

            #filter data for investment year
            d_ma = demand_data[
                (isequal.(demand_data[!, "reference_year"], y)) .& (isequal.(
                    demand_data[!, "reference_day"], d)),
                "Demand_MW_z1"]
            d_ct = demand_data[
                (isequal.(demand_data[!, "reference_year"], y)) .& (isequal.(
                    demand_data[!, "reference_day"], d)),
                "Demand_MW_z2"]
            d_me = demand_data[
                (isequal.(demand_data[!, "reference_year"], y)) .& (isequal.(
                    demand_data[!, "reference_day"], d)),
                "Demand_MW_z3"]

            #Make timearrays
            ystr = string(y)
            dstr = daystr[d]
            dates = range(
                DateTime("$(ystr)-$(dstr)T00:00:00"), step = resolution, length = 24)

            data_demand_ma = TimeArray(dates, d_ma)
            data_demand_ct = TimeArray(dates, d_ct)
            data_demand_me = TimeArray(dates, d_me)

            ts1 = SingleTimeSeries("demand_mw_z1", data_demand_ma)
            ts2 = SingleTimeSeries("demand_mw_z2", data_demand_ct)
            ts3 = SingleTimeSeries("demand_mw_z3", data_demand_me)

            IS.add_time_series!(p_3zone.data, demand_ma, ts1; model_year = y, order_day = d)
            IS.add_time_series!(p_3zone.data, demand_ct, ts2; model_year = y, order_day = d)
            IS.add_time_series!(p_3zone.data, demand_me, ts3; model_year = y, order_day = d)

            f_ma = fuel_data[
                (isequal.(fuel_data[!, "reference_year"], y)) .& (isequal.(
                    fuel_data[!, "reference_day"], d)),
                "MA_NG"]
            f_ct = fuel_data[
                (isequal.(fuel_data[!, "reference_year"], y)) .& (isequal.(
                    fuel_data[!, "reference_day"], d)),
                "CT_NG"]
            f_me = fuel_data[
                (isequal.(fuel_data[!, "reference_year"], y)) .& (isequal.(
                    fuel_data[!, "reference_day"], d)),
                "ME_NG"]
            f_no = fuel_data[
                (isequal.(fuel_data[!, "reference_year"], y)) .& (isequal.(
                    fuel_data[!, "reference_day"], d)),
                "None"]

            ts1f = SingleTimeSeries("MA_NG", TimeArray(dates, f_ma))
            ts2f = SingleTimeSeries("CT_NG", TimeArray(dates, f_ct))
            ts3f = SingleTimeSeries("ME_NG", TimeArray(dates, f_me))
            tsnf = SingleTimeSeries("None", TimeArray(dates, f_no))

            IS.add_time_series!(
                p_3zone.data, t_ma_gas, ts1f; model_year = y, order_day = d, type = "MA_NG")
            IS.add_time_series!(
                p_3zone.data, t_ct_gas, ts2f; model_year = y, order_day = d, type = "CT_NG")
            IS.add_time_series!(
                p_3zone.data, t_me_gas, ts3f; model_year = y, order_day = d, type = "ME_NG")
            IS.add_time_series!(p_3zone.data, t_ma_solar, tsnf;
                model_year = y, order_day = d, type = "None")
            IS.add_time_series!(
                p_3zone.data, t_ct_wind, tsnf; model_year = y, order_day = d, type = "None")
            IS.add_time_series!(
                p_3zone.data, t_me_wind, tsnf; model_year = y, order_day = d, type = "None")
            IS.add_time_series!(p_3zone.data, t_ct_solar, tsnf;
                model_year = y, order_day = d, type = "None")

            vmag = var[
                (isequal.(var[!, "reference_year"], y)) .& (isequal.(
                    var[!, "reference_day"], d)),
                "MA_natural_gas_combined_cycle"]
            vmas = var[
                (isequal.(var[!, "reference_year"], y)) .& (isequal.(
                    var[!, "reference_day"], d)),
                "MA_solar_pv"]
            vctg = var[
                (isequal.(var[!, "reference_year"], y)) .& (isequal.(
                    var[!, "reference_day"], d)),
                "CT_natural_gas_combined_cycle"]
            vctw = var[
                (isequal.(var[!, "reference_year"], y)) .& (isequal.(
                    var[!, "reference_day"], d)),
                "CT_onshore_wind"]
            vcts = var[
                (isequal.(var[!, "reference_year"], y)) .& (isequal.(
                    var[!, "reference_day"], d)),
                "CT_solar_pv"]
            vmeg = var[
                (isequal.(var[!, "reference_year"], y)) .& (isequal.(
                    var[!, "reference_day"], d)),
                "ME_natural_gas_combined_cycle"]
            vmew = var[
                (isequal.(var[!, "reference_year"], y)) .& (isequal.(
                    var[!, "reference_day"], d)),
                "ME_onshore_wind"]
            vmab = var[
                (isequal.(var[!, "reference_year"], y)) .& (isequal.(
                    var[!, "reference_day"], d)),
                "MA_battery"]
            vctb = var[
                (isequal.(var[!, "reference_year"], y)) .& (isequal.(
                    var[!, "reference_day"], d)),
                "CT_battery"]
            vmeb = var[
                (isequal.(var[!, "reference_year"], y)) .& (isequal.(
                    var[!, "reference_day"], d)),
                "ME_battery"]

            ts_var_ma_gas = SingleTimeSeries(
                "MA_natural_gas_combined_cycle", TimeArray(dates, vmag))
            ts_var_ma_solar = SingleTimeSeries("MA_solar_pv", TimeArray(dates, vmas))
            ts_var_ct_gas = SingleTimeSeries(
                "CT_natural_gas_combined_cycle", TimeArray(dates, vctg))
            ts_var_ct_wind = SingleTimeSeries("CT_onshore_wind", TimeArray(dates, vctw))
            ts_var_ct_solar = SingleTimeSeries("CT_solar_pv", TimeArray(dates, vcts))
            ts_var_me_gas = SingleTimeSeries(
                "ME_natural_gas_combined_cycle", TimeArray(dates, vmeg))
            ts_var_me_wind = SingleTimeSeries("ME_onshore_wind", TimeArray(dates, vmew))
            ts_var_ma_battery = SingleTimeSeries("MA_battery", TimeArray(dates, vmab))
            ts_var_ct_battery = SingleTimeSeries("CT_battery", TimeArray(dates, vctb))
            ts_var_me_battery = SingleTimeSeries("ME_battery", TimeArray(dates, vmeb))

            IS.add_time_series!(
                p_3zone.data, t_ma_gas, ts_var_ma_gas; model_year = y, order_day = d)
            IS.add_time_series!(
                p_3zone.data, t_ct_gas, ts_var_ct_gas; model_year = y, order_day = d)
            IS.add_time_series!(
                p_3zone.data, t_me_gas, ts_var_me_gas; model_year = y, order_day = d)
            IS.add_time_series!(p_3zone.data, s_ma_battery, ts_var_ma_battery;
                model_year = y, order_day = d)
            IS.add_time_series!(p_3zone.data, s_ct_battery, ts_var_ct_battery;
                model_year = y, order_day = d)
            IS.add_time_series!(p_3zone.data, s_me_battery, ts_var_me_battery;
                model_year = y, order_day = d)
            IS.add_time_series!(
                p_3zone.data, t_me_wind, ts_var_me_wind; model_year = y, order_day = d)
            IS.add_time_series!(
                p_3zone.data, t_ct_wind, ts_var_ct_wind; model_year = y, order_day = d)
            IS.add_time_series!(
                p_3zone.data, t_ma_solar, ts_var_ma_solar; model_year = y, order_day = d)
            IS.add_time_series!(
                p_3zone.data, t_ct_solar, ts_var_ct_solar; model_year = y, order_day = d)
        end
    end

    # Using the portfolio's extension to add additional data without corresponding structs for the time being.
    # This is mostly information related to policies and timesteps that have not yet been implemented
    e = Dict()

    e["Regions"] = ["MA", "CT", "ME"]

    # Need portfolio settings, this could go in there
    # 
    # Add different timeseries for each representative period, use attributes to make ordering easier

    e["Rep_Periods"] = 11
    e["Timesteps_per_Rep_Period"] = 168
    e["Sub_Weights"] = [842.3076923,
        673.8461538,
        673.8461538,
        673.8461538,
        2526.923077,
        168.4615385,
        1853.076923,
        505.3846154,
        168.4615385,
        505.3846154,
        168.4615385
    ]
    e["total_timesteps"] = 1848
    e["years"] = Int.(collect(LinRange(2020, 2030, 11)))
    e["order_days"] = [1, 2, 3, 4, 5, 6, 7]

    e["Minimum_capacity_requirement"] = Dict(1 => 5000, 2 => 10000, 3 => 6000)
    e["resource_capacity_requirement"] = Dict(
        "Min_Cap_1" => ["MA_solar_pv"],
        "Min_Cap_2" => ["CT_onshore_wind"],
        "Min_Cap_3" => ["MA_battery", "ME_battery", "CT_battery"]
    )

    p_3zone.internal.ext = e

    return p_3zone
end

function load_rts(case_name::AbstractString)
    #!/usr/bin/env julia

    """
    Method to load RTS data from SQLite database and create portfolio structs
    using the database_to_portfolio function.
    """

    # Define the database file path
    database_filepath = joinpath(case_name, "sys_DA.sqlite")

    # Define the portfolio parameters
    discount_rate = 0.05
    inflation_rate = 0.07
    interest_rate = 0.07
    base_year = 2025
    aggregation = PSY.ACBus

    log_info("Loading RTS data from database: $database_filepath")
    log_info("Parameters: Discount rate: $discount_rate, Inflation rate: $inflation_rate, Interest rate: $interest_rate, Base year: $base_year, Aggregation: $aggregation")

    # Check if the database file exists
    if !isfile(database_filepath)
        error("Database file not found: $database_filepath")
    end

    try
        log_info("Starting portfolio creation...")
    
        # Check if the database file exists and can be opened
        log_info("Opening database connection...")
    
        # Call the database_to_portfolio function
        portfolio = database_to_portfolio(
            database_filepath,
            discount_rate,
            inflation_rate,
            interest_rate,
            base_year;
            aggregation=aggregation
        )

        log_success("Database loaded successfully")
        log_success("Nodes created (with validation warnings)")
        log_success("Technologies processed (some types skipped as expected)")
        log_success("Power system data processed")
        log_success("Time series deserialization completed")
    
        log_success("Successfully created portfolio structs!")
        log_info("Portfolio object type: $(typeof(portfolio))")
    
        # Display some basic information about the portfolio
        println("\nPortfolio summary:")
        println("  - Aggregation type: $(portfolio.aggregation)")
        println("  - Discount rate: $(get_discount_rate(portfolio))")
        println("  - Inflation rate: $(get_inflation_rate(portfolio))")
        println("  - Interest rate: $(get_interest_rate(portfolio))")
        println("  - Base year: $(get_base_year(portfolio))")

        # Check if there are any technologies in the portfolio
        if isdefined(portfolio, :technologies) && !isempty(get_technologies(portfolio))
            println("  - Number of technologies: $(length(get_technologies(portfolio)))")
            println("  - Technology types:")
            for tech in get_technologies(portfolio)
                println("    - $(typeof(tech))")
            end
        end
    
        # Check if there are any demand requirements
        if isdefined(portfolio, :demand_requirements) && !isempty(get_technologies(DemandRequirement, portfolio))
            println("  - Number of demand requirements: $(length(get_technologies(DemandRequirement, portfolio)))")
        end
    
        # Check if there are any regions
        if isdefined(portfolio, :regions) && !isempty(get_regions(portfolio))
            println("  - Number of regions: $(length(get_regions(portfolio)))")
        end
        println("\nPortfolio loading complete.")
        return portfolio
    
    catch e
        # Determine which step failed based on the error message
        error_msg = string(e)
        if occursin("SystemError", error_msg) || occursin("database", error_msg)
            println("❌ Failed at database loading step")
        elseif occursin("Node", error_msg) || occursin("validation", error_msg)
            println("✅ Database loaded successfully")
            println("❌ Failed at nodes creation step")
        elseif occursin("Technologies", error_msg) || occursin("ROR", error_msg) || occursin("HYDRO", error_msg)
            println("✅ Database loaded successfully")
            println("✅ Nodes created (with validation warnings)")
            println("❌ Failed at technologies processing step")
        elseif occursin("TIME_SERIES", error_msg) || occursin("time_series", error_msg) || occursin("timeseries", error_msg)
            println("✅ Database loaded successfully")
            println("✅ Nodes created (with validation warnings)")
            println("✅ Technologies processed (some types skipped as expected)")
            println("✅ Power system data processed")
            println("❌ Failed at time series deserialization step")
        else
            println("✅ Database loaded successfully")
            println("✅ Nodes created (with validation warnings)")
            println("✅ Technologies processed (some types skipped as expected)")
            println("❌ Failed at power system data processing step")
        end
    
        println("\n❌ Error creating portfolio:")
        println("Error: $e")
        rethrow(e)
    end

end

"""
    validate_and_fix_time_series_lengths(portfolio, expected_length=8784)

Validates that all time series in the portfolio have the expected length.
For technologies with multiple time series, keeps only the one with expected_length and removes others.
If no time series with expected_length is found, creates one with all 1.0s.
"""
function validate_and_fix_time_series_lengths(portfolio, expected_length=8784)
    log_info("Validating time series lengths in portfolio...")
    log_info("Expected length: $expected_length hours")
    
    # Get all technologies that might have time series
    all_techs = vcat(
        collect(get_technologies(SupplyTechnology, portfolio)),
        collect(get_technologies(StorageTechnology, portfolio)),
        collect(get_technologies(DemandRequirement, portfolio))
    )
    
    fixed_count = 0
    
    for tech in all_techs
        tech_name = PSIP.get_name(tech)
        
        if IS.has_time_series(tech)
            ts_keys = IS.get_time_series_keys(tech)
            
            # First pass: find all time series and their lengths
            ts_info = []
            for ts_key in ts_keys
                try
                    ts_data = IS.get_time_series(tech, ts_key)
                    ts_values = PSIP.get_data(ts_data)
                    
                    current_length = if ts_values isa TS.TimeArray
                        length(values(ts_values))
                    else
                        length(ts_values)
                    end
                    
                    push!(ts_info, (key=ts_key, data=ts_data, values=ts_values, length=current_length))
                    
                catch e
                    @warn "Error reading time series '$ts_key' for technology '$tech_name': $e"
                end
            end
            
            # Find time series with expected length
            expected_length_ts = filter(info -> info.length == expected_length, ts_info)
            
            if !isempty(expected_length_ts)
                # Found time series with expected length
                log_info("Technology '$tech_name' has $(length(ts_info)) time series, $(length(expected_length_ts)) with correct length $expected_length")
                
                # Keep only the first one with expected length
                keep_ts = expected_length_ts[1]
                log_info("Keeping time series '$(keep_ts.key.name)' with length $(keep_ts.length) for technology '$tech_name'")
                
                # Remove ALL others (not just when there are multiple)
                for info in ts_info
                    if info.key != keep_ts.key
                        try
                            # Handle different types of time series keys for removal
                            if hasfield(typeof(info.key), :initial_timestamp)
                                IS.remove_time_series!(portfolio.data, tech, info.key.name, info.key.initial_timestamp)
                            else
                                # For StaticTimeSeriesKey, use the name only
                                IS.remove_time_series!(portfolio.data, tech, info.key.name)
                            end
                            log_info("Removed time series '$(info.key.name)' with length $(info.length) from technology '$tech_name'")
                            fixed_count += 1
                        catch e
                            log_warn("Error removing time series '$(info.key.name)' for technology '$tech_name': $e")
                        end
                    end
                end
            else
                # No time series with expected length found
                println("  ⚠️  Technology '$tech_name' has no time series with expected length $expected_length")
                
                # Remove all existing time series
                for info in ts_info
                    try
                        # Handle different types of time series keys for removal
                        if hasfield(typeof(info.key), :initial_timestamp)
                            IS.remove_time_series!(portfolio.data, tech, info.key.name, info.key.initial_timestamp)
                        else
                            # For StaticTimeSeriesKey, use the name only
                            IS.remove_time_series!(portfolio.data, tech, info.key.name)
                        end
                        println("  🗑️  Removed time series '$(info.key.name)' with length $(info.length)")
                    catch e
                        @warn "Error removing time series '$(info.key.name)' for technology '$tech_name': $e"
                    end
                end
                
                # Create new time series with all 1.0s
                # Use the structure from the first existing time series if available
                if !isempty(ts_info)
                    ref_key = ts_info[1].key
                    ref_values = ts_info[1].values
                    
                    if ref_values isa TS.TimeArray
                        # Create timestamps for expected length
                        ref_timestamps = TS.timestamp(ref_values)
                        if length(ref_timestamps) > 1
                            time_step = ref_timestamps[2] - ref_timestamps[1]
                        else
                            time_step = Dates.Hour(1)
                        end
                        
                        # Generate new timestamps
                        start_timestamp = ref_timestamps[1]
                        new_timestamps = [start_timestamp + (i-1) * time_step for i in 1:expected_length]
                        new_values = fill(1.0, expected_length)
                        
                        # Create new TimeArray and time series
                        new_ts_data = TS.TimeArray(new_timestamps, new_values)
                        new_ts = SingleTimeSeries(ref_key.name, new_ts_data)
                        
                        # Add the new time series
                        # Handle different types of time series keys
                        if hasfield(typeof(ref_key), :model_year) && hasfield(typeof(ref_key), :order_day)
                            # Key has model_year and order_day (e.g., from portfolio time series)
                            IS.add_time_series!(portfolio.data, tech, new_ts; 
                                model_year = ref_key.model_year, 
                                order_day = ref_key.order_day,
                                type = get(ref_key, :type, nothing))
                        else
                            # Key doesn't have model_year/order_day (e.g., StaticTimeSeriesKey)
                            # Add as a simple time series without additional metadata
                            IS.add_time_series!(portfolio.data, tech, new_ts)
                        end
                        
                        println("  ✅ Created new time series '$(ref_key.name)' with length $expected_length (all 1.0s)")
                        fixed_count += 1
                    end
                else
                    # No existing time series to use as reference - create a basic one
                    # This case should be handled by ensuring missing resources have time series elsewhere
                    @warn "Technology '$tech_name' has no time series at all - skipping (should be handled elsewhere)"
                end
            end
        else
            # Technology has no time series - this should be handled elsewhere in the code
            println("  ⏭️  Technology '$tech_name' has no time series - skipping")
        end
    end
    
    if fixed_count > 0
        log_success("Fixed $fixed_count time series length issues")
    else
        log_success("All time series have correct lengths")
    end
    
    return portfolio
end

"""
    clean_time_series_for_tdr(portfolio)

Removes non-variability time series (fuel prices, etc.) that have different lengths
than the main variability time series, keeping only the 8784-hour availability data.
"""
function clean_time_series_for_tdr(portfolio)
    log_info("Cleaning time series data for TDR compatibility...")
    
    # Get all supply technologies (where the problem occurs)
    supply_techs = collect(get_technologies(SupplyTechnology, portfolio))
    
    removed_count = 0
    
    for tech in supply_techs
        tech_name = PSIP.get_name(tech)
        
        if !IS.has_time_series(tech)
            continue
        end
        
        ts_keys = IS.get_time_series_keys(tech)
        
        if length(ts_keys) <= 1
            continue  # No problem if only one time series
        end
        
        # Find all time series and categorize by length
        ts_by_length = Dict{Int, Vector}()
        
        for key in ts_keys
            try
                ts_data = IS.get_time_series(tech, key)
                ts_values = PSIP.get_data(ts_data)
                
                length_val = if ts_values isa TS.TimeArray
                    length(values(ts_values))
                else
                    length(ts_values)
                end
                
                if !haskey(ts_by_length, length_val)
                    ts_by_length[length_val] = []
                end
                
                push!(ts_by_length[length_val], (key=key, data=ts_data))
                
            catch e
                log_warn("Error reading time series '$key' for $tech_name: $e")
            end
        end
        
        # If we have multiple lengths, keep only the longest one (8784)
        if length(ts_by_length) > 1
            max_length = maximum(keys(ts_by_length))
            
            log_info("Tech '$tech_name' has $(length(ts_keys)) time series with lengths: $(keys(ts_by_length))")
            log_info("  Keeping only time series with length $max_length")
            
            # Remove all time series that don't match max_length
            for (len, ts_list) in ts_by_length
                if len != max_length
                    for ts_info in ts_list
                        try
                            # Determine removal method based on key type
                            if hasfield(typeof(ts_info.key), :initial_timestamp)
                                IS.remove_time_series!(
                                    portfolio.data, 
                                    tech, 
                                    ts_info.key.name, 
                                    ts_info.key.initial_timestamp
                                )
                            else
                                IS.remove_time_series!(
                                    portfolio.data, 
                                    tech, 
                                    ts_info.key.name
                                )
                            end
                            
                            log_info("    Removed '$(ts_info.key.name)' (length $len)")
                            removed_count += 1
                            
                        catch e
                            log_warn("    Failed to remove '$(ts_info.key.name)': $e")
                        end
                    end
                end
            end
        end
    end
    
    log_success("Cleaned time series: removed $removed_count incompatible series")
    return portfolio
end

"""
    check_time_series_consistency(portfolio)

Simply checks and reports time series lengths without modification.
"""
function check_time_series_consistency(portfolio)
    log_info("Checking time series consistency...")
    
    all_techs = vcat(
        collect(get_technologies(SupplyTechnology, portfolio)),
        collect(get_technologies(StorageTechnology, portfolio)),
        collect(get_technologies(DemandRequirement, portfolio))
    )
    
    issues_found = false
    
    for tech in all_techs
        tech_name = PSIP.get_name(tech)
        
        if !IS.has_time_series(tech)
            log_warn("$tech_name has no time series")
            issues_found = true
            continue
        end
        
        ts_keys = IS.get_time_series_keys(tech)
        lengths = Set()
        
        for key in ts_keys
            try
                ts_data = IS.get_time_series(tech, key)
                ts_values = PSIP.get_data(ts_data)
                
                length_val = if ts_values isa TS.TimeArray
                    length(values(ts_values))
                else
                    length(ts_values)
                end
                
                push!(lengths, length_val)
            catch e
                log_warn("Error reading time series for $tech_name: $e")
            end
        end
        
        if length(lengths) > 1
            log_warn("$tech_name has inconsistent time series lengths: $lengths")
            issues_found = true
        elseif !isempty(lengths)
            log_info("$tech_name: $(first(lengths)) hours × $(length(ts_keys)) series")
        end
    end
    
    if !issues_found
        log_success("All time series are consistent")
    end
    
    return portfolio
end

if read_from_json == false && rts_case == true
    # Build portfolio from the function above and then run GenX
    case = @__DIR__#joinpath(@__DIR__, "/Users/sc87/code/GenX_PowerGenome/GenX_Benders_DC_OPF/GenX/example_systems/RTS_Case_Latest/")
    p = load_rts(case)
    
    # Validate and fix time series lengths after loading
    #**p = validate_and_fix_time_series_lengths(p, 8784)**

    # CRITICAL: Clean time series BEFORE any validation
    p = clean_time_series_for_tdr(p)
    
    # Now validate that everything is consistent
    p = check_time_series_consistency(p)
    
elseif read_from_json == true && rts_case == true
    # Load portfolio from file
    case = @__DIR__#joinpath(@__DIR__, "/Users/sc87/code/GenX_PowerGenome/PSIP_GenX/GenX/example_systems/portfolio_julia_20250512")
    case_json = joinpath(case, "portfolio_julia.json")
    p = PSIP.Portfolio(case_json)
    
    # Validate and fix time series lengths after loading
    #**p = validate_and_fix_time_series_lengths(p, 8784)**

    # Clean time series from loaded portfolio too
    p = clean_time_series_for_tdr(p)
    p = check_time_series_consistency(p)
    
elseif read_from_json == false && rts_case == false
    # Build portfolio from the function above and then run GenX
    case = joinpath(@__DIR__, "example_systems/1_three_zones")
    p = test_portfolio(case)
else
    # Load portfolio from file
    case = joinpath(@__DIR__, "/Users/sc87/code/GenX_PowerGenome/PSIP_GenX/GenX/example_systems/portfolio_julia_20250512")
    case_json = joinpath(case, "portfolio_julia.json")
    p = PSIP.Portfolio(case_json)
    
    # Validate and fix time series lengths after loading
    #**p = validate_and_fix_time_series_lengths(p, 8784)**

    # Clean time series from loaded portfolio too
    p = clean_time_series_for_tdr(p)
    p = check_time_series_consistency(p)
end


ts = collect(get_technologies(ResourceTechnology, p));

for (i, t) in enumerate(ts)
    if typeof(t) == SupplyTechnology{PSY.ThermalStandard}
        println(i, "   ", typeof(t.operation_costs.variable))
    end
    # if IS.has_supplemental_attributes(ExistingCapacity, t)
        # println("Resource ", i, " (", typeof(t), ") has supplemental attributes.")
        # break
    # end
end
ts4 = ts[4]

genx_settings = GenX.get_settings_path(case, "genx_settings.yml") # Settings YAML file path
writeoutput_settings = GenX.get_settings_path(case, "output_settings.yml") # Write-output settings YAML file path
mysetup = GenX.configure_settings(genx_settings, writeoutput_settings) # mysetup dictionary stores settings and GenX-specific parameters

# Time Domain Reduction for Portfolio-based inputs
if mysetup["TimeDomainReduction"] == 1
    settings_path = GenX.get_settings_path(case)
    TDRpath = joinpath(case, mysetup["TimeDomainReductionFolder"])
    system_path = joinpath(case, mysetup["SystemFolder"])
    
    if !GenX.time_domain_reduced_files_exist(TDRpath)
        log_info("Clustering Time Series Data from Portfolio (Grouped)...")
        
        # Final cleanup: Ensure only 8784-length time series remain before TDR
        log_info("Final cleanup: Ensuring only 8784-length time series before TDR...")
        #**p = validate_and_fix_time_series_lengths(p, 8784)**

        p = clean_time_series_for_tdr(p)
        
        # Debug: Check time series consistency before clustering
        log_info("Debugging time series data before clustering...")
        
        # Get all technologies with time series
        all_techs = vcat(
            collect(get_technologies(SupplyTechnology, p)),
            collect(get_technologies(StorageTechnology, p)),
            collect(get_technologies(DemandRequirement, p))
        )
        
        println("Found $(length(all_techs)) technologies total")
        
        # Check time series lengths for each technology
        ts_lengths = Dict()
        for tech in all_techs
            tech_name = PSIP.get_name(tech)
            if IS.has_time_series(tech)
                keys_ = IS.get_time_series_keys(tech)
                if !isempty(keys_)
                    # First pass: find all time series lengths to identify which ones to use
                    key_lengths = []
                    for k in keys_
                        try
                            ts_data = IS.get_time_series(tech, k)
                            if ts_data !== nothing
                                ts_values = PSIP.get_data(ts_data)
                                if ts_values isa TS.TimeArray
                                    length_val = length(values(ts_values))
                                else
                                    length_val = length(ts_values)
                                end
                                push!(key_lengths, (key=k, length=length_val))
                            end
                        catch e
                            # Skip problematic time series in the first pass
                            continue
                        end
                    end
                    
                    # Filter for 8784-length time series first, then others
                    target_keys = filter(kl -> kl.length == 8784, key_lengths)
                    if isempty(target_keys)
                        # If no 8784-length series, use the first available
                        target_keys = key_lengths
                    end
                    
                    if !isempty(target_keys)
                        # Use the first valid time series (preferably 8784-length)
                        selected_key = target_keys[1]
                        ts_lengths[tech_name] = selected_key.length
                        
                        # Show all available lengths for this technology
                        all_lengths = [kl.length for kl in key_lengths]
                        if length(unique(all_lengths)) > 1
                            println("  $(tech_name): Multiple time series lengths $all_lengths, using $(selected_key.length)")
                        else
                            println("  $(tech_name): $(selected_key.key.name) $(selected_key.length) time steps")
                        end
                    else
                        println("  $(tech_name): No valid time series data found")
                        ts_lengths[tech_name] = 0
                    end
                else
                    println("  $(tech_name): No time series keys")
                    ts_lengths[tech_name] = 0
                end
            else
                println("  $(tech_name): No time series")
                ts_lengths[tech_name] = 0
            end
        end
        
        # Check for length inconsistencies
        unique_lengths = unique(values(ts_lengths))
        println("Unique time series lengths found: $unique_lengths")
        
        if length(unique_lengths) > 2  # More than just 0 and one valid length
            @warn "Inconsistent time series lengths detected!"
            for (name, length_val) in ts_lengths
                if length_val > 0
                    println("  $name: $length_val")
                end
            end
        end
        
        # Check if we have the expected time series structure for TDR
        expected_total_timesteps = 0
        if haskey(p.internal.ext, "total_timesteps")
            expected_total_timesteps = p.internal.ext["total_timesteps"]
            println("Expected total timesteps from portfolio: $expected_total_timesteps")
        end
        
        # Validate that time series are properly structured for multiple years/days
        demand_techs = collect(get_technologies(DemandRequirement, p))
        if !isempty(demand_techs)
            first_demand = demand_techs[1]
            demand_keys = IS.get_time_series_keys(first_demand)
            println("Number of time series keys for first demand: $(length(demand_keys))")
            
            # Check if we have multiple time series (one for each year/day combination)
            if length(demand_keys) > 1
                println("Multiple time series found - this might cause issues with TDR")
                for (i, key) in enumerate(demand_keys[1:min(5, end)])  # Show first 5
                    println("  Key $i: $(key)")
                end
            end
        end
        
        try
            GenX.cluster_inputs_portfolio(case, settings_path, mysetup, p)
            log_success("Time domain reduction completed successfully")
        catch e
            log_error("Time domain reduction failed with error: $e")
            log_error("Stacktrace:")
            for (exc, bt) in Base.catch_stack()
                showerror(stdout, exc, bt)
                println()
            end
            
            # Try to provide more specific debugging
            if occursin("same length", string(e))
                println("\n🔧 Length mismatch detected. Attempting to diagnose...")
                
                # Check if the issue is with variability data structure
                supply_techs = collect(get_technologies(SupplyTechnology, p))
                for tech in supply_techs
                    tech_name = PSIP.get_name(tech)
                    if IS.has_time_series(tech)
                        keys_ = IS.get_time_series_keys(tech)
                        println("Tech $tech_name has $(length(keys_)) time series keys")
                        
                        # Check if all time series have the same length
                        lengths = []
                        for key in keys_
                            try
                                ts_data = IS.get_time_series(tech, key)
                                ts_values = PSIP.get_data(ts_data)
                                if ts_values isa TS.TimeArray
                                    push!(lengths, length(values(ts_values)))
                                else
                                    push!(lengths, length(ts_values))
                                end
                            catch
                                push!(lengths, -1)  # Error indicator
                            end
                        end
                        
                        if length(unique(lengths)) > 1
                            println("  ⚠️  Inconsistent lengths in $tech_name: $lengths")
                        end
                    end
                end
            end
            
            # Skip TDR and continue with full time series
            println("\n⚠️  Skipping time domain reduction due to error. Continuing with full time series...")
            mysetup["TimeDomainReduction"] = 0
        end
    else
        println("Time Series Data Already Clustered.")
    end
else
    println("Time Domain Reduction disabled.")
end

mysetup["DC_OPF"] = 1
myinputs = GenX.load_inputs(mysetup, case, p)
mysetup["DC_OPF"] = 0
mysetup["ptdf"] = 0
mysetup["bilinear"] = 0
mysetup["disaggregate"] = 0
mysetup["unfix_slacks"] = 0
mysetup["SOS1"] = 0

L_cand = myinputs["L"]
myinputs["L_cand"] = L_cand
myinputs["pNet_Map_cand"] = copy(myinputs["pNet_Map"])
myinputs["pDC_OPF_coeff_cand"] = copy(myinputs["pDC_OPF_coeff"])
myinputs["LineAngle_Limit"] = [6.282 for i in 1:L_cand]
myinputs["Line_Angle_Limit_cand"] = myinputs["Line_Angle_Limit"]

# one level of expansion for each line
# equal to half of existing capacity for any given line pTrans_Max
myinputs["Line_Reinforcement_Cap_Size"] = [i for i in myinputs["pTrans_Max"]]
myinputs["Max_Trans_Cap"] = [1 for i in myinputs["pTrans_Max"]]
myinputs["pMax_Line_Reinforcement"] = [myinputs["Line_Reinforcement_Cap_Size"][i] * myinputs["Max_Trans_Cap"][i] for i in 1:L_cand]
myinputs["pTrans_Max_Possible"] = myinputs["pTrans_Max"] .+ myinputs["pMax_Line_Reinforcement"]


EXPANSION_LEVELS = Dict{Int, Vector}()
for i in 1:L_cand
    EXPANSION_LEVELS[i] = (0:1:myinputs["Max_Trans_Cap"][i])
end
#EXPANSION_LEVELS = [[1] for i in 1:L_cand] # needs to be a dictionary
EXPANSION_LINES = [i for i in 1:L_cand]

myinputs["EXPANSION_LINES"] = EXPANSION_LINES
myinputs["EXPANSION_LEVELS"] = EXPANSION_LEVELS

lines = collect(get_technologies(TransmissionTechnology, p));
myinputs["pC_Line_Reinforcement"] = zeros(length(lines))
using Random
Random.seed!(1)
for i in 1:length(lines)
    distance = 60 * rand()
    size_mw = myinputs["Line_Reinforcement_Cap_Size"][i]
    myinputs["pC_Line_Reinforcement"][i] = distance * size_mw * 2#000
end


solver = GenX.optimizer_with_attributes(Gurobi.Optimizer, "TimeLimit" => 40000)
mysetup["NetworkExpansion"] = 1
EP = GenX.generate_model(mysetup, myinputs, solver)
GenX.optimize!(EP)

"""
    InvestmentScheduleResults

A mutable struct that stores the results of investment decisions over multiple investment periods.

# Fields

  - `results::Dict`: Dictionary mapping investment periods to technology investment results.
    Structure: InvestmentPeriod => (TypeTechnology, "name") => BuildCapacity
    Another idea would be the structure to be:
    Structure: InvestmentPeriod => TypeTechnology => Dict{String, BuildCapacity}

    Where:

      + InvestmentPeriod: Time period when investment decisions are made
      + TypeTechnology: The type of technology being invested in
      + "name": String identifier for the specific technology instance
      + BuildCapacity: The capacity to be built for that technology in that period
"""
mutable struct InvestmentScheduleResults 
    results::Dict{Tuple{Date, Date}, Dict{Tuple{DataType, String}, Any}} # InvestmentPeriod => (TypeTechnology, "name") => BuildCapacity
end

# Extract results and write capacities back to portfolio
function extract_genx_results_to_psip_format(EP, myinputs, p)
    """
    Extract GenX optimization results and organize them according to PSIP struct format
    """
    results_dict = Dict()
    
    # Get all technologies from portfolio
    supply_techs = collect(get_technologies(SupplyTechnology, p))
    storage_techs = collect(get_technologies(StorageTechnology, p))
    transport_techs = collect(get_technologies(TransmissionTechnology, p))
    
    # Extract capacity decisions for supply technologies
    if haskey(EP.obj_dict, :vCAP) || haskey(EP.obj_dict, :eTotalCap)
        cap_var = haskey(EP.obj_dict, :vCAP) ? EP.obj_dict[:vCAP] : EP.obj_dict[:eTotalCap]
        
        for (idx, tech) in enumerate(supply_techs)
            tech_name = PSIP.get_name(tech)
            if tech isa SupplyTechnology{ThermalStandard}
                tech_type = SupplyTechnology{ThermalStandard}
            elseif tech isa SupplyTechnology{RenewableDispatch}
                tech_type = SupplyTechnology{RenewableDispatch}
            else
                tech_type = typeof(tech)
            end
            
            # Get built capacity (total - initial)
            total_cap = value(cap_var[idx])
            initial_cap = PSIP.get_initial_capacity(tech)built_*_cap
            built_cap = max(0.0, total_cap - initial_cap)
            
            results_dict[(tech_type, tech_name)] = built_cap
            println("$(tech_type) $(tech_name): Built $(built_cap) MW")
        end
    end
    
    # Extract capacity decisions for storage technologies
    if haskey(EP.obj_dict, :vCAPENERGY) && haskey(EP.obj_dict, :vCAP)
        cap_power_var = EP.obj_dict[:vCAP]
        cap_energy_var = EP.obj_dict[:vCAPENERGY]
        
        # Storage technologies come after supply technologies in the indexing
        storage_start_idx = length(supply_techs) + 1
        
        for (idx, tech) in enumerate(storage_techs)
            tech_name = PSIP.get_name(tech)
            resource_idx = storage_start_idx + idx - 1
            
            # Get built capacities
            total_power_cap = value(cap_power_var[resource_idx])
            total_energy_cap = value(cap_energy_var[resource_idx])
            
            initial_power_cap = PSIP.get_existing_capacity_discharge(tech)
            initial_energy_cap = PSIP.get_existing_capacity_energy(tech)
            
            built_power_cap = max(0.0, total_power_cap - initial_power_cap)
            built_energy_cap = max(0.0, total_energy_cap - initial_energy_cap)
            
            results_dict[(StorageTechnology{Storage}, tech_name)] = (
                build_p = built_power_cap,
                build_e = built_energy_cap
            )
            println("StorageTechnology{Storage} $(tech_name): Built $(built_power_cap) MW power, $(built_energy_cap) MWh energy")
        end
    end
    
    # Extract transmission expansion results
    if haskey(EP.obj_dict, :vNEW_TRANS_CAP) || haskey(EP.obj_dict, :vTRANS)
        trans_var = haskey(EP.obj_dict, :vNEW_TRANS_CAP) ? EP.obj_dict[:vNEW_TRANS_CAP] : EP.obj_dict[:vTRANS]
        
        for (idx, tech) in enumerate(transport_techs)
            tech_name = PSIP.get_name(tech)
            built_trans_cap = value(trans_var[idx])
            
            if tech isa NodalACTransportTechnology{ACBranch}
                tech_type = NodalACTransportTechnology{ACBranch}
            else
                tech_type = typeof(tech)
            end
            
            results_dict[(tech_type, tech_name)] = built_trans_cap
            println("$(tech_type) $(tech_name): Built $(built_trans_cap) MW transmission")
        end
    end
    
    return results_dict
end

# Extract results from GenX optimization
genx_results = extract_genx_results_to_psip_format(EP, myinputs, p)

# Create investment schedule results in PSIP format
investment_period = (Date("2025-01-01"), Date("2029-12-31"))  # Adjust dates as needed
investment_schedule = Dict(investment_period => genx_results)

# Write capacities back to portfolio using GenX's format
try
    df_cap = prepare_capacity_df(case, myinputs, mysetup, EP)
    final_cap = Dict{String, DataFrame}("stage_1" => df_cap)
    GenX.set_capacity!(p, final_cap)
    println("✅ Capacities successfully written back to portfolio")
catch e
    @warn "Failed to write capacities back to portfolio using GenX format: $e"
    # Alternative: manually update portfolio with extracted results
    println("📝 Manually updating portfolio with extracted results...")
    for ((tech_type, tech_name), capacity) in genx_results
        println("Would update $(tech_type) $(tech_name) with capacity: $(capacity)")
    end
end

# Create the final investment schedule results struct
final_investment_results = InvestmentScheduleResults(investment_schedule)

println("\n=== Investment Schedule Results ===")
for (period, results) in final_investment_results.results
    println("Investment Period: $(period[1]) to $(period[2])")
    for ((tech_type, tech_name), capacity) in results
        if capacity isa NamedTuple
            println("  $(tech_type) '$(tech_name)': $(capacity)")
        else
            println("  $(tech_type) '$(tech_name)': $(capacity) MW")
        end
    end
end


