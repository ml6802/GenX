# Test script to verify gather_costs and breakout_costs produce consistent results
using Test
using DataFrames

# Define ModelScalingFactor (used in the module)
ModelScalingFactor = 10^3

# Mock zone_cost structure
struct ZoneCost
    CTotal::Vector{Float64}
    CFix::Vector{Float64}
    CVar::Vector{Float64}
    CFuel::Vector{Float64}
    CStart::Vector{Float64}
    CNSE::Vector{Float64}
    COpTot::Vector{Float64}
end

# Allow indexing by Symbol
function Base.getindex(zc::ZoneCost, s::Symbol)
    return getfield(zc, s)
end

# Create mock subproblem solution
function create_mock_subop_sol(num_periods::Int, num_zones::Int)
    subop_sol = Dict{Int, NamedTuple}()
    for k in 1:num_periods
        # Create random costs for each period
        zone_cost = ZoneCost(
            rand(num_zones) * 100,  # CTotal
            rand(num_zones) * 10,   # CFix (not used from subop)
            rand(num_zones) * 30,   # CVar
            rand(num_zones) * 20,   # CFuel
            rand(num_zones) * 5,    # CStart
            rand(num_zones) * 2,    # CNSE
            rand(num_zones) * 50    # COpTot
        )
        op_cost = sum(zone_cost.COpTot)
        subop_sol[k] = (zone_cost=zone_cost, op_cost=op_cost, emissions=zeros(num_zones, 24))
    end
    return subop_sol
end

# Create mock master solution
function create_mock_master_sol(num_zones::Int)
    zone_inv_cost = rand(num_zones) * 50
    inv_cost = sum(zone_inv_cost)
    net_exp_cost = rand() * 10
    return (inv_cost=inv_cost, zone_inv_cost=zone_inv_cost, net_exp_cost=net_exp_cost)
end

# Copy of gather_costs function
function gather_costs(master_sol::NamedTuple, subop_sol::Dict)
    investment_costs, zone_inv_cost = get_inv_cost(master_sol)
    annual_op_cost, zone_op_cost = get_op_cost(subop_sol)
    return (investment_costs=investment_costs, zone_inv_cost=zone_inv_cost, 
            annual_op_cost=annual_op_cost, zone_op_cost=zone_op_cost)
end

function get_inv_cost(master_sol::NamedTuple)
    investment_costs = master_sol.inv_cost
    zone_inv_cost = zeros(length(master_sol.zone_inv_cost))
    for z in eachindex(zone_inv_cost)
        zone_inv_cost[z] = master_sol.zone_inv_cost[z]
    end
    return investment_costs, zone_inv_cost
end

function get_op_cost(subop_sol::Dict)
    ann_op_cost = sum(subop_sol[i].op_cost for i in keys(subop_sol))
    zone_op_cost = zeros(length(subop_sol[1].zone_cost.CTotal))
    for z in eachindex(zone_op_cost)
        zone_op_cost[z] = sum(subop_sol[i].zone_cost.COpTot[z] for i in keys(subop_sol))
    end
    return ann_op_cost, zone_op_cost
end

