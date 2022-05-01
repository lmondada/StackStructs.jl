using MacroTools: combinestructdef, @capture

"""
This is the metaprogramming code that generates
StackStructs structs.

There is always an item struct and a vec struct. The former
holds a single instance of the stored object, the other a whole
array.

The code is organised around the StackGen struct, which stores all
the information required to generate the structs.
"""

export stackfields, maybefields, otherfields, allfields

######################
###### StackGen ######
######################

"""
All the information about the structs that are being generated
"""
mutable struct StackGen
    name::Symbol
    stackfields::Vector{Pair{Symbol, DataType}}
    maybefields::Vector{Pair{Symbol, DataType}}
    otherfields::Vector{Pair{Symbol, DataType}}
    allfields::Vector{Symbol}
    vecconstructors::Vector{Expr}
    itemconstructors::Vector{Expr}
    functions::Vector{Expr}

    StackGen() = new(:nothing, [], [], [], [], [], [], [])
end



#######################################
###### Type transformation logic ######
#######################################

"""
Find correct type depending on field type and struct type
"""
function gettype(::Type{T}, fieldkind::Symbol, format::Symbol) where T
    fieldkind == :otherfields && return T
    fieldkind in (:stackfields, :maybefields) || error("fieldkind not understood")
    if format == :vec
        if fieldkind == :stackfields
            Vector{T}
        else
            Union{Nothing, Vector{T}}
        end
    elseif format == :item
        if fieldkind == :stackfields
            T
        else
            Union{Nothing, T}
        end
    else
        error("format not understood")
    end
end


"""
Each field is either of "stack", of "maybe" or of "other" field kind
"""
function fieldkind(name::Symbol, s::StackGen)
    name in stackfields(s) && return :stackfields
    name in maybefields(s) && return :maybefields
    name in otherfields(s) && return :otherfields
end

function getstackfields(t)::Union{Nothing, DataType}
    @capture(t, Stack{subt_}) ? eval(subt) : nothing
end
function getmaybefields(t)::Union{Nothing, DataType}
    @capture(t, MaybeStack{subt_}) ? eval(subt) : nothing
end
function getotherfields(t)::Union{Nothing, DataType}
    if isnothing(getstackfields(t)) && isnothing(getmaybefields(t))
        eval(t)
    else
        nothing
    end
end


#####################
###### Getters ######
#####################

"""
Get the name of the item struct
"""
name(s::StackGen) = s.name
"""
Get the name of the vec struct
"""
vecname(s::StackGen) = Symbol(s.name, "Vec")

for fieldkind = [:stackfields, :maybefields, :otherfields]
    eval(quote
        """
        Generate getters for stackfields, maybefields and otherfields

        Formats the fields either name-only or name::type
        """
        function $fieldkind(s::StackGen; format = nothing)
            function format_fn(p)
                if isnothing(format)
                    first(p)
                else
                    Expr(
                        :(::),
                        p[1],
                        gettype(p[2], $(Meta.quot(fieldkind)), format)
                    )
                end
            end
            tuple(map(format_fn, s.$fieldkind)...)
        end
    end)
end

"""
Returns all fields

If formatted, the types are generated depending on the field kind
"""
function allfields(s::StackGen; format = nothing)
    if isnothing(format)
        tuple(s.allfields...)
    else
        function format_fn(name)
            fkind = fieldkind(name, s)
            if fkind == :otherfields && format == :item
                return nothing
            end
            for (n, t) in getproperty(s, fkind)
                if n == name
                    return Expr(:(::), name, gettype(t, fkind, format))
                end
            end
            error("internal logic error")
        end
        tuple(filter(!isnothing, map(format_fn, s.allfields))...)
    end
end

#####################################
###### Struct generation logic ######
#####################################

"""
Currently only very simple structs are supported.

Raises an error if unsupported feature is used
"""
function checkvalid(d::Dict)
    for field = (:constructors, :params)
        if !isempty(d[field])
            error("providing custom $field is not supported.")
        end
    end
    d[:supertype] == :Any || error("unsupported supertype")
    isempty(d[:params]) || error("unsupported type parameter")
    !d[:mutable] || error("only immutable types supported")
end

