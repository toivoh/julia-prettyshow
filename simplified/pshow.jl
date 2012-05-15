

is_expr(ex, head::Symbol) = (isa(ex, Expr) && (ex.head == head))
function is_expr(ex, head::Symbol, nargs::Int)
    is_expr(ex, head) && length(ex.args) == nargs
end


# -- PrettyIO -----------------------------------------------------------------

abstract PrettyIO <: IO
pretty(io::PrettyIO) = io
pretty() = pretty(OUTPUT_STREAM)

for T in {:ASCIIString, :UTF8String, :RopeString, :String}
    @eval print(io::PrettyIO, s::($T)) = pprint(io, s)
end

pprintln(args...) = pprint(args..., '\n')

pprint(io::PrettyIO, args...) = print(io, args...)
pprint(io::IO,       args...) = print(pretty(io), args...)
pprint(args...) = pprint(OUTPUT_STREAM, args...)

pshow(io::PrettyIO,  arg) = show(io, arg)
pshow(io::IO,        arg) = show(pretty(io), arg)
pshow(arg) = pshow(OUTPUT_STREAM, arg)

#print(io::PrettyIO, x) = error("unimplemented: print(::PrettyIO, $(typeof(x))")
#print(io::PrettyIO, x) = show(io, x)

# -- PrettyTerminal -----------------------------------------------------------

type PrettyTerminal <: IO
    parent::IO
    width::Int

    currpos::Int
    wrap::Bool
    
    function PrettyTerminal(parent::IO, width::Int)
        if width < 1; error("width must be >= 1, got ", width); end
        new(parent, width, 0, true)
    end
end

function rawprint(io::PrettyTerminal, c::Char)
    print(io.parent, c)
    io.currpos += 1
    if c == '\n'; io.currpos = 0; end
end
function print(io::PrettyTerminal, c::Char)
    if io.wrap && (io.currpos >= io.width); rawprint(io, '\n'); end  # wrap

    if c=='\t';  for k=1:((-io.currpos)&7); rawprint(io, ' '); end   # tab
    else;        rawprint(io, c);  end                               # others
end


# -- PrettyStream -------------------------------------------------------------

type PrettyStream <: PrettyIO
    parent::PrettyTerminal
    indent::Int
end
pretty(io::IO) = PrettyStream(PrettyTerminal(io, 80), 0)

indented(io::PrettyStream) = PrettyStream(io.parent, io.indent+4)

function print(io::PrettyStream, c::Char)
    if (io.parent.currpos == 0) && (io.indent > 0)  # indent
        io.parent.wrap = false
        for k=1:io.indent; print(io.parent, ' '); end
        io.parent.wrap = (2*io.parent.currpos >= io.parent.width)
    end
    print(io.parent, c)
end

function pprint(io::PrettyStream, s::String)
    n = strlen(s)
    if (io.indent+n <= io.parent.width < io.parent.currpos+n)  
        pprint(io, '\n')  # wrap string to next line
    end
    for c in s; pprint(io, c); end
end


# -- PNest --------------------------------------------------------------------

type PNest
    f::Function
    extra_args::Tuple

    PNest(f::Function, extra_args::Tuple) = new(f, extra_args)
    PNest(f::Function) = new(f, ())
end
show(io::PrettyIO, pc::PNest) = pc.f(io, pc.extra_args...)
show(io::IO, pc::PNest) = pshow(io, pc)

indent(args...) = PNest(io->(print(indented(io), args...)))


# == Expr prettyprinting ======================================================

const doublecolon = @eval (:(x::Int)).head

## list printing
function pshow_comma_list(io::PrettyIO, args::Vector, 
                          open::String, close::String) 
    pshow_delim_list(io, args, open, ", ", close)
end
function pshow_delim_list(io::PrettyIO, args::Vector, open::String, 
                          delim::String, close::String)
    pprint(io, indent(open, 
                PNest(pshow_list_delim, args, delim)),
           close)
end
function pshow_list_delim(io::PrettyIO, args::Vector, delim::String)
    for (arg, k) in enumerate(args)
        show(io, arg)
        if k < length(args)
            pprint(io, delim)
        end
    end
end

