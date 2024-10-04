defmodule Daedal.Repo do
  use Ecto.Repo,
    otp_app: :daedal,
    adapter: Ecto.Adapters.Postgres
end
