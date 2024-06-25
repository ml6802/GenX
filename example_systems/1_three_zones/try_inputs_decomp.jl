using Pkg

case = dirname(@__FILE__)

Pkg.activate(dirname(dirname(case)))

using GenX,HiGHS

genx_settings = GenX.get_settings_path(case, "genx_settings.yml") # Settings YAML file path
writeoutput_settings = GenX.get_settings_path(case, "output_settings.yml") # Write-output settings YAML file path
mysetup = GenX.configure_settings(genx_settings, writeoutput_settings) # mysetup dictionary stores settings and GenX-specific parameters

settings_path = GenX.get_settings_path(case)

 ### Cluster time series inputs if necessary and if specified by the user
 if mysetup["TimeDomainReduction"] == 1
    TDRpath = joinpath(case, mysetup["TimeDomainReductionFolder"])
    system_path = joinpath(case, mysetup["SystemFolder"])
    GenX.prevent_doubled_timedomainreduction(system_path)
    if !GenX.time_domain_reduced_files_exist(TDRpath)
        println("Clustering Time Series Data (Grouped)...")
        GenX.cluster_inputs(case, settings_path, mysetup)
    else
        println("Time Series Data Already Clustered.")
    end
end

myinputs = GenX.load_inputs(mysetup, case);

myinputs_decomp = GenX.separate_inputs_subperiods(myinputs);

OPTIMIZER = configure_solver(settings_path, HiGHS.Optimizer)

decomp_models = Dict();
for w in keys(myinputs_decomp)
    decomp_models[w] = generate_model(mysetup, myinputs_decomp[w], OPTIMIZER);
end



