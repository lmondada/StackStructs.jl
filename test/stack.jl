"""
Check that two blocks of structs contain the same structs
"""
function equiv_structs(block1, block2)
    @test Meta.isexpr(block1, :block)
    @test Meta.isexpr(block2, :block)

    getdefs(b) = map(
        MacroTools.splitstructdef,
        filter(e -> Meta.isexpr(e, :struct), b.args)
    )
    cleanup!(d) = d[:constructors] = []

    """
    Ugly function to check that two struct definitions are equivalent
    """
    function checkeq(d1, d2)
        @test d1[:name] == d2[:name]
        @test d1[:supertype] == d2[:supertype]
        for (p1, p2) = zip(d1[:fields], d2[:fields])
            type1 = p1[2] isa Type ? p1[2] : eval(p1[2])
            type2 = p2[2] isa Type ? p2[2] : eval(p2[2])
            @test type1 == type2
            @test p1[1] == p2[1]
        end
    end

    defs1, defs2 = getdefs.([block1, block2])
    cleanup!.([defs1..., defs2...])

    for (d1, d2) = zip(defs1, defs2)
        checkeq(d1, d2)
    end
end

"""
A macro to evaluate constructor expression locally
"""

@testset "stack.jl" begin

    @testset "makevecconstructor" begin
        new(a,b,c) = (a,b,c)
        def = MacroTools.splitstructdef(quote
            struct TestConstructor
                a::Int
                b::Stack{Int}
                c::Stack{Float64}
            end
        end)
        s = StackStructs.StackGen()
        StackStructs.fill!(s, def)
        # sorry for poluting the global namespace
        eval(Expr(
            :block,
            :(new(a,b,c) = (a,b,c)),
            first(StackStructs.makevecconstructors(s))
        ))
        args = (2, [2,3], [2.,3.])
        @test TestConstructorVec(args...) == args
        @test_throws ErrorException TestConstructorVec(2, [3], [4., 5.])
    end

    @testset "_stack" begin
        @testset "T1" begin
            result = StackStructs._stack(quote
                struct A
                    a::Stack{Int}
                end
            end)
            expected = quote
                struct A <: Any
                    a::Int
                end
                struct AVec <: StackStruct{A}
                    a::Vector{Int}
                end
            end
            equiv_structs(result, expected)
        end

        @testset "T2" begin
            result = StackStructs._stack(quote
                struct A
                    a::Int
                    b::Stack{Float64}
                    c::MaybeStack{Vector{Float64}}
                    d::Bool
                end
            end)
            expected = quote
                struct A <: Any
                    b::Float64
                    c::Union{Nothing, Vector{Float64}}
                end
                struct AVec <: StackStruct{A}
                    a::Int
                    b::Vector{Float64}
                    c::Union{Nothing, Vector{Vector{Float64}}}
                    d::Bool
                end
            end
            equiv_structs(result, expected)
        end

        @testset "define B + BVec" begin
            @stack struct B
                a::Int
                b::Stack{Int}
                c::MaybeStack{Int}
            end
            @test B isa DataType
            @test BVec isa DataType
            @test fieldnames(B) == (:b, :c)
            @test fieldnames(BVec) == (:a, :b, :c)
            @test BVec <: AbstractVector{B}

            b = BVec(2, [1,2], nothing)
            @test fieldnames(typeof(b)) == (:a, :b, :c)
            @test StackStructs.stackfields(b) == (:b,)
            @test StackStructs.maybefields(b) == (:c,)
            @test StackStructs.otherfields(b) == (:a,)
        end

        @testset "constructor" begin
            @stack struct C
                a::Stack{Int}
                b::Stack{Int}
            end
            @test_throws ErrorException CVec([1,2], [3])
        end

        @testset "no constructor" begin
            ex = :(struct D
                D(something) = new()
            end)
            @test_throws ErrorException StackStructs._stack(ex)
        end
    end

    @testset "fieldnames" begin
        def = MacroTools.splitstructdef(quote
            struct A
                a::Stack{Int}
                b::Int
                c::Stack{Int}
                d::MaybeStack{Int}
                e::MaybeStack{Int}
            end
        end)
        s = StackStructs.StackGen()
        StackStructs.fill!(s, def)
        @test StackStructs.allfields(s) == (:a, :b, :c, :d, :e)
        @test StackStructs.stackfields(s) == (:a, :c)
        @test StackStructs.maybefields(s) == (:d, :e)
        @test StackStructs.otherfields(s) == (:b,)
    end
end