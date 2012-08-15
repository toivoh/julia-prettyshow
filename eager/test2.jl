
load("prettyshow.jl")

module Test
import Base.*
import PrettyShow

code = quote

function recode_pprint(c::PPrint, ex::Expr)
    head, args = ex.head, ex.args    
    if head === :cell1d
        push(c.code, :( ($c.io) = ($quot(indent_io))($c.io) ))
        recode_pprint(c, args...)
        push(c.code, :(($c.io) = ($quot(dedent_io))($c.io) ))
    elseif head === :call && is_expr(args[1], :vcat, 1)
        f = args[1].args[1]
        rest_args = args[2:end]
        push(c.code, :( ($f)(($c.io), $rest_args...) ))
    else
        push(c.code, :( print(($c.io), ($ex)) ))
    end
end

end # quote

println(code)

end