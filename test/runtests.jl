using StackStructs
using Test
using MacroTools

@testset "StackStructs.jl" begin
    # Write your tests here.
    include("vector.jl")
    include("stack.jl")
end
