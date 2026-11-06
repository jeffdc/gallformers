defmodule Gallformers.Curation.Key do
  @moduledoc """
  What a tray item is about on its subject, stored as text
  (`change_set_items.key`) so one item per key is a unique index.

    * a Fact about a Gall, as the Gall page keys it
      (`Gallformers.Catalog.gall_fact_key/0`): `{:inducer, taxon_id}`,
      `{:host, taxon_id}`, `{:trait, trait, value}`, `{:alias, name}`,
      `{:range, :exclude | :only, place_id}`, `{:occurrence, place_id}`;
    * an editorial field: `{:editorial, field}`.

  Stored as a JSON list (`["host", 7]`, `["trait", "season", "Spring"]`).
  """
  use Ecto.Type

  @type t ::
          {:inducer | :host, integer()}
          | {:trait, String.t(), String.t()}
          | {:alias, String.t()}
          | {:range, :exclude | :only, integer()}
          | {:occurrence, integer()}
          | {:editorial, atom()}

  @impl true
  def type, do: :string

  @impl true
  def cast(key) do
    if valid?(key), do: {:ok, key}, else: :error
  end

  @impl true
  def dump(key) do
    if valid?(key), do: {:ok, encode(key)}, else: :error
  end

  @impl true
  def load(text) when is_binary(text) do
    case Jason.decode(text) do
      {:ok, list} when is_list(list) -> decode(list)
      _ -> :error
    end
  end

  @doc "Whether `key` is a key an item may have."
  @spec valid?(term()) :: boolean()
  def valid?({role, id}) when role in [:inducer, :host, :occurrence], do: is_integer(id)
  def valid?({:trait, trait, value}), do: is_binary(trait) and is_binary(value)
  def valid?({:alias, name}), do: is_binary(name)
  def valid?({:range, adjustment, id}), do: adjustment in [:exclude, :only] and is_integer(id)
  def valid?({:editorial, field}), do: is_atom(field)
  def valid?(_key), do: false

  @doc "Whether `key` names a Fact (not an editorial field)."
  @spec fact?(t()) :: boolean()
  def fact?({:editorial, _field}), do: false
  def fact?(key), do: valid?(key)

  @doc "`key` as stored."
  @spec encode(t()) :: String.t()
  def encode(key), do: key |> Tuple.to_list() |> Enum.map(&part/1) |> Jason.encode!()

  defp part(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp part(other), do: other

  @roles %{"inducer" => :inducer, "host" => :host, "occurrence" => :occurrence}
  @adjustments %{"exclude" => :exclude, "only" => :only}

  defp decode([role, id]) when is_map_key(@roles, role) and is_integer(id),
    do: {:ok, {@roles[role], id}}

  defp decode(["trait", trait, value]), do: {:ok, {:trait, trait, value}}
  defp decode(["alias", name]), do: {:ok, {:alias, name}}

  defp decode(["range", adjustment, id]) when is_map_key(@adjustments, adjustment),
    do: {:ok, {:range, @adjustments[adjustment], id}}

  defp decode(["editorial", field]), do: {:ok, {:editorial, String.to_existing_atom(field)}}
  defp decode(_list), do: :error
end
