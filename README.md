julia-prettyshow: pretty-printing in Julia
==========================================

This module provides simple pretty printing facilities.   
So far, there is some base functionality for indentation etc,
and a `pshow` (pretty `show`) implementation for julia AST:s.

Usage
-----

Use `pshow`,`pprint`, and `pprintln` more or less as `show`,`print`, and `println`.   
You can also supply a pretty printing context as a first argument:

    pprint(io::PrettyIO, x)

`pprint` expands vectors to print each argument; the nesting level of an argument gives the indentation. I e

    fname = "unnecessarily_long_function_name"
    pprintln("for ", {
            "i=1:n", "\nfor ", {
                "j=1:m", "\n",
                "X[",{"i, j"}, "] = A[",{"$fname(i)"},"] * B[",{"$fname(j)"},"]"
            }, "\nend"
        }, "\nend")

prints

    for i=1:n
        for j=1:m
            X[i, j] = A[unnecessarily_long_function_name(i)] * B[
                unnecessarily_long_function_name(j)]
        end
    end

By anotating the text with the nesting structure, `pprint` can do the right thing at line breaks, even within the indexing `[$fname(j)]`.
`pprint` also tries not to break individual strings across lines.

Implenting for new types
------------------------
To implement pretty-printing for a type `T`, it should be enough to overload

    pshow(io::PrettyIO, t::T)

This should output to `io` using `pshow/pprint/pprintln`.

There is also a newline callback associated with each nested `PrettyIO` context, (see the code) which I've used in another project to implement pretty printing of tree views:

    A=CallNode(
     +- .op=SymNode(:+, :call), 
     +- .arg1=CallNode(
     |   +- .op=SymNode(:.*, :call), 
     |   +- .arg1=SymNode(:B, :input), 
     |   \- .arg2=SymNode(:C, :input)), 
     \- .arg2=SymNode(:D, :input))
    X=KnotNode(
     +- .pre=A, 
     \- .value=CallNode(
         +- .op=SymNode(:+, :call), 
         +- .arg1=A, 
         \- .arg2=SymNode(:C, :input)))
    assign1=AssignNode(
     +- .lhs=RefNode(
     |   +- .ref=SymNode(:dest1, :output), 
     |   \- .ind=SymNode(:..., :symbol)), 
     \- .rhs=A)
    assign2=AssignNode(
     +- .lhs=RefNode(
     |   +- .ref=SymNode(:dest2, :output), 
     |   \- .ind=SymNode(:..., :symbol)), 
     \= .rhs=X, .dep=assign1)
    sink=TupleNode(
     \= .arg1=assign2, .arg2=X)
