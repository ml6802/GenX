#!/bin/bash                                              
#SBATCH --job-name=RTS_TDR_Monolithic_16repweeks_get_variables     # create a short name for your job
#SBATCH --ntasks=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1       # cpu-cores per task (>1 if multi-threaded tasks)
#SBATCH --output=slurm-%j.out
#SBATCH --mem-per-cpu=8G       # memory per cpu-core
#SBATCH --time=0:59:00          # total run time limit (HH:MM:SS)
#SBATCH --mail-type=all          # send email when job ends
#SBATCH --mail-user=dc0173@princeton.edu

module purge
module load gurobi/12.0.0
module load julia/1.10.5
julia -t 1 --project=./ ./example_systems/RTS_Case_Latest/TDR_monolithic_16repweeks_get_variables.jl