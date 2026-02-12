defmodule GallformersWeb.Admin.FormComponents do
  @moduledoc """
  Shared form components for admin forms.
  """

  use Phoenix.Component

  import GallformersWeb.CoreComponents, only: [icon: 1]
  import GallformersWeb.DataDisplayComponents, only: [taxon_name: 1]
  import GallformersWeb.UIComponents, only: [alert: 1]

  @doc """
  Renders the Cancel/Save button pair used by admin forms.

  ## Attributes

  * `:form_dirty` - Required. Whether the form has unsaved changes.
  * `:mode` - Required. Either `:new` or `:edit`.
  * `:save_label` - Optional. Label for the Save button when in edit mode. Defaults to "Save".
  * `:create_label` - Optional. Label for the Save button when in new mode. Defaults to "Create".

  ## Examples

      <.form_actions form_dirty={@form_dirty} mode={@mode} />
      <.form_actions form_dirty={@form_dirty} mode={@mode} save_label="Save Changes" create_label="Create Place" />
  """
  attr :form_dirty, :boolean, required: true
  attr :form_valid, :boolean, default: true
  attr :mode, :atom, required: true, values: [:new, :edit]
  attr :save_label, :string, default: "Save"
  attr :create_label, :string, default: "Create"

  def form_actions(assigns) do
    ~H"""
    <div class="flex gap-2">
      <button
        type="button"
        phx-click="request_cancel"
        class="gf-btn gf-btn-soft"
      >
        Cancel
      </button>
      <button
        type="submit"
        disabled={not @form_dirty or not @form_valid}
        class="gf-btn gf-btn-primary"
      >
        {if @mode == :new, do: @create_label, else: @save_label}
      </button>
    </div>
    """
  end

  @doc """
  Renders a warning when a species name matches an existing alias.

  Hidden when `collisions` is empty. Each collision is shown on its own line
  with a link to the species that owns the alias.

  ## Attributes

  * `:collisions` - Required. List of maps with `:species_id`, `:species_name`,
    `:taxoncode`, and `:alias_type` keys (from `Species.find_species_with_alias/1`).

  ## Examples

      <.alias_collision_warning collisions={@alias_collisions} />
  """
  attr :collisions, :list, required: true

  def alias_collision_warning(assigns) do
    ~H"""
    <.alert :if={@collisions != []} variant="warning">
      <:title>Alias collision</:title>
      <div :for={c <- @collisions}>
        This name is a {alias_type_label(c.alias_type)} of
        <.link
          navigate={species_path(c.taxoncode, c.species_id)}
          class="underline font-medium"
        >
          {c.species_name}
        </.link>
      </div>
    </.alert>
    """
  end

  defp alias_type_label("common"), do: "common name"
  defp alias_type_label("scientific"), do: "scientific synonym"
  defp alias_type_label("former_undescribed"), do: "former undescribed name"
  defp alias_type_label(other), do: other

  defp species_path("gall", id), do: "/gall/#{id}"
  defp species_path(_taxoncode, id), do: "/host/#{id}"

  @doc """
  Renders an alias editor table for editing species/host aliases.

  ## Attributes

  * `:aliases` - Required. List of alias maps with :id, :name, :type keys.
  * `:new_alias_name` - Required. Current value of the new alias name input.
  * `:new_alias_type` - Required. Currently selected alias type.

  ## Events

  The parent LiveView must handle these events:
  * `"update_new_alias"` - When name or type input changes
  * `"add_alias"` - When plus button clicked
  * `"remove_alias"` - When X button clicked (with `alias-id` value)

  ## Examples

      <.alias_editor
        aliases={@aliases}
        new_alias_name={@new_alias_name}
        new_alias_type={@new_alias_type}
      />
  """
  attr :aliases, :list, required: true
  attr :new_alias_name, :string, required: true
  attr :new_alias_type, :string, required: true

  def alias_editor(assigns) do
    ~H"""
    <div class="mb-3">
      <label class="gf-label">Aliases:</label>
      <div class="border border-gray-300 rounded">
        <table class="w-full text-sm">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-3 py-1.5 text-left font-medium text-gray-700">Name</th>
              <th class="px-3 py-1.5 text-left font-medium text-gray-700">Type</th>
              <th class="px-3 py-1.5 w-10"></th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200">
            <tr :for={a <- @aliases} class="hover:bg-gray-50">
              <td class="px-3 py-1.5"><.taxon_name name={a.name} /></td>
              <td class="px-3 py-1.5">{a.type}</td>
              <td class="px-3 py-1.5">
                <button
                  type="button"
                  phx-click="remove_alias"
                  phx-value-alias-id={a.id}
                  class="text-red-600 hover:text-red-800"
                >
                  <.icon name="ph-x" class="h-4 w-4" />
                </button>
              </td>
            </tr>
            <tr>
              <td class="px-3 py-1.5">
                <input
                  id="new-alias-input"
                  type="text"
                  value={@new_alias_name}
                  placeholder="New alias..."
                  phx-hook="InputEvent"
                  data-event="update_new_alias"
                  class="gf-input text-sm"
                />
              </td>
              <td class="px-3 py-1.5">
                <select
                  phx-change="update_new_alias"
                  phx-value-name={@new_alias_name}
                  class="gf-select text-sm"
                >
                  <option
                    :for={{label, value} <- alias_type_options()}
                    value={value}
                    selected={@new_alias_type == value}
                  >
                    {label}
                  </option>
                </select>
              </td>
              <td class="px-3 py-1.5">
                <button
                  type="button"
                  phx-click="add_alias"
                  class="text-green-600 hover:text-green-800"
                >
                  <.icon name="ph-plus" class="h-4 w-4" />
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp alias_type_options do
    [
      {"Common Name", "common"},
      {"Scientific Synonym", "scientific"},
      {"Former Undescribed Name", "former_undescribed"}
    ]
  end
end
