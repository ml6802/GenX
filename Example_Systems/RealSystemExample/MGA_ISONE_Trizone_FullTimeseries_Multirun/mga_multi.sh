#!/bin/bash
#SBATCH --job-name=multi_run               # create a short name for your job
#SBATCH --nodes=1                           # node count
#SBATCH --ntasks=1                          # total number of tasks across all nodes
#SBATCH --cpus-per-task=8                   # cpu-cores per task (>1 if multi-threaded tasks)
#SBATCH --mem-per-cpu=1G                    # memory per cpu-core
#SBATCH --time=12:00:00                     # total run time limit (HH:MM:SS)
#SBATCH --output="test.out"
#SBATCH --error="test.err"
#SBATCH --mail-type=FAIL                    # notifications for job done & fail
#SBATCH --mail-user=ml6802@princeton.edu  # send-to address   
   
module add julia/1.6.1

julia --project="/tigress/ml6802/GenX/GenX_Local/"  mga_multirun.jl

date