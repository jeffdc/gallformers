defmodule GallformersWeb.Admin.FormComponents do
  @moduledoc """
  Shared form components for admin forms.
  """

  use Phoenix.Component

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
  Displays warnings for potential duplicate taxa found while adding one in
  the taxonomy admin, each linking to the taxon's admin page:
  - `:name_match` — a taxon with this exact name already exists
  - `:alias_match` — the name is a synonym (`alias_type` `"scientific"`) or
    a common name (`"common"`) of a taxon
  - `:wcvp_id_match` — the same WCVP record is already linked to a plant

  ## Attributes

  * `:warnings` - Required. List of maps with `:taxon_id`, `:name`, and
    `:reason` keys (plus `:alias_type` for alias matches).
  """
  attr :warnings, :list, required: true

  def duplicate_host_warning(assigns) do
    ~H"""
    <.alert :if={@warnings != []} variant="warning">
      <:title>Possible duplicate</:title>
      <div :for={w <- @warnings}>
        {duplicate_reason_text(w)}
        <.link navigate={"/admin/taxonomy/#{w.taxon_id}"} class="underline font-medium">
          {w.name}
        </.link>
      </div>
    </.alert>
    """
  end

  defp duplicate_reason_text(%{reason: :name_match}),
    do: "A taxon with this exact name already exists: "

  defp duplicate_reason_text(%{reason: :alias_match, alias_type: type}),
    do: "This name is a #{alias_type_label(type)} of "

  defp duplicate_reason_text(%{reason: :wcvp_id_match}),
    do: "This WCVP record is already linked to "

  defp alias_type_label("common"), do: "common name"
  defp alias_type_label("scientific"), do: "scientific synonym"
  defp alias_type_label(other), do: other
end
