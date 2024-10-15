[
  import_deps: [:ecto, :ecto_sql, :phoenix],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"],
  line_length: 140,
  plugins: [Phoenix.LiveView.HTMLFormatter],
  subdirectories: ["priv/*/migrations"],
  locals_without_parens: [live_orion: 1, live_orion: 2]
]
