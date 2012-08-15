
begin
    
end

pprint(io, {
    [comma_list(args)],
    [show_body_lines(body)]
})

pprint(io, {
    ()->comma_list(args),
    ()->show_body_lines(body)
})

@pprint(io, {()->show(args[1]), head, ()->show(args[2])})
@pprint(io, {[show(args[1]], head, [args[2]])})
@pprint(io, [ (@io show(args[1])), head, (@io show(args[2])) ])
@pprint(io, [ [show](args[1])), head, [show](args[2]) ])
@pprint(io, [ {show}(args[1])), head, {show}(args[2]) ])
@pprint(io, { [show](args[1]), head, [show](args[2]) })

@pprint(io, head, ' ', [@io comma_list(args...)])
@pprint(io, head, ' ', { [comma_list](args...) })
