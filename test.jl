
require("recshow.jl")

type T
    x
    y
end

type Unshowable; end
show(io::IO, x::Unshowable) = error("Tried to show Unshowable()")


println("Simple and tree structured objects: just as show")
recshow(1.55);   println()
recshow(155);    println()
recshow("abc");  println()
recshow(T(1,2)); println()

println("\nSelf-referential object:")
s = T(1,1); s.y = s
recshow(s); println()

println("DAG structured object:")
t = T(1,1)
recshow(T(t,t)); println()

println("Exception during show recording ==> partial printout:")
recshow(T(s, Unshowable()))
