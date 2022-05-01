@testset "vector.jl" begin
    @test StackStruct <: AbstractVector
    @test StackStruct{Int} <: AbstractVector{Int}
    @test StackStruct{Int} <: AbstractVector
    @test StackStruct{Int} <: StackStruct

    @testset "AbstractVector interface" begin
        @stack struct D
            a::Stack{Int}
            b::Stack{Int}
            c::MaybeStack{Int}
            d::MaybeStack{Int}
        end

        d = DVec([1,2], [3,4], nothing, nothing)
        @test size(d) == (2,)
        @test d[1] == D(1, 3, nothing, nothing)
        d[1] = D(2, 3, nothing, nothing)
        @test d[1] == D(2, 3, nothing, nothing)
        @test_throws ErrorException d[1] = D(2, 3, 1, nothing)

        d = DVec([1,2], [3,4], [1,2], nothing)
        @test size(d) == (2,)
        @test d[1] == D(1, 3, 1, nothing)
        @test_throws MethodError d[1] = D(1, 3, nothing, nothing)
        d[1] = D(2, 3, 2, nothing)
        @test d[1] == D(2, 3, 2, nothing)
    end
end