[
  import_deps: [:phoenix],
  plugins: [Phoenix.LiveView.HTMLFormatter, Quokka],
  attribute_formatters: %{class: CanonicalTailwind},
  inputs: ["*.{heex,ex,exs}", "{bench,config,lib,test}/**/*.{heex,ex,exs}"]
]
