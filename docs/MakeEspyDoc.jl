using Documenter, EspyInsideFunction

push!(LOAD_PATH,"../src")
makedocs(sitename ="EspyInsideFunction documentation",
  #      modules = Lithe, # generate warning if docstrings from Lithe are forgotten
        format   = Documenter.HTML(prettyurls = false),
        pages = ["index.md"]
        )
