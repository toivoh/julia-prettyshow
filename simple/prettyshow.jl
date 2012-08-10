
module PrettyShow
import Base.*
export defer_io, defer_print, defer_show, indent, paren_block, comma_list


# ---- Deferred IO for formatting etc -----------------------------------------

# Canned io action: print(io, defer_io(f, rest_args...))
# does the same as f(io, rest_args...)
defer_io(f, rest_args...) = DeferredIO(f, rest_args)

defer_print()        = ""
defer_print(arg)     = arg
defer_print(args...) = defer_io(print, args...)
defer_show(arg)      = defer_io(show,  arg)

indent(arg)          = Indented(arg)
indent(args...)      = Indented(defer_print(args...))

paren_block(args...) = defer_print('(', indent(args...), ')')

comma_list()         = ""
comma_list(args...)  = defer_io(show_comma_list, args...)


type DeferredIO
    f::Function
    rest_args::Tuple
end
print(io::IO, d::DeferredIO) = d.f(io, d.rest_args...)

type Indented
    item  # value to be printed indented
end

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

# Capture character output and send it to print(::IndentIO, ::Char)
write(io::IndentIO, x::Uint8)       = print(io, char(x))
write(io::IndentIO, s::ASCIIString) = (for c in s; print(io, c); end)
# Work around some types that do funky stuff in show()
show(io::IndentIO, x::Float32) = print(io, string(x))
show(io::IndentIO, x::Float64) = print(io, string(x))
show(io::IndentIO, x::Symbol)  = print(io, string(x))


# ---- Expr decoding helpers --------------------------------------------------

is_expr(ex, head::Symbol) = (isa(ex, Expr) && (ex.head == head))
is_expr(ex, head::Symbol, n::Int) = is_expr(ex, head) && length(ex.args) == n

is_quoted(ex::QuoteNode) = true
is_quoted(ex::Expr)      = is_expr(ex, :quote, 1)
is_quoted(ex)            = false

unquoted(ex::QuoteNode) = ex.value
unquoted(ex::Expr)      = (@assert is_expr(ex, :quote, 1); ex.args[1])


# ---- Expr prettyprinting ----------------------------------------------------

# Show arguments of a block, and then body
function show_body(io::IO, args::Vector, body)
    print(io, indent(
            comma_list(args...),
            defer_io(show_body_lines, body)
        ))
end
show_body(io::IO, body)      = show_body(io, {},    body)
show_body(io::IO, arg, body) = show_body(io, {arg}, body)
defer_show_body(args...) = defer_io(show_body, args...)

# Show the body of a :block
function show_body_lines(io::IO, ex)
    args = is_expr(ex, :block) ? ex.args : {ex}
    for arg in args
        if !is_expr(arg, :line); print(io, '\n'); end
        show(io, arg)
    end
end


const _expr_infix = Set(
    :(+=), :(-=), :(*=), :(/=), :(\=), :(&=), :(|=), :($=), 
    :(>>>=), :(>>=), :(<<=),
    :(=), :(:), :(<:), :(->), :(=>), :(&&), :(||), symbol("::"))
const _expr_calls  = {:ref =>('[',']'), :curly =>('{','}'), :call=>('(',')')}
const _expr_parens = {:vcat=>('[',']'), :cell1d=>('{','}')}

function show(io::IO, ex::Expr)
    head = ex.head
    args = ex.args
    nargs = length(args)

    if is(head, :(.))
        print(io, indent(args[1], '.'))
        if is_quoted(args[2]); show(io, unquoted(args[2]))
        else print(io, paren_block(defer_show(args[2])))
        end
    elseif has(_expr_infix, head) && nargs == 2       # infix operations
        print(io, indent(defer_show(args[1]), head, defer_show(args[2])))
    elseif is(head, :tuple)
        if nargs == 1; print(io, paren_block(defer_show(args[1]), ','))
        else           print(io, paren_block(comma_list(args...)))
        end
    elseif has(_expr_parens, head)                # :vcat/:cell1d
        print(io, _expr_parens[head][1], 
              indent(comma_list(args...)),
              _expr_parens[head][2])
    elseif has(_expr_calls, head) && nargs >= 1  # :call/:ref/:curly
        show(io, args[1]); 
        print(io, _expr_calls[head][1], 
              indent(comma_list(args[2:end]...)),
              _expr_calls[head][2])
    elseif is(head, :comparison) && nargs >= 2    # :comparison
        print(io, paren_block({defer_show(arg) for arg in args}...))
    elseif is(head, :(...)) && nargs == 1
        show(io, args[1]); print(io, "...")
    elseif (nargs == 1 && contains([:return, :abstract, :const], head)) ||
                          contains([:local, :global], head)
        print(io, head, ' ', indent(comma_list(args...)))
    elseif is(head, :typealias) && nargs == 2
        print(io, head, ' ', indent(
            defer_show(args[1]), ' ', defer_show(args[2])
        ))
    elseif is(head, :quote) && nargs == 1       # :quote
        show_quoted_expr(io, args[1])
    elseif is(head, :line) && (1 <= nargs <= 2) # :line
        if nargs == 1; print(io, "\t#  line ", args[1], ':')
        else;          print(io, "\t#  ", args[2], ", line ", args[1], ':')
        end
    elseif is(head, :if) && nargs == 3  # if/else
        print(io, 
            "if ",     defer_show_body(args[1], args[2]),
            "\nelse ", defer_show_body(args[3]),
            "\nend")
    elseif is(head, :try) && nargs == 3 # try[/catch]
        print(io, "try ", defer_show_body(args[1]))
        if !(is(args[2], false) && is_expr(args[3], :block, 0))
            print(io, "\ncatch ", defer_show_body(args[2], args[3]))
        end
        print(io, "\nend")
    elseif is(head, :let)               # :let 
        print(io, "let ", defer_show_body(args[2:end], args[1]), "\nend")
    elseif is(head, :block)
        print(io, "begin ", defer_show_body(ex), "\nend")
    elseif contains([:for, :while, :function, :if, :type], head) && nargs == 2
        print(io, head, ' ', defer_show_body(args[1], args[2]), "\nend")
    elseif is(head, :null)
        print(io, "nothing")
    elseif is(head, :gotoifnot)
        print(io, "unless ", defer_show(args[1]), " goto ",defer_show(args[2]))
    elseif is(head, :string)
        show(io, args[1])
    else
        print(io, head, paren_block(comma_list(args...)))
    end
end

# show ex as if it were quoted
function show_quoted_expr(io::IO, sym::Symbol)
    if is(sym,:(:)) || is(sym,:(==)); print(io, ":($sym)")        
    else                              print(io, ":$sym")        
    end
end
function show_quoted_expr(io::IO, ex::Expr)
    if is(ex.head, :block); print(io, "quote ", defer_show_body(ex), "\nend")
    else                    print(io, "quote",  paren_block(defer_show(ex)))
    end
end
show_quoted_expr(io::IO, ex) = print(io, ':', paren_block(defer_show(ex)))

end # module PrettyShow
