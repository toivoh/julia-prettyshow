
require("recshow.jl")

type N
    xs::Vector
    N(args...) = new({args...})
end

function show(io::IO, node::N)
    print(io, "N(")
    show_comma_list(io, node.xs...)
    print(io, ')')
end

arg = :arg
arg1 = N(:gate, arg, N(:guard, N(isa, arg, Vector)))
arg2 = N(:gate, arg1, N(:guard, N(:egal, N(length, arg1, 3))))

e1 = N(ref, arg2, 1)
e2 = N(ref, arg2, 2)
e3 = N(ref, arg2, 3)

g1 = N(:guard, N(:egal, e1, 1))
g2 = N(:guard, N(:egal, e2, :x))
g3 = N(:guard, N(isa, e3, Int))

guards = N(:nodeset, g1, g2, g3)


println(guards)
println()

recshow(guards)


