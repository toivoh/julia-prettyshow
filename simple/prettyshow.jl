
# ---- print/show markup and helpers ------------------------------------------

type DeferredIO
    f::Function
    extra_args::Tuple
end
print(io::IO, d::DeferredIO) = d.f(io, d.extra_args...)

defer_io(f, extra_args...) = DeferredIO(f, extra_args)

defer_print(args...) = defer_io(print, args...)
defer_show(arg)      = defer_io(show, arg)


type Indented
    item  # value to be printed indented
end
indent(arg) = Indented(arg)
indent(args...) = Indented(defer_print(args...))


comma_list() = ""
function comma_list(first, rest...)
    items = {defer_show(first)}
    for arg in rest; push(items, ", "); push(items, defer_show(arg)); end
    defer_print(items...)
end


# ---- IndentIO: indentation aware wrapper IO ---------------------------------

type IndentIO <: IO
    sink::IO
    indent::Integer  # current indentation
end
IndentIO(sink::IO) = IndentIO(sink, 0)

const indent_width = 4

# capture character output and send it to print(::IndentIO, ::Char)
write(io::IndentIO, x::Uint8)       = print(io, char(x))
write(io::IndentIO, s::ASCIIString) = (for c in s; print(io, c); end)
show(io::IndentIO, x::Float32) = print(io, string(x))
show(io::IndentIO, x::Float64) = print(io, string(x))
show(io::IndentIO, x::Symbol)  = print(io, string(x))

print(io::IO, ind::Indented) = print(IndentIO(io), ind)
function print(io::IndentIO, ind::Indented)
    io.indent += indent_width
    print(io, ind.item)
    io.indent -= indent_width
    nothing
end
function print(io::IndentIO, c::Char)
    print(io.sink, c)
    if (c == '\n'); print(io.sink, " "^io.indent); end
end
