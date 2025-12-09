#!/bin/bash                                              
#SBATCH --job-name=RTS_1_week_benders_ptdf     # create a short name for your job
#SBATCH --ntasks=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=5       # cpu-cores per task (>1 if multi-threaded tasks)
#SBATCH --output=slurm-%j.out
#SBATCH --mem-per-cpu=20G       # memory per cpu-core
#SBATCH --time=4:00:00          # total run time limit (HH:MM:SS)
#SBATCH --mail-type=all          # send email when job ends
#SBATCH --mail-user=dc0173@princeton.edu

module purge
module load gurobi/12.0.0
module load julia/1.10.5
julia -t 5 --project=./ ./example_systems/RTS_Case_Latest/1_week_run_monolithic_reconductoring_ptdf_rahmani.jl