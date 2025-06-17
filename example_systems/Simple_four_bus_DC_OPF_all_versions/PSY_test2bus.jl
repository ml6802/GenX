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

add_component!(sys, bus1)
add_component!(sys, bus2)

line1 = Line(;
    name = "line1",
    available = true,
    active_power_flow = 0.0,
    reactive_power_flow = 0.0,
    arc = Arc(; from = bus1, to = bus2),
    r = 0.00281, # Per-unit
    x = 0.05917, # Per-unit
    b = (from = 0.00356, to = 0.00356), # Per-unit
    rating = 1.0, # Line rating of 200 MVA / System base of 100 MVA
    angle_limits = (min = -0.7, max = 0.7),
);

line2 = Line(;
    name = "line2",
    available = true,
    active_power_flow = 0.0,
    reactive_power_flow = 0.0,
    arc = Arc(; from = bus1, to = bus2),
    r = 0.00281, # Per-unit
    x = 0.23668, # Per-unit
    b = (from = 0.00356, to = 0.00356), # Per-unit
    rating = .25, # Line rating of 200 MVA / System base of 100 MVA
    angle_limits = (min = -0.7, max = 0.7),
);

line3 = Line(;
    name = "line3",
    available = true,
    active_power_flow = 0.0,
    reactive_power_flow = 0.0,
    arc = Arc(; from = bus1, to = bus2),
    r = 0.00281, # Per-unit
    x = 0.23668, # Per-unit
    b = (from = 0.00356, to = 0.00356), # Per-unit
    rating = .25, # Line rating of 200 MVA / System base of 100 MVA
    angle_limits = (min = -0.7, max = 0.7),
);

line4 = Line(;
    name = "line4",
    available = true,
    active_power_flow = 0.0,
    reactive_power_flow = 0.0,
    arc = Arc(; from = bus1, to = bus2),
    r = 0.00281, # Per-unit
    x = 0.23668, # Per-unit
    b = (from = 0.00356, to = 0.00356), # Per-unit
    rating = .25, # Line rating of 200 MVA / System base of 100 MVA
    angle_limits = (min = -0.7, max = 0.7),
);

line5 = Line(;
    name = "line5",
    available = true,
    active_power_flow = 0.0,
    reactive_power_flow = 0.0,
    arc = Arc(; from = bus1, to = bus2),
    r = 0.00281, # Per-unit
    x = 0.23668, # Per-unit
    b = (from = 0.00356, to = 0.00356), # Per-unit
    rating = .25, # Line rating of 200 MVA / System base of 100 MVA
    angle_limits = (min = -0.7, max = 0.7),
);


add_component!(sys, line1)
add_component!(sys, line2)
add_component!(sys, line3)
add_component!(sys, line4)
add_component!(sys, line5)


const PNM = PowerNetworkMatrices

branches = PNM.get_ac_branches(sys);
buses = PNM.get_buses(sys);
ptdf1 = PTDF(branches, buses);

a_mat = IncidenceMatrix(sys);

ba_mat = BA_Matrix(sys);

ptdf2 = PTDF(a_mat, ba_mat)