# Copy of FIXED breakout_costs function
function breakout_costs(master_sol::NamedTuple, subop_sol::Dict)
    list_of_costs = ["CTotal","CFix","CVar","CFuel","CStart","CNetworkExp","CNSE", "COpTot"]
    list_of_zones = ["_" * string(x) for x in 1:length(subop_sol[1].zone_cost.CTotal)]
    cost_mat = Array{Float64,2}(undef,(length(list_of_costs),length(list_of_zones)))
    names = Array{String,2}(undef,(length(list_of_costs),length(list_of_zones)))
    for (j, zone) in enumerate(list_of_zones)
        for (i, cost_name) in enumerate(list_of_costs)
            if cost_name == "CFix"
                cost_mat[i,j] = master_sol.zone_inv_cost[j]
            elseif cost_name == "CNetworkExp"
                cost_mat[i,j] = 0.0
            elseif cost_name == "CTotal"
                # FIXED: Sum across all subproblems
                cost_mat[i,j] = sum(subop_sol[k].zone_cost.CTotal[j] for k in keys(subop_sol)) + master_sol.zone_inv_cost[j]
            else
                # FIXED: Sum across all subproblems
                cost_mat[i,j] = sum(subop_sol[k].zone_cost[Symbol(cost_name)][j] for k in keys(subop_sol))
            end
            names[i,j] = cost_name * zone
        end
    end
    total_costs = construct_total_costs(cost_mat, master_sol)
    flat_mat = reshape(cost_mat, (length(list_of_costs)*length(list_of_zones),))
    costs = vcat(total_costs, flat_mat)
    names = reshape(names, (length(list_of_costs)*length(list_of_zones),))
    complete_names = vcat(list_of_costs, names)
    dfCosts = DataFrame(costs', complete_names)
    return dfCosts
end

function construct_total_costs(cost_mat, master_sol)
    total_costs = zeros(size(cost_mat,1))
    for i in 1:size(cost_mat,1)
        total_costs[i] = sum(cost_mat[i,j] for j in 1:size(cost_mat,2))
    end
    total_costs[6] = master_sol.net_exp_cost * ModelScalingFactor^2
    total_costs[1] += master_sol.net_exp_cost * ModelScalingFactor^2
    return total_costs
end

# Run tests
@testset "Benders Costs Consistency Tests" begin
    # Test with multiple periods and zones
    @testset "Multi-period, multi-zone" begin
        num_periods = 4
        num_zones = 3
        
        master_sol = create_mock_master_sol(num_zones)
        subop_sol = create_mock_subop_sol(num_periods, num_zones)
        
        costs = gather_costs(master_sol, subop_sol)
        dfCosts = breakout_costs(master_sol, subop_sol)
        
        println("\n=== Test Results for $num_periods periods, $num_zones zones ===")
        println("gather_costs results:")
        println("  Investment costs: ", costs.investment_costs)
        println("  Annual op cost: ", costs.annual_op_cost)
        println("  Zone inv costs: ", costs.zone_inv_cost)
        println("  Zone op costs: ", costs.zone_op_cost)
        
        println("\nbreakout_costs (dfCosts) results:")
        println("  CFix total: ", dfCosts.CFix[1])
        println("  COpTot total: ", dfCosts.COpTot[1])
        println("  Zone CFix: ", [dfCosts[1, Symbol("CFix_$z")] for z in 1:num_zones])
        println("  Zone COpTot: ", [dfCosts[1, Symbol("COpTot_$z")] for z in 1:num_zones])
        
        # Test 1: Investment costs match
        @test isapprox(costs.investment_costs, dfCosts.CFix[1], rtol=1e-10)
        println("\n✓ Total investment costs match: $(costs.investment_costs) ≈ $(dfCosts.CFix[1])")
        
        # Test 2: Zone investment costs match
        for z in 1:num_zones
            @test isapprox(costs.zone_inv_cost[z], dfCosts[1, Symbol("CFix_$z")], rtol=1e-10)
        end
        println("✓ Zone investment costs match")
        
        # Test 3: Total operational costs match
        @test isapprox(costs.annual_op_cost, dfCosts.COpTot[1], rtol=1e-10)
        println("✓ Total operational costs match: $(costs.annual_op_cost) ≈ $(dfCosts.COpTot[1])")
        
        # Test 4: Zone operational costs match
        for z in 1:num_zones
            @test isapprox(costs.zone_op_cost[z], dfCosts[1, Symbol("COpTot_$z")], rtol=1e-10)
        end
        println("✓ Zone operational costs match")
        
        # Test 5: Verify operational costs are summed across all periods (not just period 1)
        # Calculate what the OLD buggy code would have produced
        old_op_cost = subop_sol[1].op_cost  # Only period 1
        new_op_cost = sum(subop_sol[k].op_cost for k in keys(subop_sol))  # All periods
        
        println("\n=== Verification that fix works ===")
        println("Old (buggy) op cost (period 1 only): ", old_op_cost)
        println("New (fixed) op cost (all periods): ", new_op_cost)
        println("dfCosts.COpTot: ", dfCosts.COpTot[1])
        
        @test dfCosts.COpTot[1] ≈ new_op_cost
        @test dfCosts.COpTot[1] != old_op_cost || num_periods == 1
        println("✓ Confirmed: dfCosts uses all periods, not just period 1")
    end
    
    # Test edge case: single period (should work the same)
    @testset "Single period" begin
        num_periods = 1
        num_zones = 2
        
        master_sol = create_mock_master_sol(num_zones)
        subop_sol = create_mock_subop_sol(num_periods, num_zones)
        
        costs = gather_costs(master_sol, subop_sol)
        dfCosts = breakout_costs(master_sol, subop_sol)
        
        @test isapprox(costs.investment_costs, dfCosts.CFix[1], rtol=1e-10)
        @test isapprox(costs.annual_op_cost, dfCosts.COpTot[1], rtol=1e-10)
        println("\n✓ Single period case: costs match")
    end
end

println("\n=== All tests passed! ===")
