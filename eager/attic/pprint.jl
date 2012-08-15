
macro expect(pred)
    :( ($esc(pred)) ? nothing : error($"error: expected $pred == true") )
end

is_expr(ex, head::Symbol) = (isa(ex, Expr) && (ex.head == head))
is_expr(ex, head::Symbol, n::Int) = is_expr(ex, head) && length(ex.args) == n

# ---- IndentIO: indentation aware wrapper IO ---------------------------------

const indent_width = 4

type IndentIO <: IO
    sink::IO
    indent::Integer  # current indentation
end
IndentIO(sink::IO) = IndentIO(sink, 0)

indent_io(io::IO) = indent_io(IndentIO(io))
indent_io(io::IndentIO) = (io.indent += indent_width; io)
dedent_io(io::IndentIO) = (io.indent -= indent_width; io)

function print(io::IndentIO, c::Char)
    print(io.sink, c)
    if (c == '\n'); print(io.sink, " "^io.indent); end
end

# Capture character output and send it to print(::IndentIO, ::Char)
write(io::IndentIO, x::Uint8)       = print(io, char(x))
write(io::IndentIO, s::ASCIIString) = (for c in s; print(io, c); end)
# Work around some types that do funky stuff in show()
show(io::IndentIO, x::Float32) = print(io, string(x))
show(io::IndentIO, x::Float64) = print(io, string(x))
show(io::IndentIO, x::Symbol)  = print(io, string(x))

# ---- @pprint ----------------------------------------------------------------

type PPrint
    io::Symbol
    code::Vector
end

macro pprint(args...)
    code_pprint(args...)
end
function code_pprint(io, args...)
#    @expect is_expr(ex, :tuple)
#    io, args = ex.args[1], ex.args[2:end]

    println("io = ", io)
    println("args = ", args)

    io_sym = gensym("io")
    c = PPrint(io_sym, {:( ($io_sym) = ($io) )})
    recode_pprint(c, args...)

    println("code =\n", expr(:block, c.code))

    esc(expr(:block, c.code))
end

recode_pprint(c::PPrint, exs...) = for ex in exs; recode_pprint(c, ex); end
function recode_pprint(c::PPrint, ex::Expr)
    head, args = ex.head, ex.args
    
    if head === :cell1d
        push(c.code, :(($c.io) = indent_io($c.io)))
        recode_pprint(c, args...)
        push(c.code, :(($c.io) = dedent_io($c.io)))
    elseif head === :call && is_expr(args[1], :vcat, 1)
        f = args[1].args[1]
        rest_args = args[2:end]
        push(c.code, :( ($f)(($c.io), $rest_args...) ))
    else
        recode_pprint(c, args...)
    end
end
recode_pprint(c::PPrint, ex) = (push(c.code, :(print(($c.io), ($ex))));nothing)
