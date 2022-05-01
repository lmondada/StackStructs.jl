using MacroTools: splitstructdef

"""
The stack macro. Relies on StackGen to generate the code.
"""

export @stack

"""
Efficient object of vector storage

Given a `struct Name`, generates a `struct NameVec` that behaves like a
`Vector{Name}`. However instead of storing the `Name`s as a vector of `N`
objects, it is stored as a single object with `N`-dimensional fields.

This should be more cache-efficient and faster to allocate, especially
for larger collections of objects.
"""
macro stack(structcode)
    esc(_stack(structcode))
end

function _stack(structcode)
	def = splitstructdef(structcode)

    structs = StackGen()
    fill!(structs, def)

    populate!(structs)
    
    codegen(structs)
end
