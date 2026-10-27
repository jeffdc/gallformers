defmodule GallformersWeb.Admin.GallLive.Edit do
  @moduledoc """
  The Gall page in admin (matter a856, Decisions 2, 3 and 6, Design 3, Task
  7), reached from the Gall search and the public Gall page. Galls arrive
  with imports (their Hosts, Traits and aliases too); here a curator edits
  what is Gallformers' own, in sections, each saved on its own as the
  signed-in admin (the `:admin` live session's actor):

    * **editorial fields** — Gallformers code (uniqueness checked as it is
      typed), abundance, `datacomplete` (locked false, with the reason, for
      an undescribed Gall or one with no Sources) and the lead Source (one of
      the Gall's Sources, `Gallformers.Catalog.gall_sources/1`), through
      `Gallformers.Catalog.update_gall_editorial/3`;
    * **name** — the name parts (form label, descriptor, Host qualifier
      picked from the plants) and the override, with the name they derive
      and any collision shown as they are typed, through
      `Gallformers.Catalog.update_name_parts/3`;
    * **images** — `GallformersWeb.Admin.ImagesComponent`;
    * **Gallformers note** — its current text, each save a new version
      dated today (`Gallformers.Sources.store_note/5`), earlier versions
      listed;
    * **range exclusions** — the potential range on the range map (today's
      gall-range map and country drill-down), click to exclude a place or
      restore an excluded one, a statement, and Save: one Gallformers
      statement through the import path
      (`GallformersWeb.Admin.GallLive.RangeExclusions`), whose outcome is
      shown — applied, or awaiting review in the queue.

  There is no delete (merges come later, `3e8c`).
  """
  use GallformersWeb, :live_view

  alias Gallformers.Catalog
  alias Gallformers.Catalog.Gall
  alias Gallformers.Catalog.GallName
  alias Gallformers.Import
  alias Gallformers.Places
  alias Gallformers.Sources
  alias Gallformers.Taxa
  alias GallformersWeb.Admin.GallLive.RangeExclusions
  alias GallformersWeb.Admin.ImagesComponent
  alias GallformersWeb.Admin.PlaceDrillDown

  @qualifier_results 10

  @lock_reasons %{
    no_sources: "Locked: the Gall has no Sources (citations, notes or current Facts).",
    undescribed: "Locked: the Gall is undescribed (no current species-rank Inducer)."
  }

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Integer.parse(id) do
      {gall_id, ""} -> mount_gall(socket, Catalog.get_gall(gall_id))
      _ -> mount_gall(socket, nil)
    end
  end

  defp mount_gall(socket, nil) do
    {:ok,
     socket
     |> put_flash(:error, "Gall not found")
     |> push_navigate(to: ~p"/admin/galls")}
  end

  defp mount_gall(socket, %Gall{} = gall) do
    all_places = Places.list_all_places()

    {:ok,
     socket
     |> assign(:all_places, all_places)
     |> assign(:place_by_code, Map.new(all_places, &{&1.code, &1}))
     |> assign(:abundances, Catalog.list_abundances())
     |> assign(:outcome, nil)
     |> assign_gall(gall)
     |> assign_name_form()
     |> assign_notes()
     |> assign_range()}
  end

  # -- editorial fields ----------------------------------------------------------

  @impl true
  def handle_event("validate_editorial", %{"gall" => params}, socket) do
    changeset =
      socket.assigns.gall
      |> Catalog.change_gall_editorial(params)
      |> check_code(socket.assigns.gall)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :editorial_form, to_form(changeset))}
  end

  def handle_event("save_editorial", %{"gall" => params}, socket) do
    # A locked Gall saves complete only cleared (the checkbox is disabled).
    params =
      if socket.assigns.lock == :unlocked,
        do: params,
        else: Map.put(params, "datacomplete", "false")

    case Catalog.update_gall_editorial(socket.assigns.actor, socket.assigns.gall, params) do
      {:ok, gall} ->
        {:noreply, socket |> put_flash(:info, "Editorial fields saved") |> assign_gall(gall)}

      {:error, changeset} ->
        {:noreply, assign(socket, :editorial_form, to_form(changeset))}
    end
  end

  # -- name ----------------------------------------------------------------------

  def handle_event("validate_name", %{"name" => params}, socket) do
    {:noreply, assign_name_form(socket, params, :validate)}
  end

  def handle_event("save_name", params, socket) do
    attrs = name_attrs(socket, Map.get(params, "name", %{}))

    case Catalog.update_name_parts(socket.assigns.actor, socket.assigns.gall, attrs) do
      {:ok, gall} ->
        {:noreply,
         socket
         |> put_flash(:info, "Name saved")
         |> assign_gall(gall)
         |> assign_name_form()}

      {:error, changeset} ->
        {:noreply, socket |> assign(:name_form, to_form(changeset, as: :name))}
    end
  end

  def handle_event("search_qualifier", %{"value" => query}, socket) do
    results =
      if String.length(String.trim(query)) >= 2,
        do: Taxa.search_plants(query, @qualifier_results),
        else: []

    {:noreply, assign(socket, qualifier_query: query, qualifier_results: results)}
  end

  def handle_event("select_qualifier", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.qualifier_results, &("#{&1.id}" == id)) do
      nil ->
        {:noreply, socket}

      plant ->
        socket
        |> assign(qualifier: %{id: plant.id, name: plant.name})
        |> assign(qualifier_query: "", qualifier_results: [])
        |> assign_name_form(socket.assigns.name_params, :validate)
        |> then(&{:noreply, &1})
    end
  end

  def handle_event("clear_qualifier", _params, socket) do
    socket
    |> assign(qualifier: nil, qualifier_query: "", qualifier_results: [])
    |> assign_name_form(socket.assigns.name_params, :validate)
    |> then(&{:noreply, &1})
  end

  # -- Gallformers note ----------------------------------------------------------

  def handle_event("save_note", %{"note" => %{"text" => text}}, socket) do
    current = socket.assigns.notes |> List.first() |> then(&(&1 && &1.text))

    cond do
      String.trim(text) == "" ->
        {:noreply, put_flash(socket, :error, "A note needs text")}

      current && String.trim(text) == String.trim(current) ->
        {:noreply, put_flash(socket, :info, "The note is unchanged; nothing was stored")}

      true ->
        store_note(socket, text)
    end
  end

  # -- range exclusions ----------------------------------------------------------

  def handle_event("toggle_region", %{"code" => code}, socket) do
    {:noreply, mark(socket, code)}
  end

  def handle_event("toggle_country", %{"code" => code}, socket) do
    case Map.get(socket.assigns.place_by_code, code) do
      nil ->
        {:noreply, socket}

      place ->
        if Places.leaf_descendant_ids(place.id) == [place.id] do
          {:noreply, mark(socket, code)}
        else
          send_update(PlaceDrillDown, id: "range-drill-down", action: {:open, place})
          {:noreply, push_event(socket, "range-zoom-to-country", %{code: code})}
        end
    end
  end

  def handle_event("save_exclusions", %{"exclusions" => %{"statement" => text}}, socket) do
    %{range: range, marked: marked} = socket.assigns
    plan = RangeExclusions.plan(range.exclusions, marked)

    cond do
      plan.exclude == [] and plan.withdraw == [] ->
        {:noreply,
         put_flash(socket, :info, "Nothing to save: mark places to exclude or restore first")}

      String.trim(text) == "" ->
        {:noreply,
         assign(socket, :statement_form, statement_form(text, statement: {"can't be blank", []}))}

      true ->
        submit_exclusions(socket, plan, text)
    end
  end

  @impl true
  def handle_info({PlaceDrillDown, {:toggle_place, code}}, socket),
    do: {:noreply, mark(socket, code)}

  # The drill-down's "Select all" keeps places in the range: restores them.
  def handle_info({PlaceDrillDown, {:include_all, codes}}, socket) do
    {:noreply, set_marked(socket, MapSet.difference(socket.assigns.marked, MapSet.new(codes)))}
  end

  def handle_info({PlaceDrillDown, {:exclude_all, codes}}, socket) do
    markable = Enum.filter(codes, &RangeExclusions.markable?(socket.assigns.range, &1))
    {:noreply, set_marked(socket, MapSet.union(socket.assigns.marked, MapSet.new(markable)))}
  end

  def handle_info({PlaceDrillDown, :zoom_out}, socket),
    do: {:noreply, push_event(socket, "range-zoom-out", %{})}

  # -- helpers: the Gall ----------------------------------------------------------

  defp assign_gall(socket, %Gall{} = gall) do
    socket
    |> assign(:gall, gall)
    |> assign(:page_title, Gall.display_name(gall))
    |> assign(:lock, Catalog.datacomplete_lock(gall))
    |> assign(:gall_sources, Catalog.gall_sources(gall.id))
    |> assign(:editorial_form, to_form(Catalog.change_gall_editorial(gall)))
  end

  defp check_code(changeset, gall) do
    code = Ecto.Changeset.get_field(changeset, :gallformers_code)

    if is_binary(code) and Catalog.gallformers_code_taken?(code, gall.id),
      do:
        Ecto.Changeset.add_error(changeset, :gallformers_code, "is already used by another Gall"),
      else: changeset
  end

  # -- helpers: the name ----------------------------------------------------------

  # The name form, with the Host qualifier from the Gall (no params) or the
  # picker, and the name the parts derive.
  defp assign_name_form(socket) do
    gall = socket.assigns.gall

    qualifier =
      gall.host_qualifier_taxon_id &&
        %{
          id: gall.host_qualifier_taxon_id,
          name: Taxa.accepted_name(gall.host_qualifier_taxon_id)
        }

    socket
    |> assign(qualifier: qualifier, qualifier_query: "", qualifier_results: [])
    |> assign_name_form(%{}, nil)
  end

  defp assign_name_form(socket, params, action) do
    changeset = Catalog.change_name_parts(socket.assigns.gall, name_attrs(socket, params))
    preview = changeset |> Ecto.Changeset.apply_changes() |> name_preview(socket.assigns.gall)

    socket
    |> assign(:name_params, params)
    |> assign(:name_preview, preview)
    |> assign(:name_form, to_form(%{changeset | action: action}, as: :name))
  end

  defp name_attrs(socket, params) do
    Map.put(
      params,
      "host_qualifier_taxon_id",
      socket.assigns.qualifier && socket.assigns.qualifier.id
    )
  end

  # The name `pending`'s parts derive and the name it would show, and
  # whether that is another Gall's.
  defp name_preview(%Gall{} = pending, %Gall{} = gall) do
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

  defp name_errors(form), do: Enum.map(form[:name].errors, &translate_error/1)

  defp derive_error(:several_inducers), do: "its current Sources disagree on its Inducer"
  defp derive_error(:no_base), do: "an Inducer above species needs a descriptor"
  defp derive_error(:no_family), do: "its Inducer is above family"
  defp derive_error(:no_genus), do: "its Inducer is not in a genus"

  # -- helpers: the note ----------------------------------------------------------

  defp assign_notes(socket) do
    notes =
      for document <- Sources.list_gall_notes(socket.assigns.gall.id) do
        text = document |> Sources.list_document_items() |> Enum.map_join("\n\n", & &1.text)
        %{id: document.id, version_date: document.version_date, text: text}
      end

    current = notes |> List.first() |> then(&((&1 && &1.text) || ""))

    socket
    |> assign(:notes, notes)
    |> assign(:note_form, to_form(%{"text" => current}, as: :note))
  end

  defp store_note(socket, text) do
    %{actor: actor, gall: gall} = socket.assigns

    with %{} = gallformers <- Sources.get_gallformers_source(),
         {:ok, document} <-
           Sources.store_note(actor, gallformers, gall.id, text, Date.utc_today()) do
      socket = socket |> assign_notes() |> assign_gall(Catalog.get_gall!(gall.id))

      message =
        case socket.assigns.notes do
          [%{id: id} | _] when id == document.id ->
            {:info, "Note saved as a new version"}

          _ ->
            {:warning,
             "That text is an earlier version's; Sources keep each text once, so nothing new was stored"}
        end

      {:noreply, put_flash(socket, elem(message, 0), elem(message, 1))}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "There is no Gallformers Source to hold the note")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not store the note: #{inspect(reason)}")}
    end
  end

  # -- helpers: range exclusions ---------------------------------------------------

  defp assign_range(socket) do
    range = RangeExclusions.load(socket.assigns.gall.id, socket.assigns.place_by_code)

    sources =
      range.exclusions
      |> Enum.flat_map(fn e -> Enum.map(e.attributions, & &1.source_id) end)
      |> Enum.uniq()
      |> Sources.list_sources_by_id()
      |> Map.new(&{&1.id, &1.title})

    socket
    |> assign(:range, range)
    |> assign(:exclusion_sources, sources)
    |> assign(:statement_form, statement_form(""))
    |> assign(:range_bounds, Places.get_bounds_for_codes(RangeExclusions.markable_codes(range)))
    |> set_marked(range.excluded, push: false)
  end

  defp mark(socket, code) do
    if RangeExclusions.markable?(socket.assigns.range, code) do
      marked = socket.assigns.marked

      marked =
        if MapSet.member?(marked, code),
          do: MapSet.delete(marked, code),
          else: MapSet.put(marked, code)

      set_marked(socket, marked)
    else
      socket
    end
  end

  defp set_marked(socket, marked, opts \\ []) do
    %{range: range, place_by_code: place_by_code} = socket.assigns
    map = RangeExclusions.map_ranges(range, marked)
    name = &(place_by_code |> Map.get(&1, %{name: &1}) |> Map.get(:name))

    socket =
      socket
      |> assign(:marked, marked)
      |> assign(:map, map)
      |> assign(:marked_place_ids, for(code <- marked, p = place_by_code[code], do: p.id))
      |> assign(
        :to_exclude,
        marked |> MapSet.difference(range.excluded) |> Enum.map(name) |> Enum.sort()
      )
      |> assign(
        :to_restore,
        range.excluded |> MapSet.difference(marked) |> Enum.map(name) |> Enum.sort()
      )

    if Keyword.get(opts, :push, true),
      do:
        push_event(
          socket,
          "range-update",
          Map.take(map, [:in_range, :excluded_range, :inherited_range, :introduced_range])
        ),
      else: socket
  end

  defp statement_form(text, errors \\ []),
    do: to_form(%{"statement" => text}, as: :exclusions, errors: errors)

  defp submit_exclusions(socket, plan, text) do
    %{actor: actor, gall: gall, all_places: all_places} = socket.assigns
    names = Map.new(all_places, &{&1.code, &1.name})
    statement = %{text: text, stated_on: Date.utc_today()}

    with {:ok, batch} <-
           RangeExclusions.batch(Catalog.gall_summary(gall.id), plan, statement, names),
         {:ok, package} <- Import.submit_gallformers_fragment(actor, %{"gall.json" => batch}) do
      {:noreply,
       socket
       |> assign(:outcome, outcome(package))
       |> assign_range()
       |> push_range_update()}
    else
      {:error, :unidentified} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "This Gall has neither an Inducer nor a Host, so a statement cannot name it"
         )}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Could not submit the statement: #{inspect(reason)}")}
    end
  end

  defp push_range_update(socket) do
    push_event(
      socket,
      "range-update",
      Map.take(socket.assigns.map, [
        :in_range,
        :excluded_range,
        :inherited_range,
        :introduced_range
      ])
    )
  end

  defp outcome(%{status: :approved} = package) do
    if Enum.all?(Import.list_batches(package), &(&1.status == :applied)),
      do: {:applied, package},
      else: {:approved, package}
  end

  defp outcome(%{status: status} = package), do: {status, package}

  defp exclusion_by(exclusion, sources) do
    exclusion.attributions
    |> Enum.map(&Map.get(sources, &1.source_id))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.join("; ")
  end

  # -- render ---------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title={@page_title}>
      <:page_title_html>
        Editing <em class="font-bold">{@page_title}</em>
      </:page_title_html>
      <Layouts.admin_edit_layout
        back_path={~p"/admin/galls"}
        back_label="Back to Galls"
        public_url={~p"/gall/#{@gall.id}"}
      >
        <:intro>
          Galls, their Hosts, Traits and common names arrive with imports. Here you edit what is
          Gallformers' own: editorial fields, the name, images, the Gallformers note and range
          exclusions. Each section saves on its own.
        </:intro>

        <div class="space-y-6">
          <.card id="editorial" title="Editorial">
            <.form
              for={@editorial_form}
              id="editorial-form"
              phx-change="validate_editorial"
              phx-submit="save_editorial"
            >
              <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-3">
                <.input
                  field={@editorial_form[:gallformers_code]}
                  label="Gallformers Code"
                  placeholder="e.g. q-lobata-leaf-blister"
                  phx-debounce="300"
                />
                <.input
                  field={@editorial_form[:abundance_id]}
                  type="select"
                  label="Abundance"
                  prompt="Unknown"
                  options={Enum.map(@abundances, &{&1.abundance, &1.id})}
                />
              </div>

              <div class="mb-3">
                <.input
                  field={@editorial_form[:default_source_id]}
                  type="select"
                  label="Lead Source (the Gall page leads with it)"
                  prompt="None"
                  options={Enum.map(@gall_sources, &{&1.title, &1.id})}
                />
              </div>

              <div class="mb-3">
                <.input
                  field={@editorial_form[:datacomplete]}
                  type="checkbox"
                  disabled={@lock != :unlocked}
                  label="All sources containing unique information relevant to this gall have been added and are reflected in its associated data"
                />
                <p
                  :if={match?({:locked, _}, @lock)}
                  id="datacomplete-lock"
                  class="text-amber-600 text-xs mt-1"
                >
                  {@lock |> elem(1) |> then(&Map.fetch!(lock_reasons(), &1))}
                </p>
              </div>

              <div class="flex justify-end">
                <.button type="submit" variant="primary">Save editorial fields</.button>
              </div>
            </.form>
          </.card>

          <.card id="name" title="Name">
            <p class="text-sm text-gray-600 mb-3">
              The name is derived from the Gall's Inducer, generation and these parts. An override
              replaces the name shown.
            </p>

            <div class="mb-3 text-sm space-y-1">
              <div>
                <span class="font-medium text-gray-700">Derived name:</span>
                <%= case @name_preview.derived do %>
                  <% {:ok, derived} -> %>
                    <em id="derived-name">{derived}</em>
                  <% {:error, reason} -> %>
                    <span id="derived-name" class="text-amber-700">
                      none — {derive_error(reason)}; give a name override
                    </span>
                <% end %>
              </div>
              <div>
                <span class="font-medium text-gray-700">Name shown:</span>
                <em id="name-shown">{@name_preview.shown}</em>
              </div>
              <p :if={@name_preview.taken?} id="name-collision" class="text-red-600">
                “{@name_preview.shown}” is already the name of another Gall.
              </p>
            </div>

            <div class="mb-3 max-w-xl">
              <.typeahead
                id="host-qualifier-picker"
                label="Host qualifier (written “on” the plant)"
                placeholder="Search plants..."
                query={@qualifier_query}
                results={@qualifier_results}
                selected={@qualifier}
                search_event="search_qualifier"
                select_event="select_qualifier"
                clear_event="clear_qualifier"
                display_fn={& &1.name}
              />
            </div>

            <.form for={@name_form} id="name-form" phx-change="validate_name" phx-submit="save_name">
              <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-3">
                <.input
                  field={@name_form[:form_label]}
                  label="Form label"
                  placeholder="e.g. bud, australis"
                />
                <.input
                  field={@name_form[:descriptor]}
                  label="Descriptor (undescribed Galls)"
                  placeholder="e.g. q-havardii-cup-gall"
                />
              </div>
              <div class="mb-3">
                <.input field={@name_form[:name_override]} label="Name override" />
              </div>
              <div :if={name_errors(@name_form) != []} id="name-errors" class="mb-3">
                <p :for={message <- name_errors(@name_form)} class="text-sm text-red-600">
                  Name {message}
                </p>
              </div>
              <div class="flex justify-end">
                <.button type="submit" variant="primary">Save name</.button>
              </div>
            </.form>
          </.card>

          <.card id="images" title="Images">
            <.live_component
              module={ImagesComponent}
              id="gall-images"
              owner={{:gall, @gall.id}}
              uploader={@actor.name}
              name={@page_title}
            />
          </.card>

          <.card id="note" title="Gallformers note">
            <p class="text-sm text-gray-600 mb-3">
              Gallformers' own ID notes on this Gall. Each save is a new version dated today; the
              Gall page shows the newest.
            </p>
            <.form for={@note_form} id="note-form" phx-submit="save_note">
              <.input field={@note_form[:text]} type="textarea" label="Note (Markdown)" rows="10" />
              <div class="flex justify-end mt-3">
                <.button type="submit" variant="primary">Save note</.button>
              </div>
            </.form>

            <div :if={@notes != []} class="mt-6">
              <h4 class="text-sm font-medium text-gray-700 mb-2">Versions, newest first</h4>
              <ol id="note-versions" class="space-y-3">
                <li
                  :for={{note, index} <- Enum.with_index(@notes)}
                  id={"note-version-#{note.id}"}
                  class="border border-gray-200 rounded p-3"
                >
                  <div class="text-xs text-gray-500 mb-1 flex items-center gap-2">
                    {if note.version_date, do: note.version_date, else: "Undated (carried over)"}
                    <.badge :if={index == 0} variant="success">Current</.badge>
                  </div>
                  <div class="text-sm text-gray-700 whitespace-pre-wrap">{note.text}</div>
                </li>
              </ol>
            </div>
          </.card>

          <.card id="range-exclusions" title="Range exclusions">
            <p class="text-sm text-gray-600 mb-3">
              The Gall's potential range comes from its Hosts' ranges. Click a place to exclude it
              (the Gall does not occur there) or to restore an excluded one; a country with
              subdivisions opens them. Saving states the change as Gallformers' own, with your
              statement, through the import queue.
            </p>

            <p :if={@range.everywhere?} class="text-sm text-amber-700 mb-3">
              No Host range data: the Gall's range is everywhere. Any place can be excluded.
            </p>

            <div class="border border-gray-300 rounded">
              <div class="grid grid-cols-6 gap-2 p-3">
                <div class="col-span-1">
                  <div class="text-sm font-medium text-gray-700 mb-2">Legend:</div>
                  <.range_map_legend mode={:gall_admin} />
                </div>
                <div class="col-span-5">
                  <div class="flex">
                    <div class="flex-1">
                      <.range_map
                        id="exclusions-range-map"
                        in_range={@map.in_range}
                        excluded_range={@map.excluded_range}
                        inherited_range={@map.inherited_range}
                        introduced_range={@map.introduced_range}
                        bounds={@range_bounds}
                        editable
                        class="border border-gray-300 rounded bg-gray-50 min-h-[350px]"
                      />
                    </div>
                    <.live_component
                      module={PlaceDrillDown}
                      id="range-drill-down"
                      mode={:gall}
                      omitted_place_ids={@marked_place_ids}
                      host_places={
                        if @range.everywhere?, do: [], else: RangeExclusions.markable_codes(@range)
                      }
                      all_places={@all_places}
                      introduced_range={@range.introduced_range}
                    />
                  </div>
                </div>
              </div>
            </div>

            <div :if={@range.exclusions != []} id="current-exclusions" class="mt-4 text-sm">
              <h4 class="font-medium text-gray-700 mb-1">Current exclusions</h4>
              <ul class="list-disc ml-5 text-gray-600">
                <li :for={exclusion <- @range.exclusions}>
                  {exclusion.place_name}
                  <span class="text-gray-400">({exclusion_by(exclusion, @exclusion_sources)})</span>
                </li>
              </ul>
            </div>

            <div
              :if={@to_exclude != [] or @to_restore != []}
              id="marked-places"
              class="mt-4 text-sm space-y-1"
            >
              <p :if={@to_exclude != []}>
                <span class="font-medium text-red-700">To exclude:</span> {Enum.join(
                  @to_exclude,
                  ", "
                )}
              </p>
              <p :if={@to_restore != []}>
                <span class="font-medium text-green-700">To restore:</span> {Enum.join(
                  @to_restore,
                  ", "
                )}
              </p>
            </div>

            <.form
              for={@statement_form}
              id="exclusions-form"
              phx-submit="save_exclusions"
              class="mt-4"
            >
              <.input
                field={@statement_form[:statement]}
                type="textarea"
                label="Statement (why, in plain words; required)"
                rows="3"
              />
              <div class="flex justify-end mt-3">
                <.button type="submit" variant="primary">Save exclusions</.button>
              </div>
            </.form>

            <div :if={@outcome} id="exclusions-outcome" class="mt-4">
              <%= case @outcome do %>
                <% {:applied, _package} -> %>
                  <.alert variant="success">
                    Applied: the statement is part of the Gall's range.
                  </.alert>
                <% {:approved, package} -> %>
                  <.alert variant="info">
                    Approved; the statement is being applied.
                    <.link navigate={~p"/admin/queue/packages/#{package.id}"} class="underline">
                      View it in the queue
                    </.link>
                  </.alert>
                <% {:awaiting_review, package} -> %>
                  <.alert variant="warning">
                    Your statement awaits review in the queue before it is applied.
                    <.link navigate={~p"/admin/queue/packages/#{package.id}"} class="underline">
                      Review it
                    </.link>
                  </.alert>
                <% {:invalid, package} -> %>
                  <.alert variant="error">
                    The statement was not valid:
                    <ul class="list-disc ml-5">
                      <li :for={problem <- package.problems}>{problem["message"]}</li>
                    </ul>
                  </.alert>
                <% {status, package} -> %>
                  <.alert variant="info">
                    The statement is {status}.
                    <.link navigate={~p"/admin/queue/packages/#{package.id}"} class="underline">
                      View it in the queue
                    </.link>
                  </.alert>
              <% end %>
            </div>
          </.card>
        </div>

        <.record_metadata inserted_at={@gall.inserted_at} updated_at={@gall.updated_at} />
      </Layouts.admin_edit_layout>
    </Layouts.admin>
    """
  end

  defp lock_reasons, do: @lock_reasons
end
