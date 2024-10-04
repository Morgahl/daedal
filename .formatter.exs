[
  import_deps: [:ecto, :ecto_sql, :phoenix],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"],
  line_length: 120,
  plugins: [Phoenix.LiveView.HTMLFormatter],
  subdirectories: ["priv/*/migrations"]
]
