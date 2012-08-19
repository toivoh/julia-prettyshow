
#module PrettyShow
#import Base.*
const show_expr_type = Base.show_expr_type


const indent_width = 4

## AST decoding helpers ##

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

## AST printing ##

show_quoted(  io::IO, x)         = show_quoted(io, x, 0)
show_quoted(  io::IO, x, indent) = show(io, x)
show_unquoted(io::IO, x)         = show_unquoted(io, x, 0)
show_unquoted(io::IO, x, indent) = show(io, x)

const _expr_parens = {:tuple=>('(',')'), :vcat=>('[',']'), :cell1d=>('{','}')}

show(io::IO, ex::Expr) = show_quoted(io, ex)
# show ex as quoted
function show_quoted(io::IO, ex::Expr, indent::Int)
    if is(ex.head, :block) || is(ex.head, :body)
        show_block(io, "quote", ex, indent); print(io, "end")
    elseif has(_expr_parens, ex.head)
        print(io, ':')
        show_unquoted(io, ex, indent + indent_width)        
    else
        default_show_quoted(io, ex, indent)
    end
end
function show_quoted(io::IO, sym::Symbol, indent::Int)
    if is(sym,:(:)) || is(sym,:(==)); print(io, ":($sym)")        
    else                              print(io, ":$sym")        
    end
end
show_quoted(io::IO, ex, indent::Int) = default_show_quoted(io, ex, indent)
function default_show_quoted(io::IO, ex, indent::Int)
    print(io, ":( ")
    show_unquoted(io, ex, indent + indent_width)
    print(io, " )")
end

# used to show if/let/for/etc blocks
function show_block(io::IO, head, args::Vector, body, indent::Int)
    print(io, head, ' ')
    show_list(io, args, ", ", indent)

    ind = is(head, :module) ? indent : indent + indent_width
    exs = (is_expr(body, :block) || is_expr(body, :body)) ? body.args : {body}
    for ex in exs
        if !is_linenumber(ex); print(io, '\n', " "^ind); end
        show_unquoted(io, ex, ind)
    end
    print(io, '\n', " "^indent)
end
function show_block(io::IO, head, block, indent::Int)
    show_block(io, head, {}, block, indent)
end
function show_block(io::IO, head, arg, block, indent::Int)
    show_block(io, head, {arg}, block, indent)
end

# show the body of a :block
function show_body(io::IO, ex, indent::Int)
end

# show an indented list
function show_list(io::IO, items, sep, indent::Int)
    n = length(items)
    if n == 0; return end
    indent += indent_width
    show_unquoted(io, items[1], indent)
    for item in items[2:end]
        print(io, sep)
        show_unquoted(io, item, indent)        
    end
end
# show an indented list inside parens op, cl
function show_enclosed_list(io::IO, op, items, sep, cl, indent)
    print(io, op); show_list(io, items, sep, indent); print(io, cl)
end


show_linenumber(io::IO, line)       = print(io,"\t#  line ",line,':')
show_linenumber(io::IO, line, file) = print(io,"\t#  ",file,", line ",line,':')

const _expr_infix_wide = Set(:(=), :(+=), :(-=), :(*=), :(/=), :(\=), 
    :(&=), :(|=), :($=), :(>>>=), :(>>=), :(<<=), :(&&), :(||))
const _expr_infix = Set(:(:), :(<:), :(->), :(=>), symbol("::"))
const _expr_calls  = {:call =>('(',')'), :ref =>('[',']'), :curly =>('{','}')}

# show ex as unquoted
function show_unquoted(io::IO, ex::Expr, indent::Int)
    head, args, nargs = ex.head, ex.args, length(ex.args)

    if is(head, :(.))
        show_unquoted(io, args[1], indent + indent_width)
        print(io, '.')
        if is_quoted(args[2]) 
            show_unquoted(io, unquoted(args[2]), indent + indent_width)
        else
            print(io, '(')
            show_unquoted(io, args[2], indent + indent_width)
            print(io, ')')
        end                  
    elseif (has(_expr_infix, head) && nargs==2) || (is(head,:(:)) && nargs==3)
        show_list(io, args, head, indent)
    elseif has(_expr_infix_wide, head) && nargs == 2
        show_list(io, args, " $head ", indent)
    elseif has(_expr_parens, head)                # :vcat/:cell1d
        op, cl = _expr_parens[head]
        print(io, op)
        show_list(io, args, ", ", indent)
        if is(head, :tuple); print(io, ','); end
        print(io, cl)
    elseif has(_expr_calls, head) && nargs >= 1  # :call/:ref/:curly
        op, cl = _expr_calls[head]
        show_unquoted(io, args[1], indent)
        show_enclosed_list(io, op, args[2:end], ", ", cl, indent)
    elseif is(head, :comparison) && nargs >= 3 && (nargs&1==1)  # :comparison
        show_enclosed_list(io, '(', args, "", ')', indent)
    elseif is(head, :(...)) && nargs == 1
        show_unquoted(io, args[1], indent)
        print(io, "...")
    elseif (nargs == 1 && contains([:return, :abstract, :const], head)) ||
                          contains([:local, :global], head)
        print(io, head, ' ')
        show_list(io, args, ", ", indent)
    elseif is(head, :macrocall) && nargs >= 1
        print(io, '@')
        show_list(io, args, " ", indent)
    elseif is(head, :typealias) && nargs == 2
        print(io, "typealias ")
        show_list(io, args, ' ', indent)
    elseif is(head, :line) && (1 <= nargs <= 2) # :line
        show_linenumber(io, args...)
    elseif is(head, :if) && nargs == 3
        show_block(io, "if",   args[1], args[2], indent)
        show_block(io, "else", args[3], indent)
        print(io, "end")
    elseif is(head, :try) && nargs == 3
        show_block(io, "try", args[1], indent)
        if !(is(args[2], false) && is_expr(args[3], :block, 0))
            show_block(io, "catch", args[2], args[3], indent)
        end
        print(io, "end")
    elseif is(head, :let) && nargs >= 1
        show_block(io, "let", args[2:end], args[1], indent); print(io, "end")
    elseif is(head, :block) || is(head, :body)
        show_block(io, "begin", ex, indent); print(io, "end")
    elseif contains([:for, :while, :function, :if, :type, :module], head) &&
      nargs == 2
        show_block(io, head, args[1], args[2], indent); print(io, "end")
    elseif is(head, :quote) && nargs == 1
        show_quoted(io, args[1], indent)
    elseif is(head, :null)
        print(io, "nothing")
    elseif is(head, :gotoifnot) && nargs == 2
        print(io, "unless ")
        show_unquoted(io, args[1], indent + indent_width)
        print(io, "goto ")
        show_unquoted(io, args[2], indent + indent_width)
    elseif is(head, :string) && nargs == 1 && isa(args[1], String)
        show(io, args[1])
    else
        print(io, "(\$expr(")
        show_quoted(io, ex.head, indent)
        for arg in args
            print(io, ", ")
            show_quoted(io, arg, indent)
        end
        print(io, "))")
    end
    show_expr_type(io, ex.typ)
end

#end # module
