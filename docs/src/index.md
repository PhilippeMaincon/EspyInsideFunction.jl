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

Writing the function to explicitly export intermediate results clutters the element code, the element API, and the rest of the software.

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

## Code markup {#code-markup}
The following is an example of annotated code
```julia
using EspyInsideFunction
const ngp=2
@espy function residual(x,y)
    r = 0
    for igp=1:ngp
      :z = x[igp]+y[igp]
      :s  = :material(z)
      r += s
    end
    return r
end
@espy function material(z)
    :a = z+1
    :b = a*z
    return b
end
requestable = (gp=forloop(ngp,(z=scalar,s=scalar,material=(a=scalar,b=scalar))),)
```
The code of each function is prepended with `@espy`.  The name of variables of interest is annotated with a `:` (`:z`,`:s` and so forth). These variable names
must appear on the left hand side of an equation, and can not be array references (writing `:a[igp] = ...` will not work). Call to functions which may contain variables of interest must be annotated with a `:` (as in `:s  = :material(z)`).

The last line of code creates a variable `requestable`, which lists the variables of interest and their sizes.  See Section [Requestable]{#requestable} for more details.

The macro `@espy` generates two versions of the code: first a clean code (for example)
```julia
function material(z)
    a = z+1
    b = a*z
    return b
end
```
and second, a version of the code to be used for result extraction.  The function headers will look like:
```julia
function material(out,req,z)
    ...
end
```
The variables `out` (for output) and `req` (for request) are discussed in the following.

One can modify the code annotation to examine the code that is generated:
```julia
@espydbg function material(z)
    ...
end
```
The generated code itself contains macros.  To see the final code, one can type
```julia
@macroexpand @espy function material(z)
    ...
end
```

## Requestable variables {#requestable}

The *programmer* of the annotated function must provide a description of the requestable variables
and their size, as well as loops with their length, and sub-functions.

The last code line in the code example in Section [Code markup]{#code-markup} is

```julia
requestable = (gp=forloop(ngp,(z=scalar,s=scalar,material=(a=scalar,b=scalar))),)
```

where `forloop` and `scalar` are respectively a constructor and a constant exported by `EspyInsideFunction.jl`. The line will be interpreted by the function `makekey` (Section [Output access key]{#makekey}) as stating that within the body of the espied function (here `residual`), there is a loop exactly of the form
```julia
for igp = 1:ngp
```
where `gp` is from the expression `gp=forloop(...`.  `EspyInsideFunction.jl` is not flexible on this point and requires a `for` loop, not a `while` loop or comprehension.

Where some of the variables are arrays, their size must be described:

```jldoctest; output = false
using EspyInsideFunction

ndof        = 16
nx          = 2
ngp         = 4
requestable = (X=(ndof),gp=forloop(ngp,(F=(nx,nx),material=(σ=(nx,nx),ε=(nx,nx)))))
# output
(X=(16),gp=forloop(4,(F=(2,2),material=(σ=(2,2),ε=(2,2)))))
```

A development aim is to make it unnecessary to provide a list of requestable variable.  Until then, one should be meticulous in writing this, as any mistake leads to error message that are difficult to interpret.

## Which variables can be exported in this way?
`EspyInsideFunction` is made to store all results from a function inside a single array (e.g. `out`).  This allows to agregate large amounts of data with only a single allocation.  The code inserted by `@espy` to capture an intermediate result is of the form
```julia
out[key.var] .= var
```
if the variable of interest `var` is an `Array`, of `FLoat64`and
```julia
out[key.var] = var
```
if `var` is a `Float64`.  `key.var` is an integer or an array of integers (generated by `makekey`). The user has allocated `out`, typicaly as an array of `Float64`. For `EspyInsideFunction` to work Julia must be able to map `var` onto a full array, and to convert the elements of `var`, to `Float64`.

This works, for example, with `var` being a `Float64`, a `StaticArray` or an `ntuple`.

## Creating a request

In order to extract results from a function annotated with `@espy` and `:`, the *user* of the function needs to define
a *request*.  For example
```julia
req = @request gp[].(s,z,material.(a,b))
```

This request is based on the assumption that in the relevant function (`residual`), there is a `for`-loop over variable `igp` taking values from `1` to `ngp`.  Within this loop, variables `s` and `z` must appear (and be annotated).  Within the same loop, a function `material` must be called (and be annotated).  Within this function, `material`, variables `a` and `b` must appear and be annotated.

A slightly more complex example (not valid with the above code) is
```julia
req = @request X,gp[].(F,material.(σ,ε))
```
The espied function must contain a variable `X` outside of any loop.  It must contain a `for`-loop within which a variable `F` will appear, as well as a call to the function `material` within which variables `σ` and `ε` appear.

## Output access key {#makekey}

An espy-key is a data structure with a shape as described in `@request`, containing indices into the `out` vector
returned by the code generated by `@espy`.

Generating this requires

1. A request
2. A description of the requestable variables

```julia
using EspyInsideFunction
ngp         = 2
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
using EspyInsideFunction
ngp         = 8
requestable = (gp=forloop(ngp,(material=(σ=(2,2),),)),)
request     = @request gp[].(material.(σ,),)
key,nkey    = makekey(request,requestable)

key.gp[8].material.σ == [29 31;30 32]
```

## Obtaining and accessing the outputs

The following example shows how the user of an espy-annotated function can obtain and access the `out` variable.  The example is to be executed after the first code example in Section [Code markup]{#code-markup}.

```julia
x,y      = [1.,2.],[3.,4.]
req      = @request gp[].(s,z,material.(a,b))
key,nkey = makekey(req,requestable)
out      = Vector(undef,nkey)
r        = residual(out,key,x,y)
a        = out[key.gp[1].material.a]
s        = out[key.gp[1].s         ]
```

The macro invoquation `@request` creates an expression describing the requested outputs.  The call to `makekey` creates the request key, as well as the number of values in the request. `nkey` is used to allocate an array for the outputs. The spying version of `residual`.  In lines the two last lines of the code, `key` is used to access specific outputs.

## Outputs from multiple calls

Typicaly, a function like `residual` is called multiple times.  In a FEM setting, we could be interested in the values 'for each element' and 'for each time step'. Considering that all elements are of the same type (and thus that the dimensions `ndim`, `nnod` and `ngp` are the same for all elements), then `key` and `nkey` are the same for all elements. The code then becomes

```julia
...
using EspyInsideFunction
ex        = @request gp[].(s,z,material.(a,b))
key,nkey  = makekey(ex)
out       = Vector(undef,nkey,nel,nstep)
iel,istep = ...
r         = residual(@view(out[:,iel,istep],key,x,y)
a         = out[key.gp[1].material.a,iel,istep]
s         = out[key.gp[1].s         ,iel,istep]
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
