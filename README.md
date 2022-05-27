# EspyInsideFunction

This package provides functionality to extract internal variables from a function.
"Internal" refers here to variables that are neither parameters nor outputs of the function.

The need for `EspyInsideFunction` arises when there is a difference between

- what the rest of the software needs to exchange with the function, in order to
  carry out the software's task, and
- what the user may want to know about intermediate results internal to the function.

An example is the extraction of results in
a finite element software. The code for an element type must include a function that takes in
the degrees of freedom (in mechanics: nodel displacements) and output the element's
contributions to the residuals (forces). The user is interested in intermediate results such as stresses and strains.

Writing the function to explicitly export intermediate results clutters the element code, the element API, and the rest of the software.

`EspyInsideFunction`'s approach to this problem is to use metaprogramming to generate two versions of the
function's code

1. The fast version, that does nothing to save or export internediate results.  This is then
   used in e.g. the finite element solution process.
2. The exporting version.  In it receives additional parameters
   - a vector `out`, to be filled with the requested results.
   - a `key` describing which internal results are wanted and where in `out` to store which result.
   Typicaly, this version of the code is called once the computations have been completed (using the fast version), to extract
   the requested results.

See the [`documentation`](https://philippemaincon.github.io/EspyInsideFunction.jl/)
A complete usage example can be found in [`EspyDemo.jl`](https://github.com/PhilippeMaincon/EspyInsideFunction.jl/blob/master/test/EspyDemo.jl)