## show the body of a :block
pshow_mainbody(io::PrettyIO, ex) = show(io, ex)
function pshow_mainbody(io::PrettyIO, ex)
    if is_expr(ex, :block)
        args = ex.args
        for (arg, k) in enumerate(args)
            if !is_expr(arg, :line)
                pprint(io, "\n")
            end
            show(io, arg)
        end
    else
        if !is_expr(ex, :line);  pprint(io, "\n");  end
        show(io, ex)
    end
end

## show arguments of a block, and then body
pshow_body(io::PrettyIO, body) = pshow_body(io, {}, body)
function pshow_body(io::PrettyIO, arg, body)
    pprint(io, indent(arg, PNest(pshow_mainbody, body) ))
end
function pshow_body(io::PrettyIO, args::Vector, body)
    pprint(io, indent(
            PNest(pshow_comma_list, args, "", ""), 
            PNest(pshow_mainbody, body)
        ))
end

## show ex as if it were quoted
function pshow_quoted_expr(io::PrettyIO, sym::Symbol)
    if !is(sym,:(:)) && !is(sym,:(==))
        pprint(io, ":$sym")
    else
        pprint(io, ":($sym)")
    end
end
function pshow_quoted_expr(io::PrettyIO, ex::Expr)
    if ex.head == :block
        pprint(io, "quote ", PNest(pshow_body, ex), "\nend")
    else
        pprint(io, "quote(", indent(ex), ")")
    end
end
pshow_quoted_expr(io::PrettyIO, ex) =pprint(io, ":($ex)")


## show an expr
function show(io::PrettyIO, ex::Expr)
    const infix = {:(=)=>"=", :(.)=>".", doublecolon=>"::", :(:)=>":",
                   :(->)=>"->", :(=>)=>"=>",
                   :(&&)=>" && ", :(||)=>" || "}
    const parentypes = {:call=>("(",")"), :ref=>("[","]"), :curly=>("{","}")}

    head = ex.head
    args = ex.args
    nargs = length(args)

    if has(infix, head) && nargs==2             # infix operations
#        pprint(io, "(",indent(args[1], infix[head], args[2]),")")
        pprint(io, indent(args[1], infix[head], args[2]))
    elseif has(parentypes, head) && nargs >= 1  # :call/:ref/:curly
        pprint(io, args[1])
        pshow_comma_list(io, args[2:end], parentypes[head]...)
    elseif (head == :comparison) && (nargs>=3 && isodd(nargs)) # :comparison
        pprint("(",indent(args),")")
    elseif ((contains([:return, :abstract, :const] , head) && nargs==1) ||
            contains([:local, :global], head))
        pshow_comma_list(io, args, string(head)*" ", "")
    elseif head == :typealias && nargs==2
        pshow_delim_list(io, args, string(head)*" ", " ", "")
    elseif (head == :quote) && (nargs==1)       # :quote
        pshow_quoted_expr(io, args[1])
    elseif (head == :line) && (1 <= nargs <= 2) # :line
        let #io=comment(io)
            if nargs == 1
                linecomment = "line "*string(args[1])*": "
            else
                @assert nargs==2
#               linecomment = "line "*string(args[1])*", "*string(args[2])*": "
                linecomment = string(args[2])*", line "*string(args[1])*": "
            end
            pprint(io, "\t#  ", linecomment)
#             if str_fits_on_line(io, strlen(linecomment)+13)
#                 pprint(io, "\t#  ", linecomment)
#             else
#                 pprint(io, "\n", linecomment)
#             end
        end
    elseif head == :if && nargs == 3  # if/else
        pprint(io, 
            "if ", PNest(pshow_body, args[1], args[2]),
            "\nelse ", PNest(pshow_body, args[3]),
            "\nend")
    elseif head == :try && nargs == 3 # try[/catch]
        pprint(io, "try ", PNest(pshow_body, args[1]))
        if !(is(args[2], false) && is_expr(args[3], :block, 0))
            pprint(io, "\ncatch ", PNest(pshow_body, args[2], args[3]))
        end
        pprint(io, "\nend")
    elseif head == :let               # :let 
        pprint(io, "let ", 
            PNest(pshow_body, args[2:end], args[1]), "\nend")
    elseif head == :block
        pprint(io, "begin ", PNest(pshow_body, ex), "\nend")
    elseif contains([:for, :while, :function, :if, :type], head) && nargs == 2
        pprint(io, string(head), " ", 
            PNest(pshow_body, args[1], args[2]), "\nend")
    else
        pprint(io, head)
        pshow_comma_list(indent(io), args, "(", ")")
    end
end
