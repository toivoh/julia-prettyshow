

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
pshow(io::IO,        arg) = showt(pretty(io), arg)
pshow(arg) = pshow(OUTPUT_STREAM, arg)


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


# -- PrettyNest ---------------------------------------------------------------

type PrettyNest
    f::Function
    extra_args::Tuple

    PrettyNest(f::Function, extra_args::Tuple) = new(f, extra_args)
    PrettyNest(f::Function) = new(f, ())
end
show(io::PrettyIO, pc::PrettyNest) = pc.f(io, pc.extra_args...)
show(io::IO, pc::PrettyNest) = pshow(io, pc)

indent(args...) = PrettyNest(io->(print(indented(io), args...)))

