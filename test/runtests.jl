using Test,Printf#,Documenter
@printf "\nEspy test suite\n"

# Tests should be
# fast
# silent
# test high and low level components

@testset "EspyInsideFunction.jl package" begin
    include("TestEspy.jl")
    include("EspyDemo.jl")
    #doctest("EspyInsideFunction")
end
println(" ") # suppresses unwanted text output
