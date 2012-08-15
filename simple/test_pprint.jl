
module TestPPrint
import Base.*
load("pprint.jl")

println(code_pprint( :(io, { [show](args[1]), head, [show](args[2]) }) ))

io=OUTPUT_STREAM
@pprint(io, "begin", {"\n",
    "f(", [show]("hej"), ")\n",
    "begin", {"\n",
        "hoj"
    }, "\nend",
}, "\nend")
    

end