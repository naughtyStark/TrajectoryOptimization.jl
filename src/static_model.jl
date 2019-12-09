export
    AbstractModel,
    dynamics,
    discrete_dyanmics,
    jacobian,
    discrete_jacobian

export
    QuadratureRule,
    RK3,
    HermiteSimpson
abstract type FreeBodyModel <: AbstractModel end
abstract type QuadratureRule end
abstract type Implicit <: QuadratureRule end
abstract type Explicit <: QuadratureRule end
abstract type RK3 <: Implicit end
abstract type HermiteSimpson <: Explicit end

"Default quadrature rule"
const DEFAULT_Q = RK3

#=
Convenient methods for creating state and control vectors directly from the model
=#
for method in [:rand, :zeros, :ones]
    @eval begin
        function Base.$(method)(model::AbstractModel)
            n,m = size(model)
            x = @SVector $(method)(n)
            u = @SVector $(method)(m)
            return x, u
        end
        function Base.$(method)(::Type{T}, model::AbstractModel) where T
            n,m = size(model)
            x = @SVector $(method)(T,n)
            u = @SVector $(method)(T,m)
            return x,u
        end
    end
end
function Base.fill(model::AbstractModel, val)
    n,m = size(model)
    x = @SVector fill(val,n)
    u = @SVector fill(val,m)
    return x, u
end

"""Default size method for model (assumes model has fields n and m)"""
@inline Base.size(model::AbstractModel) = model.n, model.m
@inline is_euclidean(model::AbstractModel) = true

############################################################################################
#                               CONTINUOUS TIME METHODS                                    #
############################################################################################

@inline dynamics(model::AbstractModel, z::KnotPoint) = dynamics(model, state(z), control(z))

function jacobian(model::AbstractModel, z::KnotPoint)
    ix, iu = z._x, z._u
    f_aug(z) = dynamics(model, z[ix], z[iu])
    s = z.z
    ForwardDiff.jacobian(f_aug, s)
end

function jacobian(model::AbstractModel, z::SVector)
    n,m = size(model)
    ix,iu = 1:n, n .+ (1:m)
    f_aug(z) = dynamics(model, view(z,ix), view(z,iu))
    ForwardDiff.jacobian(f_aug, z)
end

############################################################################################
#                          IMPLICIT DISCRETE TIME METHODS                                  #
############################################################################################

"Set default integrator"
@inline discrete_dynamics(model::AbstractModel, z::KnotPoint) =
    discrete_dynamics(DEFAULT_Q, model, z)

@inline discrete_dynamics(::Type{Q}, model::AbstractModel, z::KnotPoint) where Q<:Implicit =
    discrete_dynamics(Q, model, state(z), control(z), z.dt)

function discrete_dynamics(::Type{RK3}, model::AbstractModel, x, u, dt)
    k1 = dynamics(model, x, u)*dt;
    k2 = dynamics(model, x + k1/2, u)*dt;
    k3 = dynamics(model, x - k1 + 2*k2, u)*dt;
    x + (k1 + 4*k2 + k3)/6
end

"Set default integrator"
@inline discrete_jacobian(model::AbstractModel, z::KnotPoint) =
    discrete_jacobian(DEFAULT_Q, model, z)

function discrete_jacobian(::Type{Q}, model::AbstractModel,
        z::KnotPoint{T,N,M,NM}) where {Q<:Implicit,T,N,M,NM}
    n,m = size(model)
    ix,iu,idt = z._x, z._u, NM+1
    fd_aug(z) = discrete_dynamics(Q, model, z[ix], z[iu], z[idt])
    s = [z.z; @SVector [z.dt]]
    ForwardDiff.jacobian(fd_aug, s)
end


############################################################################################
#                               STATE DIFFERENTIALS                                        #
############################################################################################

@inline state_diff(model::AbstractModel, x, x0) = x - x0
# @inline state_diff_jacobian(model::AbstractModel, x::SVector{N,T}) where {N,T} = Diagonal(@SVector ones(T,N))
@inline state_diff_jacobian(model::AbstractModel, x::SVector{N,T}) where {N,T} = I
@inline state_diff_size(model::AbstractModel) = size(model)[1]

function quat_diff(q2::SVector{4,T1}, q1::SVector{4,T2}) where {T1,T2}
    # equivalent to q2 - q1
    # same as inv(q1)*q2
    vec = @SVector [2,3,4]
    s1,v1 = q1[1],-q1[vec]
    s2,v2 = q2[1], q2[vec]  # needs an inverse
    # this is q1*q2
    s1*v2 + s2*v1 + v1 × v2
