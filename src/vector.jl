export StackStruct

abstract type StackStruct{T} <: AbstractVector{T} end

# default implementations
stackfields(::Type{StackStruct}) = error("macro did not export stackfields")
maybefields(::Type{StackStruct}) = error("macro did not export maybefields")
otherfields(::Type{StackStruct}) = error("macro did not export otherfields")

# forwards to type
stackfields(::T) where T <: StackStruct = stackfields(T)
maybefields(::T) where T <: StackStruct = maybefields(T)
otherfields(::T) where T <: StackStruct = otherfields(T)

#### AbstractVector interface ####

function Base.size(xs::StackStruct)
    stackfields = StackStructs.stackfields(xs)
    !isempty(stackfields) || error("no fixed size found")
    field = stackfields |> first
    (length(getproperty(xs, field)),)
end

Base.IndexStyle(::StackStruct) = IndexLinear()

function Base.getindex(xs::StackStruct{T}, i::Int) where T
    ith_or_nothing(x, i) = if !isnothing(x) x[i] else nothing end
    v(k) = getproperty(xs, k)
    args = Dict(Pair{Symbol, Any}[
        ((k => v(k)[i]) for k in stackfields(xs))...,
        ((k => ith_or_nothing(v(k), i)) for k in maybefields(xs))...
    ])
    T((args[p] for p in fieldnames(T))...)
end

function Base.setindex!(xs::StackStruct{T}, v::T, i::Int) where T
    for p in fieldnames(T)
        if p in stackfields(xs)
            getproperty(xs, p)[i] = getproperty(v, p)
        elseif p in maybefields(xs) && !isnothing(getproperty(xs, p))
            getproperty(xs, p)[i] = getproperty(v, p)
        elseif getproperty(xs, p) != getproperty(v, p)
            error("trying to change a global property")
        end
    end
end

function Base.resize!(xs::StackStruct, n::Int)
    for p in stackfields(xs)
        resize!(getproperty(xs, p), n)
    end
    for p in maybefields(xs)
        if !isnothing(getproperty(xs, p))
            resize!(getproperty(xs, p), n)
        end
    end
end