defmodule GallformersWeb.Admin.TaxonomyLive.Form do
  @moduledoc """
  Admin form for creating and editing taxonomy entries.

  Includes a hierarchical parent selector for setting up the taxonomy tree.
  """
  use GallformersWeb, :live_view
  use GallformersWeb.Admin.FormHelpers, crud_helpers: true, include_delete: false

  import GallformersWeb.Admin.FormComponents, only: [form_actions: 1]
  import GallformersWeb.FormComponents, only: [cascade_delete_modal: 1]

  alias Gallformers.Taxonomy
  alias Phoenix.HTML.Form, as: HtmlForm

  # Family types - these categorize what kind of organism a family contains.
  # "Plant" indicates a host family; all others are gall-former families.
  @gall_family_types ~w(Aphid Bacteria Beetle Fly Fungus Midge Mite Moth Nematode Oomycete Psyllid Sawfly Scale Thrips Unknown Virus Wasp) ++
                       ["Plant (gall forming)", "True Bug"]
  @host_family_types ~w(Plant)

  # Required callbacks for FormHelpers
  @impl GallformersWeb.Admin.FormHelpers
  def entity_key, do: :taxonomy
  @impl GallformersWeb.Admin.FormHelpers
  def entity_struct, do: Taxonomy.Taxonomy
  @impl GallformersWeb.Admin.FormHelpers
  def list_path, do: ~p"/admin/taxonomy"
  @impl GallformersWeb.Admin.FormHelpers
  def load_entity(id), do: Taxonomy.get_taxonomy!(id)
  @impl GallformersWeb.Admin.FormHelpers
  def change_entity(entity, params \\ %{}), do: Taxonomy.change_taxonomy(entity, params)
  @impl GallformersWeb.Admin.FormHelpers
  def create_entity(params), do: Taxonomy.create_taxonomy(params)
  @impl GallformersWeb.Admin.FormHelpers
  def update_entity(entity, params), do: Taxonomy.update_taxonomy(entity, params)

  # Note: delete_entity/1 callback not needed - we use include_delete: false
  # and handle delete in handle_event("delete", ...) below

  @impl true
  def mount(_params, session, socket) do
    {:ok, init_admin_form(socket, session)}
  end

  def close_form(socket) do
    push_navigate(socket, to: list_path())
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  # Custom apply_action to handle parent_options
  defp apply_action(socket, :new, _params) do
    apply_new_action(socket, parent_options: load_parent_options(nil))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket = apply_edit_action(socket, id)
    # Add parent_options based on loaded entity's type
    taxonomy = socket.assigns[:taxonomy]

    if taxonomy do
      socket
      |> assign(:parent_options, load_parent_options(taxonomy.type))
      |> assign(:show_delete_modal, false)
      |> assign(:deletion_impact, nil)
      |> assign(:delete_confirmation, "")
    else
      socket
    end
  end

  defp load_parent_options(type) when type in [nil, ""] do
    # No type selected yet — don't show parent options
    []
  end

  defp load_parent_options("family"), do: []

  defp load_parent_options("genus") do
    Taxonomy.list_families_for_select()
  end

  defp load_parent_options("section") do
    Taxonomy.list_genera_for_select(:plant)
    |> Enum.map(fn g -> {g.name, g.id} end)
  end

  # Custom validate handler to update parent_options when type changes
  @impl true
  def handle_event("validate", %{"taxonomy" => params}, socket) do
    # Clear name and parent when type changes
    prev_type = HtmlForm.input_value(socket.assigns.form, :type)

    params =
      if params["type"] != prev_type do
        Map.merge(params, %{"name" => "", "parent_id" => ""})
      else
        params
      end

    changeset =
      socket.assigns.taxonomy
      |> Taxonomy.change_taxonomy(params)
      |> validate_unique_name_parent(socket.assigns.taxonomy)
      |> Map.put(:action, :validate)

    parent_options = load_parent_options(params["type"])

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:parent_options, parent_options)
     |> mark_dirty()}
  end

  # Catch-all for validate events that don't match the expected form structure
  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save", %{"taxonomy" => taxonomy_params} = params, socket) do
    changeset =
      socket.assigns.taxonomy
      |> Taxonomy.change_taxonomy(taxonomy_params)
      |> validate_unique_name_parent(socket.assigns.taxonomy)

    if changeset.valid? do
      handle_save(params, socket)
    else
      changeset = Map.put(changeset, :action, :validate)
      {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("delete", _params, socket) do
    # Show cascade delete confirmation modal with impact assessment
    taxonomy = socket.assigns.taxonomy
    impact = Taxonomy.get_deletion_impact(taxonomy)

    {:noreply,
     socket
     |> assign(:deletion_impact, impact)
     |> assign(:show_delete_modal, true)
     |> assign(:delete_confirmation, "")}
  end

  @impl true
  def handle_event("update_delete_confirmation", %{"value" => value}, socket) do
    {:noreply, assign(socket, :delete_confirmation, value)}
  end

  @impl true
  def handle_event("confirm_cascade_delete", %{"confirmation" => confirmation}, socket) do
    taxonomy = socket.assigns.taxonomy
    expected_name = taxonomy.name

    if String.trim(confirmation) == expected_name do
      case Taxonomy.delete_taxonomy_cascade(taxonomy) do
        {:ok, impact} ->
          message = build_delete_success_message(taxonomy, impact)

          {:noreply,
           socket
           |> put_flash(:info, message)
           |> push_navigate(to: ~p"/admin/taxonomy")}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:show_delete_modal, false)
           |> put_flash(:error, "Delete failed: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Name does not match. Please type the exact name.")}
    end
  end

  @impl true
  def handle_event("cancel_cascade_delete", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_delete_modal, false)
     |> assign(:deletion_impact, nil)
     |> assign(:delete_confirmation, "")}
  end

  @impl true
  def handle_event(event, params, socket)
      when event in ~w(request_cancel cancel_discard confirm_discard) do
    handle_form_event(event, params, socket)
  end

  # Handle impact map (for family/genus cascade delete)
  defp build_delete_success_message(
         taxonomy,
         %{genera_count: _, sections_count: _, species_count: _} = impact
       ) do
    base = "Deleted #{taxonomy.type} \"#{taxonomy.name}\""

    details =
      [
        if(impact.genera_count > 0, do: "#{impact.genera_count} genera"),
        if(impact.sections_count > 0, do: "#{impact.sections_count} sections"),
        if(impact.species_count > 0, do: "#{impact.species_count} species")
      ]
      |> Enum.filter(& &1)

    if details == [] do
      base
    else
      base <> " and #{Enum.join(details, ", ")}"
    end
  end

  # Handle simple taxonomy struct (for section delete - no cascade)
  defp build_delete_success_message(_taxonomy, %Taxonomy.Taxonomy{} = deleted) do
    "Deleted #{deleted.type} \"#{deleted.name}\""
  end

  defp taxonomy_public_url(%{type: "family", id: id}), do: ~p"/family/#{id}"
  defp taxonomy_public_url(%{type: "genus", id: id}), do: ~p"/genus/#{id}"
  defp taxonomy_public_url(%{type: "section", id: id}), do: ~p"/section/#{id}"
  defp taxonomy_public_url(_), do: nil

  defp validate_unique_name_parent(changeset, taxonomy) do
    name = Ecto.Changeset.get_field(changeset, :name)
    parent_id = Ecto.Changeset.get_field(changeset, :parent_id)

    if name && Taxonomy.Tree.name_parent_exists?(name, parent_id, taxonomy.id) do
      Ecto.Changeset.add_error(changeset, :name, "already exists for this parent")
    else
      changeset
    end
  end

  defp family_type_options do
    gall_options = Enum.map(@gall_family_types, &{&1, &1})
    host_options = Enum.map(@host_family_types, &{"#{&1} (host)", &1})

    (gall_options ++ host_options)
    |> Enum.sort_by(fn {label, _value} -> String.downcase(label) end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin
      flash={@flash}
      current_user={@current_user}
      page_title={@page_title}
      public_url={if @mode == :edit, do: taxonomy_public_url(@taxonomy)}
    >
      <Layouts.admin_edit_layout
        back_path={~p"/admin/taxonomy"}
        back_label="Back to Taxonomy"
        title={if @mode == :new, do: "Create New Taxonomy Entry", else: "Edit Taxonomy Entry"}
      >
        <:intro>
          Taxonomy entries define the hierarchical classification of species:
          Family → Genus → Section (optional). Species are linked to genera.
        </:intro>

        <div :if={@mode == :edit and @taxonomy.type == "section"} class="mb-4">
          <.link
            href={~p"/admin/section/#{@taxonomy.id}"}
            class="inline-flex items-center gap-1.5 text-sm text-gf-maroon hover:text-gf-autumn"
          >
            <.icon name="ph-arrow-right" class="h-4 w-4" /> Manage species in this section
          </.link>
        </div>

        <% type_selected = HtmlForm.input_value(@form, :type) not in [nil, ""] %>
        <.form for={@form} id="taxonomy-form" phx-change="validate" phx-submit="save">
          <div class="mb-3">
            <.input
              field={@form[:type]}
              schema={Taxonomy.Taxonomy}
              type="select"
              label="Type"
              prompt="Select type"
              options={[{"Family", "family"}, {"Genus", "genus"}, {"Section", "section"}]}
            />
          </div>

          <div class="grid grid-cols-2 gap-4 mb-3">
            <div>
              <.input
                field={@form[:name]}
                schema={Taxonomy.Taxonomy}
                type="text"
                label="Name"
                placeholder="Enter taxonomy name"
                disabled={!type_selected}
              />
            </div>
            <div>
              <%= if HtmlForm.input_value(@form, :type) == "family" do %>
                <.input
                  field={@form[:description]}
                  type="select"
                  label="Family Type:"
                  prompt="Select family type"
                  options={family_type_options()}
                  required={true}
                />
                <p class="mt-1 text-xs text-gray-500">
                  Select "Plant" for host families; all others are gall-former families.
                </p>
              <% else %>
                <.input
                  field={@form[:description]}
                  type="text"
                  label="Description:"
                  placeholder="Common name or description"
                  disabled={!type_selected}
                />
                <p class="mt-1 text-xs text-gray-500">
                  Optional common name (e.g., "oaks" for Quercus)
                </p>
              <% end %>
            </div>
          </div>

          <div class="mb-3">
            <%= if @parent_options != [] do %>
              <.input
                field={@form[:parent_id]}
                type="select"
                label="Parent:"
                prompt={
                  if HtmlForm.input_value(@form, :type) == "section",
                    do: "Select a genus",
                    else: "Select a family"
                }
                options={@parent_options}
                required={true}
              />
              <p class="mt-1 text-xs text-gray-500">
                Genera belong to families. Sections belong to genera.
              </p>
            <% else %>
              <label class="gf-label">Parent:</label>
              <p class="text-sm text-gray-500 italic px-3 py-2">
                <%= if HtmlForm.input_value(@form, :type) == "family" do %>
                  Families are top-level entries and have no parent.
                <% else %>
                  Select a type to see available parent options.
                <% end %>
              </p>
            <% end %>
          </div>

          <div class="flex justify-between pt-4 border-t border-gray-200">
            <div>
              <button
                :if={@mode == :edit}
                type="button"
                phx-click="delete"
                class="gf-btn gf-btn-danger"
              >
                Delete
              </button>
            </div>
            <.form_actions form_dirty={@form_dirty} form_valid={@form.source.valid?} mode={@mode} />
          </div>
        </.form>

        <.discard_confirm_modal show={@show_discard_confirm} />

        <%!-- Cascade Delete Confirmation Modal --%>
        <.cascade_delete_modal
          :if={@mode == :edit}
          show={@show_delete_modal}
          impact={@deletion_impact}
          confirmation_value={@delete_confirmation}
        />

        <%!-- Help Card --%>
        <div class="mt-6 bg-blue-50 border border-blue-200 rounded-lg p-4">
          <h3 class="text-sm font-medium text-blue-800 mb-2">
            <.icon name="ph-info" class="h-4 w-4 inline mr-1" /> About Taxonomy Hierarchy
          </h3>
          <ul class="text-sm text-blue-700 space-y-1">
            <li>
              <strong>Families</strong> are the top-level groupings (e.g., Cynipidae, Fagaceae)
            </li>
            <li><strong>Genera</strong> belong to families (e.g., Andricus, Quercus)</li>
            <li>
              <strong>Sections</strong>
              are optional sub-groupings within genera (used primarily for Quercus oaks)
            </li>
          </ul>
        </div>
      </Layouts.admin_edit_layout>
    </Layouts.admin>
    """
  end
end
