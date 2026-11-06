defmodule GallformersWeb.GallNameParts do
  @moduledoc """
  A Gall's name parts in a form (form label, descriptor, Host qualifier,
  name override), with the name they derive and the checks the old admin
  Gall page made (moved here unchanged, matter ec2c: "the same strict
  logic, just moved"): what the parts derive (or why they can't), the name
  shown, and whether another Gall already has it. Used by Edit mode on the
  Gall page (`GallformersWeb.GallLive.Editor`), which puts the parts in the
  curator's tray; applying them calls `Gallformers.Catalog.update_name_parts/3`.
  """
  alias Gallformers.Catalog
  alias Gallformers.Catalog.Gall
  alias Gallformers.Catalog.GallName
  alias Gallformers.Taxa

  @type qualifier :: %{id: integer(), name: String.t()} | nil
  @type preview :: %{
          derived: {:ok, String.t()} | {:error, atom()},
          shown: String.t(),
          taken?: boolean()
        }

  @doc "The Gall's Host qualifier as a picker holds it, or nil."
  @spec qualifier(Gall.t()) :: qualifier()
  def qualifier(%Gall{host_qualifier_taxon_id: nil}), do: nil

  def qualifier(%Gall{host_qualifier_taxon_id: id}),
    do: %{id: id, name: Taxa.accepted_name(id)}

  @doc "The form's params with the picked Host qualifier (nil when none)."
  @spec attrs(map(), qualifier()) :: map()
  def attrs(params, qualifier),
    do: Map.put(params, "host_qualifier_taxon_id", qualifier && qualifier.id)

  @doc """
  The name form (`as: :name`) for `params` and `qualifier`, with `action`
  (nil, or `:validate` to show errors), and its preview.
  """
  @spec form(Gall.t(), map(), qualifier(), atom() | nil) ::
          {Phoenix.HTML.Form.t(), preview()}
  def form(%Gall{} = gall, params, qualifier, action) do
    changeset = Catalog.change_name_parts(gall, attrs(params, qualifier))
    preview = changeset |> Ecto.Changeset.apply_changes() |> preview(gall)
    {Phoenix.Component.to_form(%{changeset | action: action}, as: :name), preview}
  end

  @doc """
  The name `pending`'s parts derive and the name it would show, and
  whether that is another Gall's.
  """
  @spec preview(Gall.t(), Gall.t()) :: preview()
  def preview(%Gall{} = pending, %Gall{} = gall) do
    derived = GallName.for_gall(pending)

    shown =
      case {pending.name_override, derived} do
        {override, _} when is_binary(override) -> override
        {_, {:ok, name}} -> name
        _ -> Gall.display_name(gall)
      end

    taken? =
      String.downcase(shown) != String.downcase(Gall.display_name(gall)) and
        Catalog.gall_name_taken?(shown)

    %{derived: derived, shown: shown, taken?: taken?}
  end

  @doc "The name's own errors on the form, as text."
  @spec errors(Phoenix.HTML.Form.t()) :: [String.t()]
  def errors(form),
    do: Enum.map(form[:name].errors, &GallformersWeb.CoreComponents.translate_error/1)

  @doc "Why the parts derive no name."
  @spec derive_error(atom()) :: String.t()
  def derive_error(:several_inducers), do: "its current Sources disagree on its Inducer"
  def derive_error(:no_base), do: "an Inducer above species needs a descriptor"
  def derive_error(:no_family), do: "its Inducer is above family"
  def derive_error(:no_genus), do: "its Inducer is not in a genus"
end