end

function quat_diff_jacobian(q::SVector{4,T}) where T
    w,x,y,z = q
    x,y,z = -x,-y,-z  # invert q
    @SMatrix [x  w -z  y;
              y  z  w -x;
              z -y  x  w];
end

function dynamics_expansion(::Type{Q}, model::AbstractModel, z::KnotPoint) where Q<:Implicit
    ix = z._x
    iu = z._u
    ∇f = discrete_jacobian(Q, model, z)
    A = ∇f[ix,ix]
    B = ∇f[ix,iu]
    return A,B
end

function dynamics_expansion(::Type{Q}, model::FreeBodyModel, z::KnotPoint) where Q<:Implicit
    ix = z._x
    iu = z._u
    ∇f = discrete_jacobian(Q, model, z)
    A = ∇f[ix,ix]
    B = ∇f[ix,iu]
    G = state_diff_jacobian(model, state(z))
    return G*A*G', G*B
end

@inline dynamics_expansion(model::AbstractModel, z::KnotPoint) =
    dynamics_expansion(DEFAULT_Q, model, z)

@inline cost_expansion!(E, model::AbstractModel, Z::Traj) = nothing
function cost_expansion!(E, model::FreeBodyModel, Z::Traj)
    for k in eachindex(Z)
        G = state_diff_jacobian(model, state(Z[k]))
        E.xx[k] = G*E.xx[k]*G'
        E.ux[k] =   E.ux[k]*G'
        E.x[k]  = G*E.u[k]
    end
end

"Generate discrete dynamics function for a dynamics model using RK3 integration"
function rk3_gen(model::AbstractModel)
       # Runge-Kutta 3 (zero order hold)
   @eval begin
       function discrete_dynamics(model::$(typeof(model)), x, u, dt)
           k1 = dynamics(model, x, u)*dt;
           k2 = dynamics(model, x + k1/2, u)*dt;
           k3 = dynamics(model, x - k1 + 2*k2, u)*dt;
           x + (k1 + 4*k2 + k3)/6
       end
       # @inline function discrete_dynamics(model::$(typeof(model)), Z::KnotPoint)
       #     discrete_dynamics(model, state(Z), control(Z), Z.dt)
       # end
   end
end


"""
Generate the continuous dynamics Jacobian for a dynamics model.
The resulting function should be non-allocating if the original dynamics function is non-allocating
"""
function generate_jacobian(model::M) where {M<:AbstractModel}
    n,m = size(model)
    ix,iu = 1:n, n .+ (1:m)
    f_aug(z) = dynamics(model, view(z,ix), view(z,iu))
    ∇f(z) = ForwardDiff.jacobian(f_aug,z)
    ∇f(x::SVector,u::SVector) = ∇f([x;u])
    ∇f(x,u) = begin
        z = zeros(n+m)
        z[ix] = x
        z[iu] = u
        ∇f(z)
    end
    @eval begin
        jacobian(model::$(M), x, u) = $(∇f)(x, u)
        jacobian(model::$(M), z) = $(∇f)(z)
    end
end

"""
Generate the discrete dynamics Jacobian for a dynamics model
"""
function generate_discrete_jacobian(model::M) where {M<:AbstractModel}
    n,m = size(model)
    ix,iu,idt = 1:n, n .+ (1:m), n+m+1
    fd_aug(z) = discrete_dynamics(model, view(z,ix), view(z,iu), z[idt])
    ∇fd(z) = ForwardDiff.jacobian(fd_aug, z)
    ∇fd(z,dt) = ForwardDiff.jacobian(fd_aug, [z; @SVector [dt]])
    ∇fd(x,u::SVector,dt) = ∇fd([x;u; @SVector [dt]])
    ∇fd(x,u,dt) = begin
        z = zeros(n+m)
        z[ix] = x
        z[iu] = u
        z[idt] = dt
        ∇fd(z)
    end
    @eval begin
        discrete_jacobian(model::$(M), x, u, dt) = $(∇fd)(x, u, dt)
        discrete_jacobian(model::$(M), z::AbstractVector) = $(∇fd)(z)
        discrete_jacobian(model::$(M), z, dt) = $(∇fd)(z, dt)
    end
end
