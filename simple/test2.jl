
code = quote
    function show_body_lines(io::IO, ex)
        args = is_expr(ex, :block) ? ex.args : {ex}
        for arg in args
            if !is_linenumber(arg); print(io, '\n'); end
            show(io, arg)
        end
    end
end

show(code)
