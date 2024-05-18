module ReassemblyTools
using JSON
using LinearAlgebra

greet() = print("Hello World!")

struct ShipInfo
    mass
    centroid
    J
    thrusters
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

function makeblocksdict(blocks::Any)
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

function getkeydefaulted(dict, key, default)
    return haskey(dict, key) ? dict[key] : default
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
        ship_centroid = [0,0]

        ship_thrusters = Vector{Dict{String, Any}}(undef, 1)

        for block in ships[idx_ship]["blocks"]
            id = block["ident"]
            offset = Tuple{Float64, Float64}(block["offset"])
            θ = haskey(block, "angle") ? block["angle"] : 0

            shape = haskey(blocks[id], "shape") ? blocks[id]["shape"] : "SQUARE"
            scale = haskey(blocks[id], "scale") ? blocks[id]["scale"] : 1
            density = haskey(blocks[id], "density") ? blocks[id]["density"] : 1

            ship_mass += blocks[id]["density"] * shapes[shape][scale]["area"]
        end

        push!(output_params, ShipInfo(ship_mass, ship_centroid, ship_J, 0))
    end

    return output_params
end


end # module ReassemblyTools
