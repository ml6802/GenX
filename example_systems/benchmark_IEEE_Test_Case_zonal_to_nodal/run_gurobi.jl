a = 1


using Revise

using GenX
using Gurobi, JuMP

m1, inputs = run_genx_case!(dirname(@__FILE__), Gurobi.Optimizer, tight_bigM = true);

for var in m1[:slack_vFLOW]
    fix(var, 0, force = true)
end
for var in m1[:slackup_vCANDFLOW]
    fix(var, 0, force = true)
end
for var in m1[:slackdown_vCANDFLOW]
    fix(var, 0, force = true)
end


flow_sols = value.(m[:vFLOW])
candflow_sols = value.(m[:vCANDFLOW])
candflow_mat = zeros(76, 24)
for i in 1:76
    for j in 1:24
        candflow_mat[i,j] = candflow_sols[i,j,1]
    end
end
build_sols = value.(m[:vNEW_TRANS_CAP_DECISION_INT])
build_sols = [i for i in build_sols]
vP_sols = value.(m[:vP])

using JLD2
# jldsave(
#     (@__DIR__)*"/bigM_solutions.jld2",
#     build = build_sols,
#     vP = vP_sols,
#     flows = flow_sols,
#     candflows = candflow_mat
# )

#data = jldopen((@__DIR__)*"/bigM_solutions.jld2")

# sols_sparse = value.(m[:vNEW_TRANS_CAP_DECISION_INT])
# sols = zeros(76, 1)
# for i in 1:76
#     sols[i] = sols_sparse[i, 1]
# end

# Benders_sols = inputs[1]
# Benders_changes = zeros(size(Benders_sols))
# for i in 1:(size(Benders_sols)[2]-1)
#     Benders_changes[:, i] .= Benders_sols[:, i+1] - Benders_sols[:, i]
# end

# using Plots
# heatmap(Benders_sols, legend = :none)
# xlabel!("Benders Iteration")
# ylabel!("Build Decision")

# using ColorSchemes
# cg = cgrad([:red, :black, :yellow], [-1., 0., 1.])



# t3 = @elapsed begin
# m, inputs = run_genx_case!(dirname(@__FILE__), Gurobi.Optimizer)
# end
# iters = length(inputs[2])

# plot([1, iters], [1.9228e6, 1.9228e6], color = "red", label = :none, legend =(0.1, 0.5))
# plot!(1:iters, inputs[2], color = "black", yaxis = :log10, label = :none)
# plot!(1:iters, inputs[3], color = "black", linestyle = :dash, label = :none)

# plot!(1:iters, inputs2[1], color = "gray", yaxis = :log10, label = :none)
# plot!(1:iters, inputs2[2], color = "gray", linestyle = :dash, label = :none)
# plot!([], [], color = "black", label = "Binary B-Theta")
# plot!([], [], color = "gray", label = "Binary PTDF")
# plot!([], [], color = "red", label = "Optimal")
# plot!([], [], color = "lightgray", label = "Upper Bound")
# plot!([], [], color = "lightgray", label = "Lower Bound", linestyle = :dash)
# ylabel!("Objective Value")
# xlabel!("Iteration")
# title!("Benchmark 49-Bus Case")

# #savefig((@__DIR__)*"/Benders_Comp2.png")