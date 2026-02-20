defmodule Gallformers.Repo.WCVP do
  @moduledoc """
  Read-only Ecto repo for querying the WCVP SQLite database.

  This is a secondary database containing filtered WCVP plant data
  (Western Hemisphere accepted species). It is NOT managed by Ecto migrations —
  the database file is built externally and downloaded from S3.
  """
  use Ecto.Repo,
    otp_app: :gallformers,
    adapter: Ecto.Adapters.SQLite3
end
