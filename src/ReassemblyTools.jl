module ReassemblyTools
using JSON
using LinearAlgebra
using ControlSystems
using Printf
using Plots

greet() = print("Hello World!")

struct ShipInfo
    mass::Float64
    J::Float64
    thrusters::Vector{Dict{String, Any}}
end

struct ShipStateSpace
    A::Matrix{Float64}
    B::Matrix{Float64}
    C
    D
end

struct Thruster
    max_thrust::Float64
    min_thrust::Float64
    offset::Tuple{Float64, Float64}
    angle::Float64
end

function getkeydefaulted(dict, key, default)
    return haskey(dict, key) ? dict[key] : default
end

function getpolygonarea(X, Y)
    area_sum_items = (X .* circshift(Y, 1)) - (Y .* circshift(X, 1))

    sum(area_sum_items) / 2, area_sum_items
end

function getpolygoncentroid(X, Y)
    X_Shift = circshift(X, 1)
    Y_Shift = circshift(Y, 1)

    area, sum_items = getpolygonarea(X, Y)

     (1 / (6 .* area)) .* sum((X + X_Shift) .* sum_items),
     (1 / (6 .* area)) .* sum((Y + Y_Shift) .* sum_items)
end

# https://physics.stackexchange.com/questions/493736/moment-of-inertia-for-an-arbitrary-polygon 
function getpolygon_secondpolarareamoment(X, Y)
    X_Shift = circshift(X, 1)
    Y_Shift = circshift(Y, 1)

    area, sum_items = getpolygonarea(X, Y)

    J_x = (1/12) .* sum((sum_items) .* (Y.^2 + Y .* Y_Shift + Y_Shift.^2))
    J_y = (1/12) .* sum((sum_items) .* (X.^2 + X .* X_Shift + X_Shift.^2))
    
    J_x, J_y, J_x + J_y
end

function loadshapes(shapes::Any)
    shape_dict = Dict{String, Any}()

    for idx_shape in eachindex(shapes)
        new_shape = Array{Dict, 1}(undef, lastindex(shapes[idx_shape][2]))

        for idx_scale in eachindex(shapes[idx_shape][2])
            scale = shapes[idx_shape][2][idx_scale]

            formatted_scale = Dict{String, Any}()
            # Creates the array of vertices. as long as the number of vertices 
            # and 2 wide
            verts = Array{Float64,2}(undef, lastindex(scale["verts"]), 2)

            for idx_vtx in eachindex(scale["verts"])
                verts[idx_vtx, :] = scale["verts"][idx_vtx]
            end

            second_polar_moment_of_area = getpolygon_secondpolarareamoment(verts[:,1], verts[:,2])

            formatted_scale["verts"] = verts
            formatted_scale["area"] = getpolygonarea(verts[:,1], verts[:,2])[1]
            formatted_scale["centroid"] = getpolygoncentroid(verts[:,1], verts[:,2])
            formatted_scale["J"] = second_polar_moment_of_area

            new_shape[idx_scale] = formatted_scale
        end

        shape_dict[shapes[idx_shape][1]] = new_shape
    end

    shape_dict
end

function loadshapes(filename::String)
    loadshapes(JSON.parsefile(filename))
end

function makeblocksdict(blocks::AbstractArray)
    block_dict = Dict{Int, Dict{String, Any}}()
    # TODO: Find next steps for loading all blocks into the script
    for i in eachindex(blocks)
        block_dict[blocks[i]["ident"]] = blocks[i]
    end

    block_dict
end

function makeblocksdict(filename::String)
    makeblocksdict(JSON.parsefile(filename))
end

function hasfeature(block, feature)
    if !haskey(block, "features")
        return false
    end
    
    features = block["features"]
    
    if isa(features, AbstractString)
        return feature == features
    else
        return feature in features
    end
end

function computeshipstats(ship_filename, blocks, shapes)
    ship_dict = JSON.parsefile(ship_filename)

    is_fleet = !haskey(ship_dict, "data") 

    ship_count = 1

    if is_fleet
        ship_count = length(ship_dict["blueprints"])
    end

    ships = Vector{Dict{String, Any}}(undef, ship_count)

    if is_fleet
        ships[:] = ship_dict["blueprints"][:]
    else
        ships[1] = ship_dict
    end
    
    # TODO: compute ship parameters etc.
    #
    output_params = Vector{ShipInfo}(undef, ship_count)

    for idx_ship in eachindex(ships)
        ship_mass = 0
        ship_J = 0

        ship_thrusters = Vector{Dict{String, Any}}()

        for block in ships[idx_ship]["blocks"]
            id = block["ident"]

            # Sometimes, blocks won't be in the struct. skip these
            if !haskey(blocks, id)
                continue
            end

            offset = Tuple{Float64,Float64}(getkeydefaulted(block, "offset", (0,0)))


            shape = getkeydefaulted(blocks[id], "shape", "SQUARE")
            scale = getkeydefaulted(blocks[id], "scale", 1)
            density = getkeydefaulted(blocks[id], "density", 0.1)
            J = shapes[shape][scale]["J"][3]

            area = shapes[shape][scale]["area"]

            mass = density * area
            J_parallel_axis = mass * sum(offset .* offset) + J
            
            ship_J += J_parallel_axis
            ship_mass += mass

            if hasfeature(blocks[id], "THRUSTER")
                push!(ship_thrusters, block)
            end
        end

        output_params[idx_ship] = ShipInfo(ship_mass, ship_J, ship_thrusters)
    end

    return output_params
