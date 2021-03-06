using BenchmarkTools
using PkgBenchmark
using LinearAlgebra
using StaticArrays
using TrajectoryOptimization
using TrajOptPlots
using Plots
import TrajectoryOptimization.AbstractSolver
const TO = TrajectoryOptimization

const paramspath = joinpath(@__DIR__,"params.json")
const suite = BenchmarkGroup()

function benchmarkable_solve!(solver; samples=10, evals=10)
    Z0 = deepcopy(get_trajectory(solver))
    solver.opts.verbose = false
    b = @benchmarkable begin
        initial_trajectory!($solver,$Z0)
        solve!($solver)
    end samples=samples evals=evals
    return b
end


# ALTRO
const altro = BenchmarkGroup(["constrained"])
altro["double_int"]    = benchmarkable_solve!(ALTROSolver(Problems.DoubleIntegrator()...))
altro["pendulum"]      = benchmarkable_solve!(ALTROSolver(Problems.Pendulum()...))
altro["cartpole"]      = benchmarkable_solve!(ALTROSolver(Problems.Cartpole()...))
altro["acrobot"]       = benchmarkable_solve!(ALTROSolver(Problems.Acrobot()...))
altro["parallel_park"] = benchmarkable_solve!(ALTROSolver(Problems.DubinsCar(:parallel_park)...))
altro["3obs"]          = benchmarkable_solve!(ALTROSolver(Problems.DubinsCar(:three_obstacles)...))
altro["escape"]        = benchmarkable_solve!(ALTROSolver(Problems.DubinsCar(:escape)...,
    infeasible=true, R_inf=0.1))
altro["quadrotor"]     = benchmarkable_solve!(ALTROSolver(Problems.Quadrotor(:zigzag)...))
altro["airplane"]      = benchmarkable_solve!(ALTROSolver(Problems.YakProblems()...))
suite["ALTRO"] = altro

# iLQR
const ilqr = BenchmarkGroup(["unconstrained"])
ilqr["double_int"]    = benchmarkable_solve!(iLQRSolver(Problems.DoubleIntegrator()...))
ilqr["pendulum"]      = benchmarkable_solve!(iLQRSolver(Problems.Pendulum()...))
ilqr["cartpole"]      = benchmarkable_solve!(iLQRSolver(Problems.Cartpole()...))
ilqr["acrobot"]       = benchmarkable_solve!(iLQRSolver(Problems.Acrobot()...))
ilqr["parallel_park"] = benchmarkable_solve!(iLQRSolver(Problems.DubinsCar(:parallel_park)...))
ilqr["quadrotor"]     = benchmarkable_solve!(iLQRSolver(Problems.Quadrotor(:zigzag)...))
ilqr["airplane"]      = benchmarkable_solve!(iLQRSolver(Problems.YakProblems()...))
suite["iLQR"] = ilqr

# DIRCOL
const dircol = BenchmarkGroup(["constrained"])
dircol["double_int"] = benchmarkable_solve!(DIRCOLSolver(Problems.DoubleIntegrator()..., integration=HermiteSimpson))
dircol["pendulum"]   = benchmarkable_solve!(DIRCOLSolver(Problems.Pendulum()..., integration=HermiteSimpson))
dircol["cartpole"]   = benchmarkable_solve!(DIRCOLSolver(Problems.Cartpole()..., integration=HermiteSimpson))
dircol["acrobot"]    = benchmarkable_solve!(DIRCOLSolver(Problems.Acrobot()..., integration=HermiteSimpson))
dircol["parallel_park"]   = benchmarkable_solve!(DIRCOLSolver(Problems.DubinsCar(:parallel_park)..., integration=HermiteSimpson))
dircol["3obs"]       = benchmarkable_solve!(DIRCOLSolver(Problems.DubinsCar(:three_obstacles)..., integration=HermiteSimpson))
dircol["escape"]     = benchmarkable_solve!(DIRCOLSolver(Problems.DubinsCar(:escape)..., integration=HermiteSimpson))
dircol["quadrotor"]  = benchmarkable_solve!(DIRCOLSolver(Problems.Quadrotor(:zigzag)...,integration=HermiteSimpson))
dircol["airplane"]   = benchmarkable_solve!(DIRCOLSolver(Problems.YakProblems()..., integration=HermiteSimpson))
suite["Ipopt"] = dircol

SUITE = suite
