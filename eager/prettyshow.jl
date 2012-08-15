
module PrettyShow
import Base.*
export @pprint, show_comma_list, indent
#const show_expr_type = Base.show_expr_type

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

type Indent; end
const indent = Indent()

type IndentIO <: IO
    sink::IO
    indent::Integer  # current indentation
end
IndentIO(sink::IO) = IndentIO(sink, 0)

enter(io::IO, ::Indent)       = enter(IndentIO(io), indent)
enter(io::IndentIO, ::Indent) = (io.indent += indent_width; io)
leave(io::IndentIO, ::Indent) = (io.indent -= indent_width; io)

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
# @pprint(io, args...) expands each argument args[k] in turn into 
# 
#     print(io, args[k])
#
# just like print(io, args...), except for that
#
# * [f](args...)  expands into  f(io, args...)
#   e g @pprint(io, '(', [show](x), ')')
#
# * [indent]{args...}  expands into  @pprint(io, args...) with args indented

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
    if head === :curly && is_expr(args[1], :vcat, 1)  # e g [indent]{x, '+', y}
        env = args[1].args[1]
        push(c.code, :( ($c.io) = ($quot(enter))(($c.io),($env)) ))
        recode_pprint(c, args[2:end]...)
        push(c.code, :( ($c.io) = ($quot(leave))(($c.io),($env)) ))
    elseif head === :call && is_expr(args[1], :vcat, 1) # e g [show](x)
        f = args[1].args[1]
        rest_args = args[2:end]
        push(c.code, :( ($f)(($c.io), $rest_args...) ))
    else                                                # regular printing
        push(c.code, :( print(($c.io), ($ex)) ))
    end
end
recode_pprint(c::PPrint, ex) = push(c.code, :(print(($c.io), ($ex))))

macro indent(io, body)
    quote
        (esc($io)) = enter(($esc(io)), indent)
        result = ($body)
        (esc($io)) = leave(($esc(io)), indent)
        result
    end
end

# ---- Expr prettyprinting ----------------------------------------------------

function show_expr_type(io, ty)
    if !is(ty, Any)
        if is(ty, Function)
            print(io, "::F")
        elseif is(ty, IntrinsicFunction)
            print(io, "::I")
        else
            print(io, "::$ty")
        end
    end
end

show_linenumber(io::IO, line)       = print(io,"\t#  line ",line,':')
show_linenumber(io::IO, line, file) = print(io,"\t#  ",file,", line ",line,':')

show(io::IO, e::SymbolNode) = (print(io, e.name); show_expr_type(io, e.typ))
show(io::IO, e::LineNumberNode) = show_linenumber(io, e.line)
show(io::IO, e::LabelNode)      = print(io, e.label, ": ")
show(io::IO, e::GotoNode)       = print(io, "goto ", e.label)
show(io::IO, e::TopNode)        = print(io, "top(", e.name, ')')
show(io::IO, e::QuoteNode)      = show_quoted_expr(io, e.value)

# Show arguments of a block, and then body
function show_body(io::IO, args::Vector, body)
    @pprint(io, [indent]{
            [show_comma_list](args...),
            [show_body_lines](body)
        })
end
show_body(io::IO, body)      = show_body(io, {},    body)
show_body(io::IO, arg, body) = show_body(io, {arg}, body)

# Show the body of a :block
function show_body_lines(io::IO, ex)
    args = is_expr(ex, :block) ? ex.args : {ex}
    for arg in args
        if !is_linenumber(arg); print(io, '\n'); end
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
        @indent io begin
            print(io, args[1], '.')
            if is_quoted(args[2]); show(io, unquoted(args[2]))
            else @pprint(io, '(', [indent]{[show](args[2])}, ')')
            end
        end
    elseif has(_expr_infix, head) && nargs == 2       # infix operations
        @pprint(io, [indent]{[show](args[1]), head, [show](args[2])})
    elseif is(head, :tuple)
        if (nargs == 1) @pprint(io, '(', [indent]{[show](args[1]), ','}, ')')
        else @pprint(io, '(', [indent]{[show_comma_list](args...)}, ')')
        end
    elseif has(_expr_parens, head)                # :vcat/:cell1d
        @pprint(io, _expr_parens[head][1], 
              [indent]{[show_comma_list](args...)},
              _expr_parens[head][2])
    elseif has(_expr_calls, head) && nargs >= 1  # :call/:ref/:curly
        @pprint(io, [show](args[1]), _expr_calls[head][1], 
              [indent]{[show_comma_list](args[2:end]...)},
              _expr_calls[head][2])
    elseif is(head, :comparison) && nargs >= 3 && (nargs&1==1)  # :comparison
        print(io, '(')
        @indent io (for arg in args; show(io, arg); end)
        print(io, ')')
    elseif is(head, :(...)) && nargs == 1
        show(io, args[1]); print(io, "...")
    elseif (nargs == 1 && contains([:return, :abstract, :const], head)) ||
                          contains([:local, :global], head)
        @pprint(io, head, ' ', [indent]{[show_comma_list](args...)})
    elseif is(head, :typealias) && nargs == 2
        @pprint(io, head, ' ', [indent]{
            [show](args[1]), ' ', [show](args[2])
        })
    elseif is(head, :quote) && nargs == 1       # :quote
        show_quoted_expr(io, args[1])
    elseif is(head, :line) && (1 <= nargs <= 2) # :line
        show_linenumber(io, args...)
    elseif is(head, :if) && nargs == 3  # if/else
        @pprint(io, 
            "if ",     [show_body](args[1], args[2]),
            "\nelse ", [show_body](args[3]),
            "\nend")
    elseif is(head, :try) && nargs == 3 # try[/catch]
        @pprint(io, "try ", [show_body](args[1]))
        if !(is(args[2], false) && is_expr(args[3], :block, 0))
            @pprint(io, "\ncatch ", [show_body](args[2], args[3]))
        end
        print(io, "\nend")
    elseif is(head, :let)               # :let 
        @pprint(io, "let ", [show_body](args[2:end], args[1]), "\nend")
    elseif is(head, :block)
        @pprint(io, "begin ", [show_body](ex), "\nend")
    elseif contains([:for, :while, :function, :if, :type], head) && nargs == 2
        @pprint(io, head, ' ', [show_body](args[1], args[2]), "\nend")
    elseif is(head, :null)
        print(io, "nothing")
    elseif is(head, :gotoifnot)
        @pprint(io, "unless ", [show](args[1]), " goto ",[show](args[2]))
    elseif is(head, :string)
        show(io, args[1])
    else
        @pprint(io, head, '(', [indent]{[show_comma_list](args...)}, ')')
    end
    show_expr_type(io, ex.typ)
end

# show ex as if it were quoted
function show_quoted_expr(io::IO, sym::Symbol)
    if is(sym,:(:)) || is(sym,:(==)); print(io, ":($sym)")        
    else                              print(io, ":$sym")        
    end
end
function show_quoted_expr(io::IO, ex::Expr)
    if is(ex.head, :block); @pprint(io, "quote ", [show_body](ex), "\nend")
    else @pprint(io, "quote",  '(', [indent]{[show](ex)}, ')')
    end
end
show_quoted_expr(io::IO, ex) = @pprint(io, ':', '(', [indent]{[show](ex)}, ')')

end # module PrettyShow
