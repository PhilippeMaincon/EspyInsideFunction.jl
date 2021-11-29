# Espy
Provide functionality to extract intermediate results that are internal to a function - without cluttering the function.

[`Documentation`](https://github.com/PhilippeMaincon/Espy/blob/master/docs/build/index.html)

**Espy.jl** provides functionality to extract internal variables from a function.
"Internal" refers here to variables that are neither parameters nor outputs of the function.

The need for Espy arises when there is a difference between
- What the rest of the software needs to exchange with the function, in order to
  carry out the software's task.
and
- What the user may want to know about intermediate results internal to the function.

An example (and the original motivation for this package) is the extraction of results in
a finite element software. The code for an element type must include a function that takes in
the degrees of freedom (let us say, nodal displacements, in mechanics) and output the element's
contributions to the residuals (forces). A central motivation for the finite element
analysis could be to obtain intermediate results (stresses, strains).

Writing the function to explicitly export intermediate results has several disadvantages:
- This clutters the element code, the element API, and the rest of the software.
- This slows the solution process down (a little), as the element function is typicaly called many
  times before an acceptable result is obtained (Newton-Raphson iterations). Even
  tests  `if  converged ...` take time.

Espy's approach to this problem is to use metaprogramming to generate two versions of the
function's code
1. The fast version, that does nothing to save or export internediate results.  This is then
   used in e.g. the finite element solution process.
2. The exporting version.  In it receives additional parameters
   - a `request`, which specifies which internal results are wanted.
   - a vector `out`, to be filled with the requested results.
   - a `key` describing where in `out` to store which result.
   Typicaly, this version of the code is called once the computations have been completed, to extract
   the requested results.

[`Documentation`](https://github.com/PhilippeMaincon/Espy/blob/master/docs/build/index.html).
