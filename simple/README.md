julia-prettyshow v0.1
=====================

The `PrettyShow` module is a small toolbox for pretty-printing in Julia.
It contains

 * a small set of functions to help produce formated printouts,
   notably using nested indentation,
 * an improved `show()` implementation for Julia abstract syntax trees 
   (AST:s), i e the `Expr` type.

AST pretty printing
-------------------

To use the PrettyShow's supplied `show()` for AST:s, just load the file
`prettyshow.jl`.

Example:

Formatting functions
--------------------

These create objects that produce the intended text and formatting when passed to `print`.

    print(io, defer_show(arg...))    ==>  show(io,  args)
    print(io, indent(args...))       ==>  # print args one step indented
    print(io, paren_block(args...))  ==>  print(io, '(', indent(args...), ')')

    print(io, comma_list(args...))   # e g:
    print(io, comma_list(x, y))      ==>  show(io, x); print(io, ", "); show(io, y)  # etc

There's also a few lower level functions that might come in handy occasionally:

    print(io, defer_print(args...))  ==>  print(io, args...)
    print(io, defer_io(f, args...))  ==>  f(io, args...)

Changes since v0.0
------------------
