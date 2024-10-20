[
  import_deps: [:ash, :ecto, :ecto_sql, :phoenix],
  inputs:
    Enum.flat_map(["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"], &Path.wildcard(&1, match_dot: true)) --
      ["lib/daedal/attribute.ex"],
  line_length: 140,
  plugins: [Phoenix.LiveView.HTMLFormatter],
  subdirectories: ["priv/*/migrations"],
  locals_without_parens: [
    # Daedal.Attribute
    primary_pub_static: 3,
    primary_pub_static: 4,
    req_pub_static: 3,
    req_pub_static: 4,

    # Orion LiveView
    live_orion: 1,
    live_orion: 2
  ]
]
