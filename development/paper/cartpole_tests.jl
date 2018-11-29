using HDF5
using TrajectoryOptimization

# Set up the problem
model, obj0 = Dynamics.cartpole_analytical
n,m = model.n, model.m

obj = copy(obj0)
obj.x0 = [0;0;0;0.]
obj.xf = [0.5;pi;0;0]
obj.tf = 2.0
u_bnd = 20
x_bnd = [0.6,Inf,Inf,Inf]
obj_c = ConstrainedObjective(obj,u_min=-u_bnd, u_max=u_bnd)
obj_min = update_objective(obj_c,tf=:min,c=1.,Q = obj.Q*0., Qf = obj.Qf*1)
dt = 0.1

# Params
N = 51
method = :hermite_simpson

# Initial Trajectory
U0 = ones(1,N)
X0 = line_trajectory(obj.x0,obj.xf,N)

X0_rollout = copy(X0)
solver = Solver(model,obj_c,N=N)
rollout!(X0_rollout,U0,solver)

# Dircol functions
eval_f, eval_g, eval_grad_f, eval_jac_g = gen_usrfun_ipopt(solver,method)

function comparison_plot(results,sol_ipopt;kwargs...)
    n = size(results.X,1)
    if n == 2 # pendulum
        state_labels = ["pos" "vel"]
    else
        state_labels = ["pos" "angle"]
    end
    time_dircol = range(0,stop=obj.tf,length=size(sol_ipopt.X,2))
    time_ilqr = range(0,stop=obj.tf,length=size(results.X,1))

    colors = [:blue :red]

    p_u = plot(time_ilqr,to_array(results.U)',width=2,label="iLQR",color=colors)
    plot!(time_dircol,sol_ipopt.U',width=2, label="IPOPT",color=colors,style=:dashdot,ylabel="control")

    p_x = plot(time_ilqr,to_array(results.X)[1:2,:]',width=2,label=state_labels,color=colors)
    plot!(time_dircol,sol_ipopt.X[1:2,:]',width=2, label="",color=colors,style=:dashdot,ylabel="state")

    p = plot(p_x,p_u,layout=(2,1),xlabel="time (s)"; kwargs...)

    return p
end

function convergence_plot(stat_i,stat_d)
    plot(stat_i["cost"],width=2,label="iLQR")
    plot!(stat_d["cost"], ylim=[0,10], ylabel="Cost",xlabel="iterations",width=2,label="dircol")
end

colors_X = [:red :blue :orange :green]

#####################################
#          UNCONSTRAINED            #
#####################################

# Solver Options
opts = SolverOptions()
opts.use_static = false
opts.cost_tolerance = 1e-6
opts.outer_loop_update = :default
opts.τ = 0.75

# iLQR
solver = Solver(model,obj,N=N,opts=opts,integration=:rk3_foh)
res_i, stat_i = solve(solver,U0)
plot(to_array(res_i.X)')
plot(to_array(res_i.U)')
max_violation(res_i)
cost(solver, res_i)
stat_i["runtime"]
stat_i["iterations"]
var_i = DircolVars(to_array(res_i.X),to_array(res_i.U))

# DIRCOL
res_d, stat_d = solve_dircol(solver, X0_rollout, U0; method=method)
plot(res_d.X')
plot(res_d.U')
stat_d["c_max"][end]
stat_d["cost"][end]
stat_d["runtime"]
stat_d["iterations"]

comparison_plot(res_i,res_d)
convergence_plot(stat_i,stat_d)

eval_f(var_i.Z)
eval_f(res_d.Z)

stat_i["cost"][50]
stat_d["cost"][50]

time_per_iter = stat_i["runtime"]/stat_i["iterations"]
time_per_iter = stat_d["runtime"]/stat_d["iterations"]


#####################################
#           CONSTRAINED             #
#####################################

# Solver Options
opts = SolverOptions()
opts.cost_tolerance = 1e-6
opts.cost_intermediate_tolerance = 1e-1
opts.constraint_tolerance = 1e-3
opts.outer_loop_update = :individual
opts.τ = .85

# iLQR
solver = Solver(model,obj_c,N=N,opts=opts,integration=:rk3)
res_i, stat_i = solve(solver,U0)
plot(to_array(res_i.X)')
plot(to_array(res_i.U)')
max_violation(res_i)
cost(solver, res_i)
_cost(solver, res_i)
stat_i["runtime"]
stat_i["iterations"]

# DIRCOL
res_d, stat_d = solve_dircol(solver, X0_rollout, U0; method=:hermite_simpson)
plot(res_d.X')
plot(res_d.U')
stat_d["c_max"][end]
stat_d["cost"][end]
stat_d["runtime"]
stat_d["iterations"]

comparison_plot(res_i,res_d)
convergence_plot(stat_i,stat_d)

eval_f(var_i.Z)
eval_f(res_d.Z)

stat_i["cost"][40]
stat_d["cost"][40]

time_per_iter = stat_i["runtime"]/stat_i["iterations"]
time_per_iter = stat_d["runtime"]/stat_d["iterations"]


#####################################
#        INFEASIBLE START           #
#####################################

# Solver Options
opts = SolverOptions()
opts.cost_tolerance = 1e-6
opts.cost_intermediate_tolerance = 1e-1
# opts.constraint_tolerance = 1e-3
opts.outer_loop_update = :default
opts.τ = .85
opts.resolve_feasible = false

# iLQR
solver = Solver(model,obj_c,N=N,opts=opts,integration=:rk3)
res_i, stat_i = solve(solver,X0,U0)
plot(to_array(res_i.X)')
plot(to_array(res_i.U)')
max_violation(res_i)
_cost(solver, res_i)
stat_i["runtime"]
stat_i["iterations"]
var_i = DircolVars(res_i)


# DIRCOL
res_d, stat_d = solve_dircol(solver, X0, U0; method=:hermite_simpson)
plot(res_d.X')
plot(res_d.U')
stat_d["c_max"][end]
stat_d["cost"][end]
stat_d["runtime"]
stat_d["iterations"]
stat_d["cost"]

comparison_plot(res_i,res_d)
convergence_plot(stat_i,stat_d)

eval_f(var_i.Z)
eval_f(res_d.Z)

stat_i["cost"][30]
stat_d["cost"][30]

time_per_iter = stat_i["runtime"]/stat_i["iterations"]
time_per_iter = stat_d["runtime"]/stat_d["iterations"]


#####################################
#          MINIMUM TIME             #
#####################################


# Solver Options
opts = SolverOptions()
opts.use_static = false
opts.max_dt = 0.25
opts.verbose = false
opts.cost_tolerance = 1e-4
opts.cost_intermediate_tolerance = 1e-3
opts.constraint_tolerance = 0.05
opts.outer_loop_update = :default
opts.R_minimum_time = 500
opts.resolve_feasible = false
opts.μ_initial_minimum_time_equality = 50.
opts.γ_minimum_time_equality = 15

# iLQR
solver = Solver(model,obj_min,N=N,opts=opts,integration=:rk3)
res_i, stat_i = solve(solver,U0)
plot(to_array(res_i.X)')
plot(to_array(res_i.U)')
max_violation(res_i)
_cost(solver, res_i)
stat_i["runtime"]
stat_i["iterations"]
total_time(solver, res_i)

# DIRCOL
solver.opts.verbose = false
res_d, stat_d = solve_dircol(solver, X0_rollout, U0; method=:hermite_simpson)
stat_d["info"]
plot(res_d.X')
plot(res_d.U')
stat_d["c_max"][end]
stat_d["cost"][end]
stat_d["runtime"]
stat_d["iterations"]
stat_d["cost"]
total_time(solver, res_d)

comparison_plot(res_i,res_d)
convergence_plot(stat_i,stat_d)

eval_f(var_i.Z)
eval_f(res_d.Z)

stat_i["cost"][30]
stat_d["cost"][30]

time_per_iter = stat_i["runtime"]/stat_i["iterations"]
time_per_iter = stat_d["runtime"]/stat_d["iterations"]

dt_i = [res_i.U[k][end]^2 for k = 1:N]
dt_d = res_d.U[end,:]

plot(dt_i)
plot!(dt_d)



#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
#                                                                              #
#                       KNOT POINT COMPARISONS                                 #
#                                                                              #
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

# High-Accuracy DIRCOL
function run_dircol_truth(model, obj, dt, group::String)
    println("Solving DIRCOL \"truth\"")
    solver_truth = Solver(model,obj,dt=dt_truth,opts=opts,integration=:rk3_foh)
    res_truth, stat_truth = solve_dircol(solver_truth, Array(res_d.X), Array(res_d.U), method=:hermite_simpson)

    println("Writing results to file")
    h5open("data.h5","cw") do file
        group *= "/dircol_truth"
        if exists(file, group)
            g_truth = file[group]
            o_delete(g_truth,"X")
            o_delete(g_truth,"U")
        else
            g_truth = g_create(file, group)
        end
        g_truth["X"] = res_truth.X
        g_truth["U"] = res_truth.U
        attrs(g_truth)["dt"] = dt
        attrs(g_truth)["cost_tolerance"] = solver.opts.cost_tolerance
    end

    return solver_truth, res_truth, stat_truth
end

function run_Ns(model, obj, Ns, integration, dt_truth=1e-3)
    num_N = length(Ns)

    err = zeros(num_N)
    err_final = zeros(num_N)
    stats = Array{Dict,1}(undef,num_N)
    disable_logging(Logging.Info)
    for (i,N) in enumerate(Ns)
        println("Solving with $N knot points")
        solver = Solver(model,obj,N=N,opts=opts,integration=integration)
        res,stat = solve(solver,U0)
        t = get_time(solver)
        Xi,Ui = interpolate_trajectory(solver_truth, res_truth.X, res_truth.U, t)
        err[i] = norm(Xi-to_array(res.X))/N
        err_final[i] = norm(res.X[N] - obj.xf)
        stats[i] = stat
    end
    return err, err_final, stats
end

function plot_error()
    plot(Ns,err_mid,yscale=:log10, label="midpoint", marker=:circle, ylabel="Normed Error", xlabel="Number of Knot Points")
    plot!(Ns,err_rk3,label="rk3", marker=:circle)
    plot!(Ns,err_foh,label="rk3_foh", marker=:circle)
    plot!(Ns,err_rk4,label="rk4", marker=:circle)
end

function plot_error_final()
    plot(Ns,eterm_mid,yscale=:log10, label="midpoint", marker=:circle, ylabel="Normed Error", xlabel="Number of Knot Points")
    plot!(Ns,eterm_rk3,label="rk3", marker=:circle)
    plot!(Ns,eterm_foh,label="rk3_foh", marker=:circle)
    plot!(Ns,eterm_rk4,label="rk4", marker=:circle)
end

function plot_stat(name::String; kwargs...)
    val_mid = [stat[name] for stat in stats_mid]
    val_rk3 = [stat[name] for stat in stats_rk3]
    val_foh = [stat[name] for stat in stats_foh]
    val_rk4 = [stat[name] for stat in stats_rk4]
    plot(Ns,val_mid, label="midpoint", marker=:circle, ylabel=name, xlabel="Number of Knot Points")
    plot!(Ns,val_rk3,label="rk3", marker=:circle)
    plot!(Ns,val_foh,label="rk3_foh", marker=:circle)
    plot!(Ns,val_rk4,label="rk4", marker=:circle; kwargs...)
end

function plot_last_stat(name::String; kwargs...)
    val_mid = [stat[name][end] for stat in stats_mid]
    val_rk3 = [stat[name][end] for stat in stats_rk3]
    val_foh = [stat[name][end] for stat in stats_foh]
    val_rk4 = [stat[name][end] for stat in stats_rk4]
    plot(Ns,val_mid, label="midpoint", marker=:circle, ylabel=name, xlabel="Number of Knot Points")
    plot!(Ns,val_rk3,label="rk3", marker=:circle)
    plot!(Ns,val_foh,label="rk3_foh", marker=:circle)
    plot!(Ns,val_rk4,label="rk4", marker=:circle; kwargs...)
end

function save_data(group)
    all_err = [err_mid, err_rk3, err_foh, err_rk4]
    all_stats = [stats_mid, stats_rk3, stats_foh, stats_rk4]
    all_names = ["midpoint", "rk3", "rk3_foh", "rk4"]
    h5open("data.h5","cw") do file
        group *= "/N_plots"
        if exists(file, group)
            g_parent = file[group]
        else
            g_parent = g_create(file, group)
        end
        for name in all_names
            if has(g_parent,name)
                o_delete(g_parent, name)
            end
            g_create(g_parent, name)
        end
        gs = [g_parent[name] for name in all_names]

        for i = 1:4
            g = gs[i]
            g["runtime"] = [stat["runtime"] for stat in all_stats[i]]
            g["error"] = all_err[i]
            g["iterations"] = [stat["iterations"] for stat in all_stats[i]]
            if ~isempty(all_stats[i][1]["c_max"])
                g["c_max"] = [stat["c_max"][end] for stat in all_stats[i]]
            end
        end
    end
end

Ns = [21,41,51,81,101,201,401,501,801,1001]
obj.tf ./ (Ns.-1)
dt_truth = 1e-3

#####################################
#          UNCONSTRAINED            #
#####################################
solver_truth, res_truth,  = run_dircol_truth(model, obj, 1e-3, "cartpole/unconstrained")
time_truth = get_time(solver_truth)

err_mid, eterm_mid, stats_mid = run_Ns(model, obj, Ns, :midpoint)
err_rk3, eterm_rk3, stats_rk3 = run_Ns(model, obj, Ns, :rk3)
err_foh, eterm_foh, stats_foh = run_Ns(model, obj, Ns, :rk3_foh)
err_rk4, eterm_rk4, stats_rk4 = run_Ns(model, obj, Ns, :rk4)

plot_error()
plot_error_final()
plot_stat("runtime",legend=:topleft)
plot_stat("iterations",legend=:bottomright)

save_data("cartpole/unconstrained")


#####################################
#            CONSTRAINED            #
#####################################
solver_truth, res_truth,  = run_dircol_truth(model, obj_c, 1e-3, "cartpole/constrained")
time_truth = get_time(solver_truth)
plot(res_truth.X')

err_mid, eterm_mid, stats_mid = run_Ns(model, obj_c, Ns, :midpoint)
err_rk3, eterm_rk3, stats_rk3 = run_Ns(model, obj_c, Ns, :rk3)
err_foh, eterm_foh, stats_foh = run_Ns(model, obj_c, Ns, :rk3_foh)
err_rk4, eterm_rk4, stats_rk4 = run_Ns(model, obj_c, Ns, :rk4)

plot_error()
plot_error_final()
plot_stat("runtime",legend=:topleft)
plot_stat("iterations",legend=:bottomright)
plot_last_stat("c_max")

save_data("cartpole/constrained")

[stat["c_max"][end] for stat in stats_rk3]
