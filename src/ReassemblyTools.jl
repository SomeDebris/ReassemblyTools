module ReassemblyTools
using JSON
using LinearAlgebra

greet() = print("Hello World!")

struct ShipInfo
    mass
    centroid
    I
end

function getpolygoncentroid(X, Y)
    X
end

function getpolygonarea(X, Y)
    area_sum_items = (X .* circshift(Y, 1)) - (Y .* circshift(X, 1))

    sum(area_sum_items) / 2
end

function loadshapefile(filename::String)
    shapes = JSON.parsefile(filename)

    shape_dict = Dict{String, Any}()

    for idx_shape in eachindex(shapes)
        new_shape = Array{Dict, 1}(undef, lastindex(shapes[idx_shape][2]))

        for idx_scale in eachindex(shapes[idx_shape][2])
            scale = shapes[idx_shape][2][idx_scale]

            formatted_scale = Dict{String, AbstractVecOrMat}()
            # Creates the array of vertices. as long as the number of vertices 
            # and 2 wide
            verts = Array{Float64,2}(undef, lastindex(scale["verts"]), 2)

            for idx_vtx in eachindex(scale["verts"])
                verts[idx_vtx, :] = scale["verts"][idx_vtx]
            end

            formatted_scale["verts"] = verts
            formatted_scale["area"] = getpolygonarea(verts[:,1], verts[:,2])

            new_shape[idx_scale] = formatted_scale
        end

        display(new_shape)

        shape_dict[shapes[idx_shape][1]] = new_shape
    end

    shape_dict
end


end # module ReassemblyTools
