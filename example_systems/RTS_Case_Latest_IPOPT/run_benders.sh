#!/bin/bash
#SBATCH --job-name=Example_DCOPF
#SBATCH --nodes=1                           # node count
#SBATCH --ntasks=1                          # total number of tasks across all nodes
#SBATCH --cpus-per-task=52                   # cpu-cores per task (>1 if multi-threaded tasks)
#SBATCH --mem-per-cpu=5G                    # memory per cpu-core
#SBATCH --time=24:00:00                     # total run time limit (HH:MM:SS)
#SBATCH --output="test.out"
#SBATCH --error="test.err"
#SBATCH --mail-type=end                    # notifications for job done & fail
#SBATCH --mail-user=ml6802@princeton.edu  # send-to address

module add julia/1.10.5
module add gurobi/11.0.3

julia 1_year_run_Benders.jl

date