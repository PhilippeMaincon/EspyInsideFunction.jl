using Test,Documenter,EspyInsideFunction
println("\nEspy test suite\n")

@testset "EspyInsideFunction.jl package" begin
    include("TestEspy.jl")
    include("EspyDemo.jl")
    doctest(EspyInsideFunction)
end
;