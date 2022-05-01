# StackStructs

Store vectors of objects as a single object of vector fields.

Best understood through an example:

## Example

Given the following struct:
```julia
using StackStructs

@stack struct A
    a::Int
    b::Stack{Int}
    c::Stack{String}
end
```
the macro `@stack` will create a `struct AVec`. This will act just like a vector
of `A`s: 

```julia
vec = AVec(a = 3)
push!(vec, A(b = 2, c = "bla"))
typeof(vec[1]) == A
a = vec[1]
(a.b, a.c) == (2, "bla")
```

However, under the hood, the fields are stored as vectors:
```julia
vec.b # returns [2]
vec.c # returns ["bla"]
```

Note that `a` is a global property of the vector. It can no longer be accessed
through `A`, but only through `AVec`.
```julia
a.a # error
vec.a # okay
```