end

function getshipstatespace(ship_stats::ShipInfo, blocks::AbstractDict, angle_offset::Float64 = 0)
    # state matrix of an arbitrary ship
    
    m = ship_stats.mass
    J = ship_stats.J

    A = [0 0 1 0 0 0
         0 0 0 1 0 0
         0 0 -0.2 0 0 0
         0 0 0 -0.2 0 0
         0 0 0 0 0 1
         0 0 0 0 0 -0.2]

    thruster_count = lastindex(ship_stats.thrusters)

    B = zeros(6, thruster_count)

    for i in eachindex(ship_stats.thrusters)
        block = ship_stats.thrusters[i]
        id = block["ident"]

        block_def = blocks[id]

        θ = getkeydefaulted(block, "angle", 0) + angle_offset

        offset = Tuple{Float64,Float64}(getkeydefaulted(block, "offset", (0,0)))

        thruster_force = getkeydefaulted(block_def, "thrusterForce", 10000)

        x_component = cos(θ)
        y_component = sin(θ)

        B[3,i] = (1/m) * x_component * thruster_force
        B[4,i] = (1/m) * y_component * thruster_force

        B[6,i] = (1/J) * sum((thruster_force .* (y_component, x_component)) .* offset)
    end

    return ShipStateSpace(A, B, Diagonal(ones(6)), 0)
end

function getshipgainscheduled_rotation(ship_stats::ShipInfo, blocks, angles = 8)
    ship_state_spaces = getshipstatespace.(Ref(ship_stats), Ref(blocks), LinRange{Float64}(0, 2*π, angles + 1)[1:(end-1)])

    return ship_state_spaces
end

function getshipstatespace_fromfiles(ship_filename::AbstractString, blocks::AbstractDict, shapes::AbstractDict)
    ship_stats = computeshipstats(ship_filename, blocks, shapes)

    # out = getshipstatespace.(ship_stats, Ref(blocks), Ref(shapes))

    # K = Vector{Matrix{Float64}}(undef, lastindex(ship_stats))
    out = Vector{ShipStateSpace}(undef, lastindex(ship_stats))

    for i in eachindex(ship_stats)
        out[i] = getshipstatespace(ship_stats[i], blocks, shapes)
        # K[i] = lqr(out[i].A, out[i].B, I, I)
    end

    return out #, K
end

function getshipstatespace_fromfiles(ship_filename::AbstractString, blocks_filename::AbstractString, shapes_filename::AbstractString)
    blocks = makeblocksdict(blocks_filename)
    shapes = loadshapes(shapes_filename)

    return getshipstatespace_fromfiles(ship_filename, blocks, shapes)
end

function simulate_ship_lqr_gainscheduled_rotation(ship::Vector{ShipStateSpace}, target, range, deltat)
    thruster_count = size(ship[1].B, 2)

    count_mapped_rotations = lastindex(ship)

    angles = LinRange{Float64}(0, 2*π, count_mapped_rotations + 1)[1:(end-1)]

    Q = Diagonal([1, 1, 100, 100, 100, 100])
    
    K_options = Vector{Matrix{Float64}}(undef, count_mapped_rotations)

    for i in eachindex(ship)
        K_options[i] = lqr(ship[i].A, ship[i].B, Q, 2*I)
    end

    state = copy(target)
    states = Matrix{Float64}(undef, lastindex(target), lastindex(range))
    thruster_states = Matrix{Float64}(undef, thruster_count, lastindex(range))

    for i in range
        θ = mod(state[5], 2*π)
        
        idx_selected_model = argmin(abs.(angles .- θ))

        selected_model = ship[idx_selected_model]
        K = K_options[idx_selected_model]

        state += deltat .* (selected_model.A * state - selected_model.B * clamp.(K * state, 0, 1))
        
        thruster_states[:,i] = clamp.(K * state, 0, 1)

        states[:,i] = state
    end
    
    return states, thruster_states
end

function simulate_ship_lqr(ship::ShipStateSpace, target, range, deltat)
    thruster_count = size(ship.B, 2)

    Q = Diagonal([4, 4, 10, 10, 12, 10])
    
    K = lqr(ship.A, ship.B, Q, 2*I)

    state = copy(target)
    states = Matrix{Float64}(undef, lastindex(target), lastindex(range))
    thruster_states = Matrix{Float64}(undef, size(K,1), lastindex(range))

    for i in range
        state += deltat .* (ship.A * state - ship.B * clamp.(K * state, 0, 1))
        
        thruster_states[:,i] = clamp.(K * state, 0, 1)

        states[:,i] = state
    end
    
    return states, thruster_states
end

function plot_performance_lqr(ship::ShipStateSpace, target, range, deltat)
    plotrange = range .* deltat

    states, thrusts = simulate_ship_lqr(ship, target, range, deltat)

    Plots.plot(plotrange, states')
end

function plot_performance_lqr_gainscheduled_rotation(ship::Vector{ShipStateSpace}, target, range, deltat)
    plotrange = range .* deltat

    states, thrusts = simulate_ship_lqr_gainscheduled_rotation(ship, target, range, deltat)

    Plots.plot(plotrange, states')
end
        
function plot_thrusters_lqr_gainscheduled_rotation(ship::Vector{ShipStateSpace}, target, range, deltat)
    plotrange = range .* deltat

    states, thrusts = simulate_ship_lqr_gainscheduled_rotation(ship, target, range, deltat)

    Plots.plot(plotrange, thrusts')
end


end # module ReassemblyTools
