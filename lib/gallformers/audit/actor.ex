defmodule Gallformers.Audit.Actor do
  @moduledoc """
  Who made an audited change.

  A `:user` actor is a person with a local `users.id` and the display name
  they had when the change was made, so history still reads correctly after a
  profile is renamed or deleted. A `:system` actor is a named process acting
  on its own account, such as a scheduled job or the data migration. There is
  no unknown or default actor: every audited write names one of these.
  """

  @enforce_keys [:type, :name]
  defstruct [:type, :id, :name]

  @type t ::
          %__MODULE__{type: :user, id: pos_integer(), name: String.t()}
          | %__MODULE__{type: :system, id: nil, name: String.t()}

  @doc "A person, by local user ID and the display name to record."
  @spec user(pos_integer(), String.t()) :: t()
  def user(id, name) when is_integer(id) and id > 0 and is_binary(name) do
    %__MODULE__{type: :user, id: id, name: present!(name)}
  end

  @doc ~s(A named system process, such as `"importer"` or `"catalog_migration"`.)
  @spec system(String.t()) :: t()
  def system(name) when is_binary(name) do
    %__MODULE__{type: :system, id: nil, name: present!(name)}
  end

  @doc false
  @spec to_meta(t()) :: map()
  def to_meta(%__MODULE__{type: :user, id: id, name: name}),
    do: %{"type" => "user", "id" => id, "name" => name}

  def to_meta(%__MODULE__{type: :system, name: name}),
    do: %{"type" => "system", "name" => name}

  defp present!(name) do
    case String.trim(name) do
      "" -> raise ArgumentError, "an audit actor needs a name"
      trimmed -> trimmed
    end
  end
end
