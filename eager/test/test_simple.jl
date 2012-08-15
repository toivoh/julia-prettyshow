
load("prettyshow.jl")

module TestSimple
import Base.*
import PrettyShow
import PrettyShow.*
const _expr_calls = PrettyShow._expr_calls

ex = :(f(x))
head, args = ex.head, ex.args

io = OUTPUT_STREAM
@pprint(io, _expr_calls[head][1])
# @pprint(io, _expr_calls[head][1], 
#     {[show_comma_list](args[2:end]...)},
#     _expr_calls[head][2])

println("\n")
println(_expr_calls[head][1])

end