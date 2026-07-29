defmodule Pokerscars.Repo do
  use Ecto.Repo,
    otp_app: :pokerscars,
    adapter: Ecto.Adapters.Postgres
end
