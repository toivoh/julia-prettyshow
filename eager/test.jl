
load("prettyshow.jl")

module Test
import Base.*
import PrettyShow
import PrettyShow.*
const is_expr = PrettyShow.is_expr

code = quote

# ---- print/show helpers and markup ------------------------------------------

function show_comma_list(io::IO, first, rest...)
    show(io, first)
    for arg in rest; print(io, ", "); show(io, arg); end
end
show_comma_list(io::IO) = nothing

type Indented
    item  # value to be printed indented
end

type DeferredIO
    f::Function
    extra_args::Tuple
end
print(io::IO, d::DeferredIO) = d.f(io, d.extra_args...)

defer_io(f, extra_args...) = DeferredIO(f, extra_args)

defer_print()        = ""
defer_print(arg)     = arg
defer_print(args...) = defer_io(print, args...)
defer_show(arg)      = defer_io(show, arg)

indent(arg)          = Indented(arg)
indent(args...)      = Indented(defer_print(args...))

inparens(args...)    = defer_print('(', indent(args...), ')')

comma_list()         = ""
comma_list(args...)  = defer_io(show_comma_list, args...)



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


# ---- Expr decoding helpers --------------------------------------------------

is_expr(ex, head::Symbol) = (isa(ex, Expr) && (ex.head == head))
function is_expr(ex, head::Symbol, nargs::Int)
    is_expr(ex, head) && length(ex.args) == nargs
end

is_quoted(ex::QuoteNode) = true
is_quoted(ex::Expr)      = is_expr(ex, :quote, 1)
is_quoted(ex)            = false

unquoted(ex::QuoteNode) = ex.value
unquoted(ex::Expr)      = (@assert is_quoted(ex); ex.args[1])

const doublecolon = symbol("::")


# ---- Expr prettyprinting ----------------------------------------------------

function lnshow_bodyline(io::IO, ex)
    if !is_expr(ex, :line); print(io, '\n'); end
    show(io, ex)
end

## show the body of a :block
function show_mainbody(io::IO, ex)
    if is_expr(ex, :block); for arg in ex.args; lnshow_bodyline(io, arg); end
    else                    lnshow_bodyline(io, ex)
    end
end

## show arguments of a block, and then body
function show_body(io::IO, args::Vector, body)
    print(io, indent(
            comma_list(args...),
            defer_io(show_mainbody, body)
        ))
end
show_body(io::IO, body)      = show_body(io, {},    body)
show_body(io::IO, arg, body) = show_body(io, {arg}, body)
defer_show_body(args...) = defer_io(show_body, args...)

function show(io::IO, ex::Expr)
    const infix = Set(:(=), :(:), :(<:), :(->), :(=>), :(&&), :(||),
                      doublecolon)
    const calltypes  = {:ref =>('[',']'), :curly =>('{','}'), :call=>('(',')')}
    const parentypes = {:vcat=>('[',']'), :cell1d=>('{','}')}

    head = ex.head
    args = ex.args
    nargs = length(args)

    if head == :(.)
        print(io, indent(args[1], '.'))
        if is_quoted(args[2]); show(io, unquoted(args[2]))
        else print(io, inparens(defer_show(args[2])))
        end
    elseif has(infix, head) && nargs == 2       # infix operations
        print(io, indent(defer_show(args[1]), head, defer_show(args[2])))
    elseif is(head, :tuple)
        if nargs == 1; print(io, inparens(defer_show(args[1]), ','))
        else           print(io, inparens(comma_list(args...)))
        end
    elseif has(parentypes, head)                # :vcat/:cell1d
        print(io, parentypes[head][1], 
              indent(comma_list(args...)),
              parentypes[head][2])
    elseif has(calltypes, head) && nargs >= 1  # :call/:ref/:curly
        show(io, args[1]); 
        print(io, calltypes[head][1], 
              indent(comma_list(args[2:end]...)),
              calltypes[head][2])
    elseif head == :comparison && nargs >= 2    # :comparison
        print(io, inparens({defer_show(arg) for arg in args}...))
    elseif head == :(...) && nargs == 1
        show(io, args[1]); print(io, "...")
    elseif (nargs == 1 && contains([:return, :abstract, :const], head)) ||
                          contains([:local, :global], head)
        print(io, head, ' ', indent(comma_list(args...)))
    elseif head == :typealias && nargs == 2
        print(io, head, ' ', indent(
            defer_show(args[1]), ' ', defer_show(args[2])
        ))
    elseif (head == :quote) && (nargs==1)       # :quote
        show_quoted_expr(io, args[1])
    elseif (head == :line) && (1 <= nargs <= 2) # :line
        if nargs == 1; print(io, "\t#  line ", args[1], ':')
        else;          print(io, "\t#  ", args[2], ", line ", args[1], ':')
        end
    elseif head == :if && nargs == 3  # if/else
        print(io, 
            "if ",     defer_show_body(args[1], args[2]),
            "\nelse ", defer_show_body(args[3]),
            "\nend")
    elseif head == :try && nargs == 3 # try[/catch]
        print(io, "try ", defer_show_body(args[1]))
        if !(is(args[2], false) && is_expr(args[3], :block, 0))
            print(io, "\ncatch ", defer_show_body(args[2], args[3]))
        end
        print(io, "\nend")
    elseif head == :let               # :let 
        print(io, "let ", defer_show_body(args[2:end], args[1]), "\nend")
    elseif head == :block
        print(io, "begin ", defer_show_body(ex), "\nend")
    elseif contains([:for, :while, :function, :if, :type], head) && nargs == 2
        print(io, head, ' ', defer_show_body(args[1], args[2]), "\nend")
    else
        print(io, head, inparens(comma_list(args...)))
    end
end

# show ex as if it were quoted
function show_quoted_expr(io::IO, sym::Symbol)
    if is(sym,:(:)) || is(sym,:(==)); print(io, ":($sym)")        
    else                              print(io, ":$sym")        
    end
end
function show_quoted_expr(io::IO, ex::Expr)
    if ex.head == :block; print(io, "quote ", defer_show_body(ex), "\nend")
    else                  print(io, "quote", inparens(defer_show(ex)))
    end
end
show_quoted_expr(io::IO, ex) = print(io, ':', inparens(defer_show(ex)))

end  # quote


for ex in code.args
    print(ex)
    if is_expr(ex, :line); println(); end
end

export @pprint

end # module Test
