# EspyInsideFunction.jl

*Extracting internal variables from a function.*

## Package features

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

A complete usage example can be found in [`EspyDemo.jl`](https://github.com/PhilippeMaincon/EspyInsideFunction.jl/blob/master/test/EspyDemo.jl)

## [Code markup](@id code-markup)

The following is an example of annotated code

```jldoctest EspyDemo; output = false
using EspyInsideFunction
struct Material
    E   :: Float64 
end
@espy function material(m::Material,ε)
    :σ = m.E*ε
    return σ
end
requestable(m::Material) = (σ=scalar,)


struct Element  
    L₀  :: Float64  
    A   :: Float64  
    ρg  :: Float64  
    mat :: Material 
end

const ngp = 1 

@espy function force(e::Element,ΔX)
    :w      = e.ρg*e.A*e.L₀
    :R      = [w/2,w/2]
    for igp = 1:ngp 
        :ε  = (ΔX[2]-ΔX[1])/e.L₀
        σ   = :material(e.mat,ε)  
        :T  = e.A*σ
        R   = +[T,-T]
    end
    return R
end
requestable(e::Element) = (w=scalar, R=(2,), gp= 
       forloop(ngp, (ε=scalar, T=scalar, material=requestable(e.mat) )))

# output
requestable (generic function with 2 methods)
```

The code of each function is prepended with `@espy`.  The name of variables of interest is annotated with a `:` ( for example `:ε` and `:σ`). These variable names
must appear on the left of an assignment, and can not be expressions that would otherwise be acceptable at the left of an assigment (writing `:a[igp] = ...` or `:a.b`will not work). Calls to sub-functions which are themselves annotated with @espy must be annotated with a `:` (as in `σ   = :material(e.mat,ε)`).

The last line of code (`requestable`) provides the obtainable intermediate results and their sizes.  See Section [Requestable](@ref requestable) for more details.

The macro `@espy` generates two versions of the code: first a clean code (for example)

```julia
function material(m::Material,ε)
    σ = m.E*ε
    return σ
end
```

and second, a version of the code to be used for result extraction.  Its interface is

```julia
function material(out,key,m::Material,εz)
    ...
end
```

The variables `out` and `key` are discussed in the following.

One can replace the `@espy` annotation with `@espydbg` to examine the code that is generated:

```julia
@espydbg function material(m::Material,ε)
    ...
end
```

The generated code itself contains macros.  To see the final code, one can type

```julia
@macroexpand @espy function material(m::Material,ε)
    ...
end
```

## [Requestable variables](@id requestable)

The programmer of the annotated function must provide a description of the requestable variables
and their size, as well as loops with their length, and sub-functions.  

```julia
requestable_from_element_ = (w=scalar, R=(2,), 
          gp=forloop(ngp, (ε=scalar, T=scalar, material=requestable(e.mat)) ) )
```


In at last code line of the code example in Section [Code markup](@ref code-markup), this is done as

```julia
requestable(e::Element) = (w=scalar, R=(2,), 
          gp=forloop(ngp, (ε=scalar, T=scalar, material=requestable(e.mat)) ) )
```

the choice being made made to provide this as a method associated to `Element`.

`forloop` and `scalar` are respectively a constructor and a constant exported by `EspyInsideFunction.jl`. The line will be interpreted by the function `makekey` (Section [Output access key](@ref makekey)) as stating that within the body of the espied function (here `residual`), there is a loop exactly of the form

```julia
for igp = 1:ngp
```

where the letters `gp` refer to the expression `gp=forloop(...)`. The currect version of `EspyInsideFunction.jl` is not flexible on this point: it must be a `for` loop (not a `while` loop or comprehension), the index variable must be `igp` (`gp` from `gp=forloop(...)` perfixed by `i`), and the upper bound must be `ngp`.

Where some of the variables are arrays, their size must be described, using `Tuples`:

```jldoctest; output = false
using EspyInsideFunction

ndof        = 16
nx          = 2
ngp         = 4
requestable = (X=(ndof),gp=forloop(ngp,(F=(nx,nx),material=(σ=(nx,nx),ε=(nx,nx)))))
# output
(X = 16, gp = forloop(4, (F = (2, 2), material = (σ = (2, 2), ε = (2, 2)))))
```

A development aim is to make it unnecessary to provide a list of requestable variable.  Until then, one should be meticulous in writing these lists, as any mistake leads to error message that are difficult to interpret. A drawback is that this will require requestable variables to have a size that is part of the type.

## [Creating a request](@id creating-a-request)

In order to extract results from a function annotated with `@espy` and `:`, the *user* of the function needs to define
a *request*.  For example

```jldoctest EspyDemo; output = false
request   = @request w,gp[].(ε,material.(σ))

# output
:((w, (gp[]).(ε, material.(σ))))
```

For the above request to be valid, the espied function (`force`, Section [Code markup](@ref code-markup)) must contain a variable `w` outside of any loop.  In the function there is a `for`-loop over variable `igp` taking values from `1` to `ngp`.  Within this loop, variable `ε` must appear (and be annotated, and defined as `requestable`).  Within the same loop, a function `material` must be called (and be annotated).  Within this function, `material`, variable `σ` must appear and be annotated, and defined as `requestable`.

## [Output access key](@id makekey)

An espy-key is a data structure containing indices into the `out` vector.  It is generated using `makekey` which
takes as inputs

1. A request (Section [Creating a request](@ref creating-a-request))
2. A description of the requestable variables (Section [Requestable variables](@ref requestable))

In the example provided in Section [Code markup](@ref code-markup), methods `force` and `requestable` are associated to the  type `Element`, so in this example we need to create an `Element` variable. 

```jldoctest EspyDemo; output = false
m          = Material(2.1e11)
e          = Element(1.,1e-4,8000*9.81,m)
key,nkey   = makekey(request,requestable(e))

# output
((w = 1, gp = NamedTuple{(:ε, :material), Tuple{Int64, NamedTuple{(:σ,), Tuple{Int64}}}}[(ε = 2, material = (σ = 3,))]), 3)

```

This produces `key` such that

```jldoctest EspyDemo; output = false
key.w                == 1 
key.gp[1].ε          == 2   
key.gp[1].material.σ == 3            
# output
true
```

and

```jldoctest EspyDemo; output = false
nkey == 3               
# output
true
```

where `nkey` is the largest index found in `key`.

If requestable variables are themselves arrays, `key` will contain arrays of indices:

```julia
using EspyInsideFunction
ngp         = 8
requestable = (gp=forloop(ngp,(material=(σ=(2,2),),)),)
request     = @request gp[].(material.(σ,),)
key,nkey    = makekey(request,requestable)
# Output
key.gp[8].material.σ == [29 31;30 32]
```

## Obtaining and accessing the outputs

The following example shows how the user of an espy-annotated function can obtain and access the `out` variable. Continuing with the example from Section [Code markup](@ref code-markup), we assume that we have the results `ΔX` for which we want to extract intermediate results.  Typicaly `ΔX` has been obtained in a numerical procedure that made use of the fast code generated from the annotated code.  For a simple example:

```jldoctest EspyDemo; output = false
nel  = 10
elementconnectivity = [[i,i+1] for i = 1:nel]
ΔX   = [1/2*e.ρg/m.E*((iel*e.L₀)^2-(nel*e.L₀)^2) for iel = 0:nel]

iel  = 4
igp  = 1
# output
1
```

In this case, the code extracts and agregates results from multiple calls to `force`:

```jldoctest EspyDemo; output = false
out = Matrix{Float64}(undef,nkey,nel)
for (iel,ec) ∈ enumerate(elementconnectivity)
    _ = force(@view(out[:,iel]),key, e,ΔX[ec])
end

σ = out[key.gp[igp].material.σ,iel]
ε = out[key.gp[igp].ε         ,iel] 

# output
1.3080000000000017e-6
```

`nkey` (obtained from `makekey`) is used to allocate `out`. `out` and `key` are passed to the exporting version of `force`. In this example where results are agregated to multiple calls to `force`, care must be taken not to pass `out[:,iel]`, but `@view(out[:,iel])` so that `force` can modify the content of the slice. 

In the two last lines of the code, `key` is used to access specific outputs. 

## Which variables types can be exported in this way?

`EspyInsideFunction` is made to store all results from a function inside a single array (e.g. `out`).  This allows to agregate large amounts of data, often produced in multiple calls to the same function, with only a single allocation.  

If `var` is a scalar, the code inserted by `@espy` to capture an intermediate result is of the form `out[key.var] = var`,
so `var` must convert to the `eltype` of `out`. 

If `var` is a container, `key.var` is an array of integers, and the inserted code is `out[key.var] .= var`.  This assigment works for array-like containers, including `Array`, `StaticArray` and `ntuple`. A normal `Array` can be used, but its size must be defined as a constant, in `requestable`.


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
