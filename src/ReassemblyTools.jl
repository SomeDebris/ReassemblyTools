module ReassemblyTools
using JSON
using LinearAlgebra

greet() = print("Hello World!")

struct ShipInfo
    mass
    centroid
    I
end

function loadshapefile(filename::String)
    shapes = JSON.parsefile(filename)

    shape_dict = Dict{String, Any}()

    for shape in shapes
        for scale in shape[2]
            # Creates the array of vertices. as long as the number of vertices 
            # and 2 wide
            verts = Array{Float64,2}(undef, length(scale["verts"]), 2)

            for idx_vtx in 1:length(scale["verts"])
                verts[idx_vtx, :] = scale["verts"][idx_vtx]
            end

            display(verts)
        end

        shape_dict[shape[1]] = shape[2]
    end
end


end # module ReassemblyTools
