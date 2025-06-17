using PowerSystems, PowerNetworkMatrices

sys = System(100.0)

bus1 = ACBus(;
    number = 1,
    name = "bus1",
    bustype = ACBusTypes.REF,
    angle = 0.0,
    magnitude = 1.0,
    voltage_limits = (min = 0.9, max = 1.05),
    base_voltage = 230.0,
);

bus2 = ACBus(;
    number = 2,
    name = "bus2",
    bustype = ACBusTypes.PV,
    angle = 0.0,
    magnitude = 1.0,
    voltage_limits = (min = 0.9, max = 1.05),
    base_voltage = 230.0,
);

bus3 = ACBus(;
    number = 3,
    name = "bus3",
    bustype = ACBusTypes.PV,
    angle = 0.0,
    magnitude = 1.0,
    voltage_limits = (min = 0.9, max = 1.05),
    base_voltage = 230.0,
);

bus4 = ACBus(;
    number = 4,
    name = "bus4",
    bustype = ACBusTypes.PV,
    angle = 0.0,
    magnitude = 1.0,
    voltage_limits = (min = 0.9, max = 1.05),
    base_voltage = 230.0,
);

add_component!(sys, bus1)
add_component!(sys, bus2)
add_component!(sys, bus3)
add_component!(sys, bus4)

line1 = Line(;
    name = "line1",
    available = true,
    active_power_flow = 0.0,
    reactive_power_flow = 0.0,
    arc = Arc(; from = bus1, to = bus2),
    r = 0.00281, # Per-unit
    x = 0.05917, # Per-unit
    b = (from = 0.00356, to = 0.00356), # Per-unit
    rating = 0.01, # Line rating of 200 MVA / System base of 100 MVA
    angle_limits = (min = -0.7, max = 0.7),
);

line2 = Line(;
    name = "line2",
    available = true,
    active_power_flow = 0.0,
    reactive_power_flow = 0.0,
    arc = Arc(; from = bus1, to = bus3),
    r = 0.00281, # Per-unit
    x = 0.05917, # Per-unit
    b = (from = 0.00356, to = 0.00356), # Per-unit
    rating = .01, # Line rating of 200 MVA / System base of 100 MVA
    angle_limits = (min = -0.7, max = 0.7),
);

line3 = Line(;
    name = "line3",
    available = true,
    active_power_flow = 0.0,
    reactive_power_flow = 0.0,
    arc = Arc(; from = bus1, to = bus4),
    r = 0.00281, # Per-unit
    x = 0.05917, # Per-unit
    b = (from = 0.00356, to = 0.00356), # Per-unit
    rating = .01, # Line rating of 200 MVA / System base of 100 MVA
    angle_limits = (min = -0.7, max = 0.7),
);

line4 = Line(;
    name = "line4",
    available = true,
    active_power_flow = 0.0,
    reactive_power_flow = 0.0,
    arc = Arc(; from = bus3, to = bus4),
    r = 0.00281, # Per-unit
    x = 0.05917, # Per-unit
    b = (from = 0.00356, to = 0.00356), # Per-unit
    rating = .01, # Line rating of 200 MVA / System base of 100 MVA
    angle_limits = (min = -0.7, max = 0.7),
);


add_component!(sys, line1)
add_component!(sys, line2)
add_component!(sys, line3)
add_component!(sys, line4)

for i in 1:3
    linex = Line(;
        name = "line$(4+i)",
        available = true,
        active_power_flow = 0.0,
        reactive_power_flow = 0.0,
        arc = Arc(; from = bus1, to = bus2),
        r = 0.00281, # Per-unit
        x = 0.001, # Per-unit
        b = (from = 0.00356, to = 0.00356), # Per-unit
        rating = 0.5, # Line rating of 200 MVA / System base of 100 MVA
        angle_limits = (min = -0.7, max = 0.7),
    );
    add_component!(sys, linex)
end
for i in 1:3
    linex = Line(;
        name = "line$(7+i)",
        available = true,
        active_power_flow = 0.0,
        reactive_power_flow = 0.0,
        arc = Arc(; from = bus1, to = bus3),
        r = 0.00281, # Per-unit
        x = 0.001, # Per-unit
        b = (from = 0.00356, to = 0.00356), # Per-unit
        rating = 0.5, # Line rating of 200 MVA / System base of 100 MVA
        angle_limits = (min = -0.7, max = 0.7),
    );
    add_component!(sys, linex)
end
for i in 1:6
    linex = Line(;
        name = "line$(10+i)",
        available = true,
        active_power_flow = 0.0,
        reactive_power_flow = 0.0,
        arc = Arc(; from = bus1, to = bus4),
        r = 0.00281, # Per-unit
        x = 0.001, # Per-unit
        b = (from = 0.00356, to = 0.00356), # Per-unit
        rating = 0.5, # Line rating of 200 MVA / System base of 100 MVA
        angle_limits = (min = -0.7, max = 0.7),
    );
    add_component!(sys, linex)
end
for i in 1:6
    linex = Line(;
        name = "line$(16+i)",
        available = true,
        active_power_flow = 0.0,
        reactive_power_flow = 0.0,
        arc = Arc(; from = bus3, to = bus4),
        r = 0.00281, # Per-unit
        x = 0.001, # Per-unit
        b = (from = 0.00356, to = 0.00356), # Per-unit
        rating = 0.5, # Line rating of 200 MVA / System base of 100 MVA
        angle_limits = (min = -0.7, max = 0.7),
    );
    add_component!(sys, linex)
end




const PNM = PowerNetworkMatrices

branches = PNM.get_ac_branches(sys);
buses = PNM.get_buses(sys);
ptdf1 = PTDF(branches, buses);

a_mat = IncidenceMatrix(sys);

ba_mat = BA_Matrix(sys);

ptdf2 = PTDF(a_mat, ba_mat)

# line_tuples = inputs["ptdf_by_line"].axes[2]
# line_names = ["line$i" for i in 1:22]

# for i in 1:22
#     println(line_names[i])
#     lookup1 = ptdf1.lookup[2]
#     println(ptdf1.data[:, lookup1[line_names[i]]])
#     lookup2 = inputs["ptdf_by_line"].lookup[2]
#     println(inputs["ptdf_by_line"].data[:, lookup2[line_tuples[i]]])
#     println()
# end