"""
Given input struct, fill in a StackGen object for internal representation
"""
function fill!(s::StackGen, d::Dict)
    checkvalid(d)

    getfields(typetransform) = filter(
        !isnothing ∘ last, [n => typetransform(t) for (n, t) = d[:fields]]
    )

    s.name = d[:name]
    s.allfields = map(first, d[:fields])
    s.stackfields = getfields(getstackfields)
    s.maybefields = getfields(getmaybefields)
    s.otherfields = getfields(getotherfields)
end

"""
Use internal representation to build helper functions
"""
function populate!(s::StackGen)
    s.functions = makefuncs(s)
    s.vecconstructors = makevecconstructors(s)
    s.itemconstructors = makeitemconstructors(s)
end

"""
Builds getter functions for StackStructs
"""
function makefuncs(s::StackGen)
    funcs = Expr[]

    ## Getters for NameVec
    push!(funcs, quote
        StackStructs.stackfields(::Type{$(vecname(s))}) = $(stackfields(s))
        StackStructs.maybefields(::Type{$(vecname(s))}) = $(maybefields(s))
        StackStructs.otherfields(::Type{$(vecname(s))}) = $(otherfields(s))
    end)

    ## Name keyword constructor
    args = [
        stackfields(s, format=:item)...,
        map(e -> Expr(:kw, e, nothing), maybefields(s, format=:item))...
    ]
    push!(funcs, quote
        function $(name(s))(; $(args...))
            $(name(s))($(allfields(s, format=:item)...))
        end
    end)

    ## NameVec keyword constructor
    args = [
        otherfields(s, format=:vec)...,
        map(e -> Expr(:kw, e, e.args[2]()), stackfields(s, format=:vec))...,
        map(e -> Expr(:kw, e, nothing), maybefields(s, format=:vec))...
    ]
    resets = [
        :(isempty($(e.args[1])) && ($(e.args[1]) = $(e.args[2])[]))
        for e in stackfields(s, format=:item)
    ]
    push!(funcs, quote
        function $(vecname(s))(; $(args...))
            $(Expr(:block, resets...))
            $(vecname(s))($(allfields(s)...))
        end
    end)
    
    # forward properties to Vec struct
    # push!(funcs, quote
    #     function Base.getproperty(x::$(name(s)), prop::Symbol)
    #         if prop ∈ fieldnames($(name(s)))
    #             getfield(x, prop)
    #         else
    #             getfield(x._ref, prop)
    #         end
    #     end
    # end)

    funcs
end

"""
Builds constructors for StackStruct vec type
"""
function makevecconstructors(s::StackGen)
    constructors = Expr[]

    if length(stackfields(s)) ≥ 2
        push!(constructors, quote
            function $(vecname(s))($(allfields(s, format=:vec)...))
                n = length($(stackfields(s)[1]))
                for f in [$(stackfields(s)[2:end]...)]
                    length(f) == n || error("all vectors must have same length")
                end
                for f in [$(maybefields(s)...)]
                    isnothing(f) || length(f) == n || error("all vectors must have same length")
                end
                new($(allfields(s)...))
            end
        end)
    else
        push!(constructors, quote
            function $(vecname(s))($(allfields(s, format=:vec)...))
                new($(allfields(s)...))
            end
        end)
    end

    constructors
end

"""
Builds constructors for StackStruct item type
"""
function makeitemconstructors(s::StackGen)
    constructors = Expr[]

    push!(constructors, quote
        function $(name(s))($(allfields(s, format=:item)...))
            new($(allfields(s, format=:item)...))
        end
    end)

    constructors
end

function structdict(; name, fields,
    mutable = false,
    params = [], 
    constructors = [],
    supertype = :Any
)
    Dict(
        :name => name,
        :mutable => mutable,
        :params => params, 
        :fields => fields,
        :constructors => constructors,
        :supertype => supertype
    )
end

function codegen(s::StackGen)
    itemdef = structdict(
        name = name(s),
        fields = map(e -> e.args, allfields(s, format=:item)),
        constructors = s.itemconstructors
    )
    stackdef = structdict(
        name = vecname(s),
        fields = map(e -> e.args, allfields(s, format=:vec)),
        constructors = s.vecconstructors,
        supertype = :(StackStruct{$(name(s))})
    )
    funcdefs = Expr(:block, s.functions...)

    # println(combinestructdef(itemdef))
    # println(combinestructdef(stackdef))
    # println(funcdefs)
    Expr(:block, combinestructdef(itemdef), combinestructdef(stackdef), funcdefs)
end
