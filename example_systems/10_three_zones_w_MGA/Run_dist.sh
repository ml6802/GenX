#!/bin/bash
#SBATCH --job-name=Example
#SBATCH --nodes=1                           # node count
#SBATCH --ntasks=1                          # total number of tasks across all nodes
#SBATCH --cpus-per-task=4                   # cpu-cores per task (>1 if multi-threaded tasks)
#SBATCH --mem-per-cpu=5G                    # memory per cpu-core
#SBATCH --time=1:00:00                     # total run time limit (HH:MM:SS)
#SBATCH --output="test.out"
#SBATCH --error="test.err"
#SBATCH --mail-type=end                    # notifications for job done & fail
#SBATCH --mail-user=ml6802@princeton.edu  # send-to address


module add julia/1.9.1
module add gurobi/10.0.1
julia --project="/home/ml6802/GenX-Bend-0.4/GenX" -p4 Run_dist.jl

date
