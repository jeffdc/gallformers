defmodule Gallformers.Repo do
  use Ecto.Repo,
    otp_app: :gallformers,
    adapter: Ecto.Adapters.Postgres
end
