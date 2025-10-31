ENV["GENX_PRECOMPILE"] = "false"

using Revise
using JuMP
using GenX
using PowerSystemsInvestmentsPortfolios
using Gurobi
using TimeSeries
using CSV
using DataFrames
using Dates
using InfrastructureSystems
using PowerSystems
const PSIP = PowerSystemsInvestmentsPortfolios
const IS = InfrastructureSystems
const PSY = PowerSystems
using Plots
import Pkg
using Distributed, ClusterManagers

# Pkg.activate("/home/ml6802/GenX")
# include("/home/ml6802/GenX/src/GenX.jl")

include((@__DIR__)*"/load_portfolio.jl")
include((@__DIR__)*"/../convert_input_dict.jl")


tts = collect(get_technologies(TransmissionTechnology, p))

tts_caps = [get_existing_capacity_mw(p, tts[i]) for i in 1:length(tts)]
tts_volts = [PSIP.get_voltage(tts[i]) for i in 1:length(tts)]