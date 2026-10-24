[
  import_deps: [:phoenix],
  locals_without_parens: [law: 2, laws: 2, termination_suffix: 2, cutoff: 1, prelude: 1],
  plugins: [Phoenix.LiveView.HTMLFormatter, Quokka],
  attribute_formatters: %{class: CanonicalTailwind},
  inputs: ["*.{heex,ex,exs}", "{bench,config,lib,test}/**/*.{heex,ex,exs}"]
]
