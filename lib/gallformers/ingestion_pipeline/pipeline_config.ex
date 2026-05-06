defmodule Gallformers.IngestionPipeline.PipelineConfig do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          config: map() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "pipeline_configs" do
    field :name, :string
    field :config, :map

    timestamps(type: :utc_datetime)
  end

  @required_fields [:name, :config]

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(pipeline_config, attrs) do
    pipeline_config
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> update_change(:name, &String.trim/1)
    |> validate_change(:name, fn :name, name ->
      if String.trim(name) == "", do: [name: "can't be blank"], else: []
    end)
    |> unique_constraint(:name)
  end
end
