
code = quote

function show_block(io::IO, head, args::Vector, body, indent::Int)
    print(io, head, ' ')
    show_list(io, args, ", ", indent)

    ind = indent + indent_width
    exs = (is_expr(body, :block) || is_expr(body, :body)) ? body.args : {body}
    for ex in exs
        if !is_linenumber(ex); print(io, '\n', " "^ind); end
        show_unquoted(io, ex, ind)
    end
    print(io, '\n', " "^indent)
end

end # quote

println(code)
