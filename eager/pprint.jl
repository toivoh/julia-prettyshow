
show(io, x) = isa(io,IOStream) ? ccall(:jl_show_any, Void, (Any,Any,), io, x) :
              print(io, repr(x))

macro expect(pred)
    :( ($esc(pred)) ? nothing : error($"error: expected $pred == true") )
end

# ---- Expr decoding helpers --------------------------------------------------

is_expr(ex, head::Symbol) = (isa(ex, Expr) && (ex.head == head))
is_expr(ex, head::Symbol, n::Int) = is_expr(ex, head) && length(ex.args) == n

is_linenumber(ex::LineNumberNode) = true
is_linenumber(ex::Expr)           = is(ex.head, :line)
is_linenumber(ex)                 = false

is_quoted(ex::QuoteNode) = true
is_quoted(ex::Expr)      = is_expr(ex, :quote, 1)
is_quoted(ex)            = false

unquoted(ex::QuoteNode) = ex.value
unquoted(ex::Expr)      = ex.args[1]

# ---- formatting helpers -----------------------------------------------------

function show_comma_list(io::IO, first, rest...)
    show(io, first)
    for arg in rest; print(io, ", "); show(io, arg); end
end
show_comma_list(io::IO) = nothing

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

# ---- @pprint: simple printing convenience macro -----------------------------

quot(ex) = expr(:quote, ex)

type PPrint
    io::Symbol
    code::Vector
end

macro pprint(args...)
    code_pprint(args...)
end
function code_pprint(io, args...)
    io_sym = gensym("io")
    c = PPrint(io_sym, {:( ($io_sym) = ($io) )})
    recode_pprint(c, args...)
    esc(expr(:block, c.code))
end

recode_pprint(c::PPrint, exs...) = for ex in exs; recode_pprint(c, ex); end
function recode_pprint(c::PPrint, ex::Expr)
    head, args = ex.head, ex.args    
    if head === :cell1d
        push(c.code, :( ($c.io) = ($quot(indent_io))($c.io) ))
        recode_pprint(c, args...)
        push(c.code, :(($c.io) = ($quot(dedent_io))($c.io) ))
    elseif head === :call && is_expr(args[1], :vcat, 1)
        f = args[1].args[1]
        rest_args = args[2:end]
        push(c.code, :( ($f)(($c.io), $rest_args...) ))
    else
        push(c.code, :( print(($c.io), ($ex)) ))
    end
end
recode_pprint(c::PPrint, ex) = push(c.code, :( print(($c.io), ($ex)) ))

