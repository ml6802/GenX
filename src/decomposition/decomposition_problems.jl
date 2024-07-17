function generate_planning_problem(setup::Dict, inputs::Dict, OPTIMIZER::MOI.OptimizerWithAttributes)

    ## Start pre-solve timer
    presolver_start_time = time()
    EP = Model(OPTIMIZER)

    #set_string_names_on_creation(EP, Bool(setup["EnableJuMPStringNames"]))
    # Introduce dummy variable fixed to zero to ensure that expressions like eTotalCap,
    # eTotalCapCharge, eTotalCapEnergy and eAvail_Trans_Cap all have a JuMP variable
    @variable(EP, vZERO==0)

    # Initialize Objective Function Expression
    EP[:eObj] = AffExpr(0.0)

    planning_model!(EP,setup,inputs)

    ## Define the objective function
    @objective(EP, Min, setup["ObjScale"]*EP[:eObj])

    ## Record pre-solver time
    presolver_time = time() - presolver_start_time

    return EP


end

function generate_operation_subproblem(setup::Dict, inputs::Dict, OPTIMIZER::MOI.OptimizerWithAttributes)

    ## Start pre-solve timer
    presolver_start_time = time()
    EP = Model(OPTIMIZER)

    #set_string_names_on_creation(EP, Bool(setup["EnableJuMPStringNames"]))
    # Introduce dummy variable fixed to zero to ensure that expressions like eTotalCap,
    # eTotalCapCharge, eTotalCapEnergy and eAvail_Trans_Cap all have a JuMP variable
    @variable(EP, vZERO==0)

    # Initialize Objective Function Expression
    EP[:eObj] = AffExpr(0.0)

    operation_model!(EP,setup,inputs)

    ## Define the objective function
    @objective(EP, Min, setup["ObjScale"]*EP[:eObj])

    ## Record pre-solver time
    presolver_time = time() - presolver_start_time

    return EP


end