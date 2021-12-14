# EspyInsideFunction.jl: result extraction
## What does EspyInsideFunction do?
**EspyInsideFunction.jl** provides functionality to extract internal variables from a function.
"Internal" refers here to variables that are neither parameters nor outputs of the function.



The need for EspyInsideFunction arises when there is a difference between
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

EspyInsideFunction's approach to this problem is to use metaprogramming to generate two versions of the
function's code
1. The fast version, that does nothing to save or export internediate results.  This is then
   used in e.g. the finite element solution process.
2. The exporting version.  In it receives additional parameters
   - a `request`, which specifies which internal results are wanted.
   - a vector `out`, to be filled with the requested results.
   - a `key` describing where in `out` to store which result.
   Typicaly, this version of the code is called once the computations have been completed, to extract
   the requested results.



## Code markup
The following is an example of annotated code
```julia
1   using EspyInsideFunction
2   const ngp=2
4   @espy function residual(x,y)
3       r = 0
5       for igp=1:ngp
6           :z = x[igp]+y[igp]
7           :s  = :material(z)
8           r += s
9       end
10      return r
11  end
12  @espy function material(z)
13      :a = z+1
14      :b = a*z
15      return b
16  end
17  requestable = (gp=forloop(ngp,(z=scalar,s=scalar,material=(a=scalar,b=scalar))),)
```
The code of each function is prepended with `@espy` (lines 2 and 12).  The name of variables of interest (lines 6, 7 13 and 14) is annotated with a `:`. These variable names
must appear on the left hand side of an equation, and can not be array references (writing `:a[igp] = ...` will not work). Call to functions which may contain variables of interest must be annotated with a `:` (line 7).

The macro `@espy` will generate two versions of the code: first a clean code (for example)
```julia
1   function material(z)
2       a = z+1
3       b = a*z
4       return b
5   end
```
and second, a version of the code to be used for result extraction.  The function headers will look like:
```julia
function residual(out,req,x,y)
    ...
end
```
The variables `out` (for output) and `req` (for request) are discussed in the following.

One can modify the code annotation to examine the code that is generated:
```julia
@espydbg true function residual(x,y)
    ...
end
```

## Creating a request

In order to extract results from a function annotated with `@espy` and `:`, the *user* of the function needs to define
a *request*.  For example

```julia
using EspyInsideFunction
req = @request gp[].(s,z,material.(a,b))
```

This states that in the relevant function (`residual`), there is a `for`-loop over variable `igp` taking values from `1` to `ngp`.  Within this loop, variables `s` and `z` will appear (and be annotated) and are requested.  Within the same loop, a function `material` is called (and is annotated).  Within this function, `material`, variables `a` and `b` are requested.

A slightly more complex example is

```julia
using EspyInsideFunction
req = @request X,gp[].(F,material.(σ,ε))
```

The espied function will contain a variable `X`, a `for`-loop within which a variable `F` will appear, as well as a call to the function `material` within which variables `σ` and `ε` appear.

## Requestable variables

The *programmer* of the annotated function must provide a description of the requestable variables
and their size, as well as loops with their length, and sub-functions.

Code line 17 in the first example above provides an example (copied here):

```julia
requestable = (gp=forloop(ngp,(z=scalar,s=scalar,material=(a=scalar,b=scalar))),)
```

Where some of the variables are arrays, their size must be described:

```julia
ndof        = ...
nx          = ...
requestable = (X=[ndof],gp=forloop(ngp,(F=[nx,nx],material=(σ=[nx,nx],ε=[nx,nx]))),)
```

## Output access key

An espy-key is a data structure with a shape as described in `@request`, containing indices into the `out` vector
returned by the code generated by `@espy`.

Generating this requires

1. A request
2. A description of the requestable variables

```julia
using EspyInsideFunction
requestable = (gp=forloop(ngp,(z=scalar,s=scalar,material=(a=scalar,b=scalar))),)
request     = @request gp[].(s,z,material.(a,b))
key,nkey    = makekey(request,requestable)
```

This generates `key`, such that in this case

```julia
key.gp[1].s          == 1
key.gp[1].z          == 2
key.gp[1].material.a == 3
key.gp[1].material.b == 4
key.gp[2].s          == 5
key.gp[2].z          == 6
key.gp[2].material.a == 7
key.gp[2].material.b == 8
```

`nkey` is the highest index that appears in `key` (the length of the vector `out`).  In this example
`nkey==8`.

Where requestable variables are themselves array, the key will contain arrays of indices:

```julia
key.gp[8].material.σ == [125 126;128 129]
```

## Obtaining and accessing the outputs

The following example shows how the user of an espy-annotated function can obtain and access
the `out` variable.

```julia
1   using EspyInsideFunction
2   ex       = @request gp[].(s,z,material.(a,b))
3   key,nkey = makekey(ex)
4   out      = Vector(undef,nkey)
5   r        = residual(out,key,x,y)
6   a        = out[key.gp[1].material.a]
7   s        = out[key.gp[1].s         ]
```

Line 2 creates an expression describing the request.  Line 3 creates the request key, as well as the number of values in the request. Line 4 allocates an array for the outputs, using `nkey`. In line 5, the `residual` code generated by `@espy` is called.  In lines 6 and 7, `key` is used to access specific outputs.

## Outputs from multiple calls

Typicaly, a function like `residual` is called multiple times.  In a FEM setting, we could be interested in the values 'for each element' and 'for each time step'. Considering that all elements are of the same type (and thus that the dimensions `ndim`, `nnod` and `ngp` are the same for all elements), then `key` and `nkey` are the same for all elements. The code then becomes

```julia
...
1   using EspyInsideFunction
2   ex        = @request gp[].(s,z,material.(a,b))
3   key,nkey  = makekey(ex)
4   out       = Vector(undef,nkey,nel,nstep)
5   iel,istep = ...
6   r         = residual(@view(out[:,iel,istep],key,x,y)
7   a         = out[key.gp[1].material.a,iel,istep]
8   s         = out[key.gp[1].s         ,iel,istep]
```

Thus, a large quantity of results can be stored in one large array, avoiding to clutter the memory-heap many smaller array.

# Reference
```@meta
CurrentModule = EspyInsideFunction
```
```@docs
@request
makekey
@espy
@espydbg
forloop
scalar
```
