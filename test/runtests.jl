using Test,Printf
@printf "\nEspy test suite\n"

# Tests should be
# fast
# silent
# test high and low level components

@testset "Espy package" begin
    include("TestEspy.jl")
end
println(" ") # suppresses unwanted text output
