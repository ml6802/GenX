using Plots


lbs = [6.363e3,7.778e3,7.990e3,8.445e3,1.396e4,1.744e4,1.951e4,1.977e4,2.038e4,2.077e4,2.120e4,2.192e4,2.253e4,2.274e4,2.292e4,2.301e4,2.308e4,2.319e4,2.326e4,2.335e4,2.338e4,2.340e4,2.341e4,2.343e4,2.344e4,2.345e4,2.346e4,2.346e4,2.347e4,2.347e4,2.347e4,2.348e4] ./1e3
ubs = [2.373e4, 2.373e4,2.373e4,2.373e4,2.373e4,2.373e4,2.373e4,2.360e4,2.355e4,2.353e4,2.352e4,2.350e4,2.350e4,2.350e4,2.350e4,2.350e4,2.350e4] ./1e3
lbs_iters = 1:32
ubs_iters = 16:32

plot(ubs_iters, ubs, color = "black", label = "Upper Bound", linewidth = 2, yticks = [5, 10, 15, 20, 25], legendfontsize = 10, legend = :bottomright, xguidefontsize=14, yguidefontsize=14, xtickfontsize=10, ytickfontsize = 10)
plot!(lbs_iters, lbs, color = "black", label = "Lower Bound", linewidth = 2, linestyle = :dash)
xlabel!("Iteration")
ylabel!("Objective Value (Billion USD)")
ylims!(5, 25)
title!("Benders Decomposition Bounds")
savefig("C:/Users/dc0173/Documents/Princeton/CONUS_z3_stochastic_results.png")


plot([],[], yaxis = :log, color = "black", label="Benders Multicut", linewidth = 2)
plot!([],[], yaxis = :log, color = "red", label="Benders Multicut, filtered lines", linewidth = 2)
plot!([], [], yaxis = :log, color = "orange", label = "Benders Multicut, warmstart", linewidth = 2)
plot!([],[], yaxis = :log, color = "blue", label="Monolithic (Gurobi)", linewidth = 2)
plot!([],[], yaxis = :log, color = "grey", label="Upper Bound", linewidth = 2)
plot!([],[], yaxis = :log, color = "grey", label="Lower Bound", linewidth = 2, linestyle = :dash)
plot!(cputimes, data.UB, color = "black", label = :none, linewidth = 2)
plot!(cputimes, data.LB, color = "black", label = :none, linewidth = 2, linestyle = :dash)
plot!(cputimes2, data2.UB, yaxis = :log, color = "red", label = :none, linewidth = 2)
plot!([cputimes2[1], cputimes2[end]], [9.89e8, 9.89e8], color = "red", label = :none, linewidth = 2, linestyle = :dash)
plot!(cputimes3, data3.UB, yaxis = :log, color = "blue", label = :none, linewidth = 2)
plot!(cputimes3, data3.LB, color = "blue", label = :none, linewidth = 2, linestyle = :dash)
plot!(cputimes4, data4.UB, color = "orange", label = :none, linewidth = 2)
plot!(cputimes4, data4.LB, color = "orange", label = :none, linewidth = 2, linestyle = :dash)
xlabel!("Time (hrs)")
ylabel!("Objective Value (USD)")