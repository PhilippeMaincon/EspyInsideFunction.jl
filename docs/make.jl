using Documenter, EspyInsideFunction

push!(LOAD_PATH,"../src")
makedocs(sitename ="EspyInsideFunction.jl",
        modules   = [EspyInsideFunction],
        format    = Documenter.HTML(prettyurls = false),
        pages     = ["index.md"]
        )

deploydocs(repo = "github.com/PhilippeMaincon/EspyInsideFunction.jl.git")

