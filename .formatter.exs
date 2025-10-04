[
  import_deps: [:phoenix],
  plugins: [TailwindFormatter, Phoenix.LiveView.HTMLFormatter, Quokka],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}"]
]
