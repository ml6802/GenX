#!/bin/bash                                              
#SBATCH --job-name=RTS_TDR_Benders_16repweeks_warmstart_RTS_scale_up_sampledlines1_BD_LP     # create a short name for your job
#SBATCH --ntasks=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=32       # cpu-cores per task (>1 if multi-threaded tasks)
#SBATCH --output=slurm-%j.out
#SBATCH --mem-per-cpu=6G       # memory per cpu-core
#SBATCH --time=36:00:00          # total run time limit (HH:MM:SS)
#SBATCH --mail-type=all          # send email when job ends
#SBATCH --mail-user=dc0173@princeton.edu

module purge
module load gurobi/12.0.0
module load julia/1.10.5
julia -t 32 --project=./ ./example_systems/RTS_Case_Latest/TDR_benders_16repweeks_RTS_scale_up_sampledlines1_BD.jl 1