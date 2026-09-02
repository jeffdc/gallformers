defmodule GallformersWeb.Admin.TaxonomyLive.Form do
  @moduledoc """
  Admin form for creating and editing taxonomy entries.

  Includes a hierarchical parent selector for setting up the taxonomy tree.
  """
  use GallformersWeb, :live_view
  use GallformersWeb.Admin.FormHelpers, crud_helpers: true, include_delete: false

  import GallformersWeb.Admin.FormComponents, only: [form_actions: 1]

  import GallformersWeb.BrowseHelpers, only: [toggle_group_selection: 3, toggle_set: 2]

  import GallformersWeb.FormComponents,
    only: [cascade_delete_modal: 1, selectable_tree: 1, typeahead: 1]

  alias Gallformers.Taxonomy
  alias GallformersWeb.TaxonomyURL
  alias Phoenix.HTML.Form, as: HtmlForm

  # Group ID for unassigned genera in the children tree (used in expanded defaults + group builder).
  @unassigned_group "unassigned"

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

  # Override do_update to handle genus rename collision errors,
  # which return {:error, {:rename_collision, ...}} instead of changeset errors.
  defp do_update(socket, params) do
    entity = Map.get(socket.assigns, entity_key())

    case update_entity(entity, params) do
      {:ok, entity} ->
        {:noreply, after_update(socket, entity)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, {:rename_collision, species_name, _reason}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Cannot rename: \"#{species_name}\" would collide with an existing species"
         )}
    end
  end

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
    socket
    |> apply_new_action(parent_options: load_parent_options(nil))
    |> assign(:children_tree_groups, [])
    |> assign(:selected_children, MapSet.new())
    |> assign(:expanded_intermediate_groups, MapSet.new([@unassigned_group]))
    |> assign_parent_typeahead_defaults(nil, [])
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket = apply_edit_action(socket, id)
    # Add parent_options based on loaded entity's type
    taxonomy = socket.assigns[:taxonomy]

    if taxonomy do
      all_parent_options =
        taxonomy.type
        |> Taxonomy.list_parent_options_with_paths()
        |> Enum.reject(&(&1.id == taxonomy.id))

      socket
      |> assign(:parent_options, load_parent_options(taxonomy.type) |> reject_self(taxonomy.id))
      |> assign(:show_delete_modal, false)
      |> assign(:deletion_impact, nil)
      |> assign(:delete_confirmation, "")
      |> assign(:children_tree_groups, [])
      |> assign(:selected_children, MapSet.new())
      |> assign(:expanded_intermediate_groups, MapSet.new([@unassigned_group]))
      |> assign_parent_typeahead_defaults(taxonomy, all_parent_options)
    else
      socket
    end
  end

  defp assign_parent_typeahead_defaults(socket, taxonomy, all_parent_options) do
    selected_parent =
      if taxonomy && taxonomy.parent_id do
        Enum.find(all_parent_options, &(&1.id == taxonomy.parent_id))
      end

    socket
    |> assign(:parent_query, "")
    |> assign(:parent_results, [])
    |> assign(:selected_parent, selected_parent)
    |> assign(:all_parent_options, all_parent_options)
  end

  defp load_parent_options(type) when type in [nil, ""] do
    # No type selected yet — don't show parent options
    []
  end

  defp load_parent_options("family"), do: []

  defp load_parent_options("genus") do
    # Genera can parent to families or intermediates
    families = Taxonomy.list_families_for_select()

    intermediates =
      Taxonomy.list_taxonomies_by_type("intermediate")
      |> Enum.map(fn t -> {"#{t.name} (#{t.rank})", t.id} end)

    families ++ intermediates
  end

  defp load_parent_options("intermediate") do
    # Intermediates can parent to families or other intermediates
    families = Taxonomy.list_families_for_select()

    intermediates =
      Taxonomy.list_taxonomies_by_type("intermediate")
      |> Enum.map(fn t -> {"#{t.name} (#{t.rank})", t.id} end)

    families ++ intermediates
  end

  defp load_parent_options("section") do
    Taxonomy.list_genera_for_select(:plant)
    |> Enum.map(fn g -> {g.name, g.id} end)
  end

  defp reject_self(options, nil), do: options

  defp reject_self(options, id) do
    Enum.reject(options, fn
      {_label, opt_id} -> opt_id == id
      _ -> false
    end)
  end

  # Custom validate handler to update parent_options when type changes
  @impl true
  def handle_event("validate", %{"taxonomy" => params}, socket) do
    # Disabled fields aren't submitted by the browser — inject type in edit mode
    params = inject_type_for_edit(params, socket)

    prev_type = HtmlForm.input_value(socket.assigns.form, :type)
    type_changed? = params["type"] != prev_type

    params = normalize_validate_params(params, type_changed?, socket)

    changeset =
      socket.assigns.taxonomy
      |> Taxonomy.change_taxonomy(params)
      |> validate_unique_name_parent(socket.assigns.taxonomy)
      |> Map.put(:action, :validate)

    socket =
      socket
      |> maybe_reload_parent_options(params, type_changed?)
      |> maybe_reload_children(params)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:parent_options, load_parent_options(params["type"]))
     |> mark_dirty()}
  end

  # Catch-all for validate events that don't match the expected form structure
  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  # Parent typeahead events
  @impl true
  def handle_event("search_parent", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        query_lower = String.downcase(query)

        socket.assigns.all_parent_options
        |> Enum.filter(fn opt ->
          String.contains?(String.downcase(opt.path), query_lower)
        end)
        |> Enum.take(20)
      else
        []
      end

    {:noreply, assign(socket, parent_query: query, parent_results: results)}
  end

  @impl true
  def handle_event("select_parent", %{"id" => id}, socket) do
    parent_id = String.to_integer(id)
    parent = Enum.find(socket.assigns.all_parent_options, &(&1.id == parent_id))

    if parent do
      # Update the form changeset with the selected parent_id
      params =
        socket.assigns.form.source
        |> Ecto.Changeset.apply_changes()
        |> Map.from_struct()
        |> Map.new(fn {k, v} -> {to_string(k), v} end)
        |> Map.put("parent_id", to_string(parent_id))

      changeset =
        socket.assigns.taxonomy
        |> Taxonomy.change_taxonomy(params)
        |> Map.put(:action, :validate)

      # Load children options for intermediates in new mode
      socket =
        if params["type"] == "intermediate" and socket.assigns.live_action == :new do
          groups =
            parent_id
            |> to_string()
            |> load_children_options()
            |> children_tree_groups()

          socket
          |> assign(:children_tree_groups, groups)
          |> assign(:selected_children, MapSet.new())
          |> assign(:expanded_intermediate_groups, MapSet.new([@unassigned_group]))
        else
          socket
        end

      {:noreply,
       socket
       |> assign(:selected_parent, parent)
       |> assign(:parent_query, "")
       |> assign(:parent_results, [])
       |> assign(:form, to_form(changeset))
       |> mark_dirty()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_parent", _params, socket) do
    params =
      socket.assigns.form.source
      |> Ecto.Changeset.apply_changes()
      |> Map.from_struct()
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("parent_id", "")

    changeset =
      socket.assigns.taxonomy
      |> Taxonomy.change_taxonomy(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:selected_parent, nil)
     |> assign(:parent_query, "")
     |> assign(:parent_results, [])
     |> assign(:children_tree_groups, [])
     |> assign(:selected_children, MapSet.new())
     |> assign(:expanded_intermediate_groups, MapSet.new([@unassigned_group]))
     |> assign(:form, to_form(changeset))
     |> mark_dirty()}
  end

  @impl true
  def handle_event("toggle_child", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)

    {:noreply,
     assign(socket, :selected_children, toggle_set(socket.assigns.selected_children, id))}
  end

  @impl true
  def handle_event("select_all_children", _params, socket) do
    all_ids =
      socket.assigns.children_tree_groups
      |> Enum.flat_map(& &1.items)
      |> MapSet.new(& &1.id)

    {:noreply, assign(socket, :selected_children, all_ids)}
  end

  @impl true
  def handle_event("deselect_all_children", _params, socket) do
    {:noreply, assign(socket, :selected_children, MapSet.new())}
  end

  @impl true
  def handle_event("expand_children_group", %{"group" => group_id}, socket) do
    expanded = toggle_set(socket.assigns.expanded_intermediate_groups, group_id)
    {:noreply, assign(socket, :expanded_intermediate_groups, expanded)}
  end

  @impl true
  def handle_event("toggle_group_children", %{"group" => group_id}, socket) do
    updated =
      toggle_group_selection(
        socket.assigns.children_tree_groups,
        socket.assigns.selected_children,
        group_id
      )

    {:noreply, assign(socket, :selected_children, updated)}
  end

  @impl true
  def handle_event("save", %{"taxonomy" => taxonomy_params} = params, socket) do
    # Disabled fields aren't submitted by the browser — inject type in edit mode
    # (must happen before inject_parent_id which checks the type)
    taxonomy_params = inject_type_for_edit(taxonomy_params, socket)

    # Inject parent_id from typeahead for types that use it
    taxonomy_params = inject_parent_id(taxonomy_params, socket)

    params = Map.put(params, "taxonomy", taxonomy_params)

    if taxonomy_params["type"] == "intermediate" and socket.assigns.live_action == :new do
      handle_save_intermediate(taxonomy_params, socket)
    else
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
    impact = Taxonomy.get_deletion_impact(taxonomy)

    cond do
      taxonomy.type == "section" and impact.species_count > 0 ->
        {:noreply,
         socket
         |> assign(:deletion_impact, impact)
         |> put_flash(
           :error,
           "This section cannot be deleted until its linked species are reclassified."
         )}

      confirmation != expected_name ->
        {:noreply, put_flash(socket, :error, "Name does not match. Please type the exact name.")}

      true ->
        case Taxonomy.delete_taxonomy_cascade(taxonomy) do
          {:ok, deleted_impact} ->
            message = build_delete_success_message(taxonomy, deleted_impact)

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

  # When type changes, clear name/parent/rank. Otherwise inject the parent_id from
  # the typeahead selection — the typeahead doesn't generate a hidden form input, so
  # params never includes parent_id on its own. Without this, non-typeahead form
  # changes (e.g., checkbox clicks) would build a changeset that loses the parent.
  defp normalize_validate_params(params, true = _type_changed?, _socket) do
    Map.merge(params, %{"name" => "", "parent_id" => "", "rank" => ""})
  end

  defp normalize_validate_params(params, false, socket) do
    case socket.assigns[:selected_parent] do
      %{id: id} -> Map.put_new(params, "parent_id", to_string(id))
      _ -> params
    end
  end

  defp maybe_reload_parent_options(socket, params, true = _type_changed?) do
    exclude_id = socket.assigns.taxonomy && socket.assigns.taxonomy.id

    all_parent_options =
      params["type"]
      |> Taxonomy.list_parent_options_with_paths()
      |> Enum.reject(&(&1.id == exclude_id))

    socket
    |> assign(:all_parent_options, all_parent_options)
    |> assign(:selected_parent, nil)
    |> assign(:parent_query, "")
    |> assign(:parent_results, [])
  end

  defp maybe_reload_parent_options(socket, _params, false), do: socket

  # Reload children when parent changes for intermediates in new mode.
  defp maybe_reload_children(socket, params) do
    if params["type"] == "intermediate" and socket.assigns.live_action == :new do
      prev_parent_id = Ecto.Changeset.get_field(socket.assigns.form.source, :parent_id)

      if to_string(params["parent_id"]) != to_string(prev_parent_id) do
        groups =
          params["parent_id"]
          |> load_children_options()
          |> children_tree_groups()

        assign(socket,
          children_tree_groups: groups,
          selected_children: MapSet.new(),
          expanded_intermediate_groups: MapSet.new([@unassigned_group])
        )
      else
        socket
      end
    else
      socket
    end
  end

  # Disabled fields aren't included in browser FormData. In edit mode,
  # the type select is disabled, so we must inject the existing type.
  defp inject_type_for_edit(params, socket) do
    if socket.assigns.mode == :edit do
      Map.put_new(params, "type", socket.assigns.taxonomy.type)
    else
      params
    end
  end

  defp inject_parent_id(params, socket) do
    if params["type"] in ["genus", "intermediate", "section"] do
      case socket.assigns.selected_parent do
        %{id: id} -> Map.put(params, "parent_id", to_string(id))
        _ -> params
      end
    else
      params
    end
  end

  defp handle_save_intermediate(params, socket) do
    children_ids = MapSet.to_list(socket.assigns.selected_children)

    if children_ids == [] do
      {:noreply, put_flash(socket, :error, "At least one child must be selected.")}
    else
      attrs =
        params
        |> Map.put("type", "intermediate")
        |> Map.put("children_ids", children_ids)

      case Taxonomy.create_intermediate(attrs) do
        {:ok, intermediate} ->
          {:noreply,
           socket
           |> put_flash(
             :info,
             "Created intermediate \"#{intermediate.name}\" (#{intermediate.rank})"
           )
           |> push_navigate(to: ~p"/admin/taxonomy/#{intermediate.id}")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :form, to_form(changeset))}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to create: #{inspect(reason)}")}
      end
    end
  end

  defp load_children_options(parent_id) when parent_id in [nil, ""],
    do: %{unassigned: [], intermediate_groups: [], intermediates: []}

  defp load_children_options(parent_id) do
    direct_children =
      parent_id
      |> String.to_integer()
      |> Taxonomy.get_children()
      |> Enum.reject(&(&1.type == "section"))

    {intermediates, genera} = Enum.split_with(direct_children, &(&1.type == "intermediate"))

    # Get genera under each intermediate sibling
    intermediate_ids = Enum.map(intermediates, & &1.id)

    assigned_by_parent =
      Taxonomy.Tree.get_children_for_parents(intermediate_ids)

    intermediate_groups =
      intermediates
      |> Enum.map(fn int ->
        children =
          assigned_by_parent
          |> Map.get(int.id, [])
          |> Enum.filter(&(&1.type == "genus"))
          |> Enum.map(fn g -> %{id: g.id, name: g.name, type: g.type, label: g.name} end)

        %{
          id: int.id,
          name: int.name,
          rank: int.rank,
          label: "#{int.name} (#{int.rank})",
          children: children
        }
      end)
      |> Enum.reject(&(&1.children == []))

    unassigned =
      Enum.map(genera, fn g ->
        %{id: g.id, name: g.name, type: g.type, label: g.name}
      end)

    intermediate_opts =
      Enum.map(intermediates, fn t ->
        %{id: t.id, name: t.name, type: t.type, label: "#{t.name} (#{t.rank})"}
      end)

    %{
      unassigned: unassigned,
      intermediate_groups: intermediate_groups,
      intermediates: intermediate_opts
    }
  end

  # Converts children_options into the groups format expected by selectable_tree.
  defp children_tree_groups(%{
         unassigned: unassigned,
         intermediate_groups: int_groups,
         intermediates: intermediates
       }) do
    to_items = fn children -> Enum.map(children, &%{id: &1.id, label: &1.label}) end

    unassigned_group =
      if unassigned != [],
        do: [%{id: @unassigned_group, label: "Unassigned genera", items: to_items.(unassigned)}],
        else: []

    int_item_groups =
      Enum.map(int_groups, fn g ->
        %{
          id: "under-#{g.id}",
          label: "Under #{g.label}",
          name: g.name,
          items: to_items.(g.children)
        }
      end)

    intermediates_group =
      if intermediates != [],
        do: [%{id: "intermediates", label: "Intermediates", items: to_items.(intermediates)}],
        else: []

    unassigned_group ++ int_item_groups ++ intermediates_group
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

  defp taxonomy_public_url(taxonomy), do: TaxonomyURL.public_path(taxonomy)

  defp validate_unique_name_parent(changeset, taxonomy) do
    name = Ecto.Changeset.get_field(changeset, :name)
    parent_id = Ecto.Changeset.get_field(changeset, :parent_id)

    if name && Taxonomy.Tree.name_parent_exists?(name, parent_id, taxonomy.id) do
      Ecto.Changeset.add_error(changeset, :name, "already exists for this parent")
    else
      changeset
    end
  end

  defp display_type(%{type: "intermediate", rank: rank}) when rank not in [nil, ""],
    do: String.capitalize(rank)

  defp display_type(%{type: type}), do: type

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
    >
      <:page_title_html>
        <%= if @mode == :edit do %>
          Editing <em class="font-bold">{display_type(@taxonomy)} {@taxonomy.name}</em>
        <% else %>
          New Taxonomy Entry
        <% end %>
      </:page_title_html>

      <Layouts.admin_edit_layout
        back_path={~p"/admin/taxonomy"}
        back_label="Back to Taxonomy"
        public_url={if @mode == :edit, do: taxonomy_public_url(@taxonomy)}
      >
        <:quick_links>
          <.link
            :if={@mode == :edit and @taxonomy.type == "section"}
            href={~p"/admin/section/#{@taxonomy.id}"}
            class="text-sm hover:underline"
          >
            Manage species in this section
          </.link>
        </:quick_links>

        <% type_selected = HtmlForm.input_value(@form, :type) not in [nil, ""] %>
        <.form for={@form} id="taxonomy-form" phx-change="validate" phx-submit="save">
          <div class="mb-3">
            <.input
              field={@form[:type]}
              schema={Taxonomy.Taxonomy}
              type="select"
              label="Type"
              prompt="Select type"
              disabled={@mode == :edit}
              options={[
                {"Family", "family"},
                {"Genus", "genus"},
                {"Intermediate", "intermediate"},
                {"Section", "section"}
              ]}
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

          <div :if={HtmlForm.input_value(@form, :type) == "intermediate"} class="mb-3">
            <.input
              field={@form[:rank]}
              type="select"
              label="Rank"
              prompt="Select rank"
              options={Taxonomy.Taxonomy.valid_ranks()}
              required={true}
            />
            <p class="mt-1 text-xs text-gray-500">
              The taxonomic rank label for this intermediate level.
            </p>
          </div>

          <div class="mb-3">
            <% current_type = HtmlForm.input_value(@form, :type) %>
            <%= cond do %>
              <% current_type in ["genus", "intermediate"] -> %>
                <.typeahead
                  id="parent-picker"
                  label="Parent"
                  placeholder="Search for a parent (family or intermediate)..."
                  search_event="search_parent"
                  select_event="select_parent"
                  clear_event="clear_parent"
                  query={@parent_query}
                  results={@parent_results}
                  selected={@selected_parent}
                  display_fn={fn opt -> opt.path end}
                  required={true}
                />
                <p class="mt-1 text-xs text-gray-500">
                  <%= if current_type == "genus" do %>
                    Genera belong to families or intermediates.
                  <% else %>
                    Intermediates belong to families or other intermediates.
                  <% end %>
                </p>
              <% current_type == "section" -> %>
                <.typeahead
                  id="parent-picker"
                  label="Parent"
                  placeholder="Search for a parent genus..."
                  search_event="search_parent"
                  select_event="select_parent"
                  clear_event="clear_parent"
                  query={@parent_query}
                  results={@parent_results}
                  selected={@selected_parent}
                  display_fn={fn opt -> opt.path end}
                  required={true}
                />
                <p class="mt-1 text-xs text-gray-500">
                  Sections belong to genera.
                </p>
              <% current_type == "family" -> %>
                <label class="gf-label">Parent:</label>
                <p class="text-sm text-gray-500 italic px-3 py-2">
                  Families are top-level entries and have no parent.
                </p>
              <% true -> %>
                <label class="gf-label">Parent:</label>
                <p class="text-sm text-gray-500 italic px-3 py-2">
                  Select a type to see available parent options.
                </p>
            <% end %>
          </div>

          <div
            :if={
              HtmlForm.input_value(@form, :type) == "intermediate" and @mode == :new and
                @children_tree_groups != []
            }
            class="mb-3"
          >
            <p class="mb-2 text-xs text-gray-500">
              Select which children should be re-parented under this new intermediate. At least one is required.
            </p>

            <.selectable_tree
              id="children-tree"
              label="Children to move under this intermediate"
              groups={@children_tree_groups}
              selected={@selected_children}
              expanded={@expanded_intermediate_groups}
              toggle_item_event="toggle_child"
              toggle_group_event="toggle_group_children"
              expand_group_event="expand_children_group"
              select_all_event="select_all_children"
              deselect_all_event="deselect_all_children"
            >
              <:group_footer :let={group}>
                <p :if={group[:name]} class="text-xs text-amber-600 italic">
                  Selecting these will move them from {group.name} to the new intermediate.
                </p>
                <p :if={group.id == "intermediates"} class="text-xs text-gray-500 italic">
                  Moving an intermediate re-parents its entire subtree.
                </p>
              </:group_footer>
            </.selectable_tree>

            <p :if={MapSet.size(@selected_children) == 0} class="mt-1 text-xs text-amber-600">
              Select at least one child to continue.
            </p>
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
            <li>
              <strong>Intermediates</strong>
              are ranks between family and genus (e.g., Subfamily, Tribe)
            </li>
            <li>
              <strong>Genera</strong> belong to families or intermediates (e.g., Andricus, Quercus)
            </li>
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
