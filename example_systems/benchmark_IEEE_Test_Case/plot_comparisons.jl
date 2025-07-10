using CSV, Plots, DataFrames


nobigM = DataFrame(CSV.File((@__DIR__)*"/nobigM.csv"))
bigM = DataFrame(CSV.File((@__DIR__)*"/bigM.csv"))
ptdf = DataFrame(CSV.File((@__DIR__)*"/ptdf.csv"))

# get optimal
# run monolithic with each formulation
# plot times? 
obj_val = 1.97732e6

plot([], [], color = "red", yaxis=:log10, label = "B-Theta (big M)", legend = :bottomright)
plot!([], [], color = "blue", label = "B-Theta (no big M)")
plot!([], [], color = "orange", label = "PTDF")
plot!([], [], color = "gray", label = "Upper Bound")
plot!([], [], color = "gray", linestyle = :dash, label = "Lower Bound")
plot!([], [], color = "black", label = "Optimal")

plot!([2, 250], [obj_val, obj_val], color = "black", label = :none, linewidth = 3)
plot!(2:250, bigM[2:end, "UB_best"], color = "red", label = :none, linewidth = 2)
plot!(2:250, bigM[2:end, "LB"], color = "red", linestyle = :dash, label = :none, linewidth = 2)
plot!(2:250, nobigM[2:end, "UB_best"], color = "blue", label = :none, linewidth = 2)
plot!(2:250, nobigM[2:end, "LB"], color = "blue", linestyle = :dash, label = :none, linewidth = 2)
plot!(2:250, ptdf[2:end, "UB_best"], color = "orange", label = :none, linewidth = 2)
plot!(2:250, ptdf[2:end, "LB"], color = "orange", linestyle = :dash, label = :none, linewidth = 2)
xlabel!("Benders Iteration")
ylabel!("Objective")
ylims!(2e3, 4e6)


plot([], [], color = "red", yaxis=:log10, label = "B-Theta (big M)")
plot!([], [], color = "blue", label = "B-Theta (no big M)")
plot!([], [], color = "orange", label = "PTDF")
plot!([], [], color = "gray", label = "Upper Bound")
plot!([], [], color = "gray", linestyle = :dash, label = "Lower Bound")
plot!([], [], color = "black", label = "Optimal")

plot!([2, 250], [obj_val, obj_val], color = "black", label = :none)
plot!(2:250, bigM[2:end, "UB_best"], color = "red", label = :none)
plot!(2:250, bigM[2:end, "LB"], color = "red", linestyle = :dash, label = :none)
plot!(2:250, nobigM[2:end, "UB_best"], color = "blue", label = :none)
plot!(2:250, nobigM[2:end, "LB"], color = "blue", linestyle = :dash, label = :none)
plot!(2:250, ptdf[2:end, "UB_best"], color = "orange", label = :none)
plot!(2:250, ptdf[2:end, "LB"], color = "orange", linestyle = :dash, label = :none)
xlabel!("Benders Iteration")
ylabel!("Objective")

bigM_time = []
bigM_ub = []
bigM_lb = []
nobigM_time = []
nobigM_ub = []
nobigM_lb = []
ptdf_time = [5,10,15,20,38,50,100, 208,219,260, 300]
ptdf_ub = [1.0602e10,1.0602e10,2124677,2122854,2052255,2052255,1982284,1952243,1952243,1952243,1952243]
ptdf_lb = [1856228,1858015,1859815,1862635,1862803,1865989,1865989,1872619,1872619,1872619,1872619]

plot([], [], color = "red", yaxis=:log10, label = "B-Theta (big M)")
plot!([], [], color = "blue", label = "B-Theta (no big M)")
plot!([], [], color = "orange", label = "PTDF")
plot!([], [], color = "gray", label = "Upper Bound")
plot!([], [], color = "gray", linestyle = :dash, label = "Lower Bound")
plot!([], [], color = "black", label = "Optimal")

plot!(bigM_time, bigM_ub, color = "red", label = :none)
plot!(bigM_time, bigM_lb, color = "red", linestyle = :dash, label = :none)
plot!(nobigM_time, nobigM_ub, color = "blue", label = :none)
plot!(nobigM_time, nobigM_lb, color = "blue", linestyle = :dash, label = :none)
plot!(ptdf_time, ptdf_ub, color = "orange", label = :none)
plot!(ptdf_time, ptdf_lb, color = "orange", linestyle = :dash, label = :none)
xlabel!("Time")
ylabel!("Objective")