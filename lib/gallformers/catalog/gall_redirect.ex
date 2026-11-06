defmodule Gallformers.Catalog.GallRedirect do
  @moduledoc """
  A Gall merged into another (matter `ec2c`, "What a Gall merge does"): its
  old ID (`from_gall_id`) and Gallformers code (`from_code`) now name
  `gall_id`, so iNat links and outside references keep working
  (`Gallformers.Catalog.gall_redirect/1`). It goes with the Gall it points
  to; a merge of that Gall re-points it.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{
          from_gall_id: integer() | nil,
          from_code: String.t() | nil,
          gall_id: integer() | nil,
          inserted_at: DateTime.t() | nil
        }

  @primary_key {:from_gall_id, :id, autogenerate: false}
  schema "gall_redirects" do
    field :from_code, :string
    field :gall_id, :integer

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
