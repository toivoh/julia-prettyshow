
abstract CustomIO <: IO

# usage: Given MyIO <: CustomIO
# @customio MyIO
# to redirect printing of chars/strings to emit(io, x)

macro customio(Tsym)
    TSym = esc(Tsym)
    quote
        ($esc(:print))(io::($Tsym), s::ASCIIString)   = emit(io, s)
        ($esc(:print))(io::($Tsym), s::UTF8String)    = emit(io, s)
        ($esc(:print))(io::($Tsym), s::RopeString)    = emit(io, s)
        ($esc(:print))(io::($Tsym), s::String)        = emit(io, s)
        ($esc(:print))(io::($Tsym), c::Char)          = emit(io, c)

        ($esc(:print))(io::($Tsym), x::VersionNumber) = print(io, string(x))
    end
end

write(io::CustomIO, c::Char)        = emit(io, c)
write(io::CustomIO, s::ASCIIString) = emit(io, s)

# Work around some types that do funky stuff in show
show(io::CustomIO, x::Float32) = print(io, sshow(x))
show(io::CustomIO, x::Float64) = print(io, sshow(x))
show(io::CustomIO, x::Symbol)  = print(io, string(x))


# ---- default_show: jl_show_any replacement that invokes rshow ---------------

print(io::IO, x) = rshow(io, x)
rshow(io::IO, x) = show(io, x)

function show(io, x)
    if isa(io, IOStream) ccall(:jl_show_any, Void, (Any, Any,), io, x)
    else                 default_show(io, x)
    end
end

default_show(io::IO, x::Union(Type, Function, TypeName)) = print(io, sshow(x))

default_show(io::IO, x) = default_show(io, typeof(x), x)
default_show(io::IO, T::CompositeKind, x) = show_composite(io, x)
default_show(io::IO, T, x)                = print(io, sshow(x))

function show_composite(io, x)
    T = typeof(x)
    names = filter(name->(name!=symbol("")), [T.names...])
    values = {}
    for name in names
        try        push(values, getfield(x, name))
        catch err; error("default_show: Error accessing field \"$name\" in $T")
        end
    end
    print(io, T.name, '('); show_comma_list(io, values...); print(io, ')')
end

show_comma_list(io::IO) = nothing
function show_comma_list(io::IO, arg, args...)    
    rshow(io, arg)
    for arg in args print(io, ", "); rshow(io, arg) end
end
