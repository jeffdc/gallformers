defmodule GallformersWeb.GallLive.Editor do
  @moduledoc """
  Edit mode's parts of the Gall page (matter ec2c; the order Jeff set:
  Hosts and Traits first): the Inducer, the Hosts and the Traits, each
  Fact with its Sources and its actions, as `GallformersWeb.GallLive`
  shows them when a curator turns on Edit.

  Every action adds an item to the curator's tray (`Gallformers.Curation`):

    * a Host: Withdraw; Correct… (another plant in its place); Note…;
    * the Inducer: Note… (correcting it is taxonomy, phase 2);
    * a Trait value: ✕ withdraws it; a Trait's Add adds one;
    * Add a host, found by name;
    * Add from observation… (`GallformersWeb.ObservationIntake`, this Gall
      given), opened from the page header's button beside the Edit toggle
      (`open_observation`, targeted at this component).

  What is already in the tray is marked on the page (`pending_for/2`). The
  page refreshes this component when the tray changes elsewhere
  (`send_update/3` with `refresh: true`).
  """
  use GallformersWeb, :live_component

  alias Gallformers.Catalog
  alias Gallformers.Curation
  alias Gallformers.Sources
  alias Gallformers.Taxa
  alias GallformersWeb.FactKey
  alias GallformersWeb.GallNameParts

  @traits [
    {"Detachable", "detachable"},
    {"Color", "color"},
    {"Texture", "texture"},
    {"Shape", "shape"},
    {"Season", "season"},
    {"Alignment", "alignment"},
    {"Walls", "walls"},
    {"Location", "plant_part"},
    {"Form", "form"},
    {"Cells", "cells"}
  ]

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       dialog: nil,
       host_query: "",
       host_results: [],
       dialog_query: "",
       dialog_results: [],
       code_dialog: nil,
       note_dialog: nil,
       name_dialog: nil,
       observation_open: false,
       qualifier_query: "",
       qualifier_results: [],
       abundances: Catalog.list_abundances(),
       trait_options:
         Map.new(Catalog.identify_options(), fn {trait, values} ->
           {trait, Enum.map(values, & &1.value)}
         end)
     )}
  end

  @impl true
  def update(%{refresh: true}, socket), do: {:ok, socket |> load_record() |> load_pending()}

  def update(assigns, socket) do
    socket =
      socket
      |> assign(id: assigns.id, gall: assigns.gall, curator: assigns.curator)
      |> assign(photos_open: Map.get(assigns, :photos_open, false))
      |> assign(sources: source_labels(assigns.gall))
      |> load_record()
      |> load_pending()

    {:ok, socket}
  end

  # The Gall itself, for its editorial fields and their checks.
  defp load_record(socket) do
    record = Catalog.get_gall!(socket.assigns.gall.id)

    assign(socket,
      record: record,
      lock: Catalog.datacomplete_lock(record),
      lead_sources: Catalog.gall_sources(record.id)
    )
  end

  defp load_pending(socket) do
    %{curator: curator, gall: gall} = socket.assigns
    assign(socket, pending: Curation.pending_for(curator, {:gall, gall.id}))
  end

  # Each attributing Source's short label, by ID: "Weld (1959)", the first
  # author's surname and the year, else the title.
  defp source_labels(gall) do
    gall.attributions
    |> Map.values()
    |> List.flatten()
    |> Enum.map(& &1.source_id)
    |> Enum.uniq()
    |> Sources.list_sources_by_id()
    |> Map.new(&{&1.id, short_label(&1)})
  end

  defp short_label(%{author: author, pubyear: year}) when author not in [nil, ""] do
    surname = author |> String.split([",", " "], trim: true) |> List.first()
    if year in [nil, ""], do: surname, else: "#{surname} (#{year})"
  end

  defp short_label(source), do: source.title

  # -- events --------------------------------------------------------------------

  @impl true
  def handle_event("fact_action", %{"action" => "withdraw", "key" => key}, socket) do
    {:noreply, with_key(socket, key, &add(socket, %{action: :withdraw, key: &1}))}
  end

  def handle_event("fact_action", %{"action" => action, "key" => key}, socket)
      when action in ["correct", "note"] do
    {:noreply,
     with_key(socket, key, fn key ->
       assign(socket,
         dialog: %{action: String.to_existing_atom(action), key: key, label: label(socket, key)},
         dialog_query: "",
         dialog_results: []
       )
     end)}
  end

  def handle_event("close_dialog", _params, socket), do: {:noreply, assign(socket, dialog: nil)}

  def handle_event("note", %{"text" => text}, socket) do
    text = String.trim(text)
    %{dialog: %{key: key}, gall: gall} = socket.assigns

    if text == "" do
      {:noreply, socket}
    else
      socket = tray(socket, %{kind: :note, gall_id: gall.id, key: key, text: text})
      {:noreply, assign(socket, dialog: nil)}
    end
  end

  def handle_event("search_dialog_plant", %{"value" => query}, socket),
    do: {:noreply, assign(socket, dialog_query: query, dialog_results: plants(query))}

  def handle_event("select_dialog_plant", %{"id" => id}, socket) do
    %{dialog: %{key: key}} = socket.assigns
    socket = add(socket, %{action: :correct, key: key, to: {:host, String.to_integer(id)}})
    {:noreply, assign(socket, dialog: nil)}
  end

  def handle_event("clear_dialog_plant", _params, socket),
    do: {:noreply, assign(socket, dialog_query: "", dialog_results: [])}

  def handle_event("search_add_host", %{"value" => query}, socket),
    do: {:noreply, assign(socket, host_query: query, host_results: plants(query))}

  def handle_event("select_add_host", %{"id" => id}, socket) do
    socket = add(socket, %{action: :add, key: {:host, String.to_integer(id)}})
    {:noreply, assign(socket, host_query: "", host_results: [])}
  end

  def handle_event("clear_add_host", _params, socket),
    do: {:noreply, assign(socket, host_query: "", host_results: [])}

  def handle_event("add_trait", %{"trait" => trait, "value" => value}, socket)
      when value != "" do
    {:noreply, add(socket, %{action: :add, key: {:trait, trait, value}})}
  end

  def handle_event("add_trait", _params, socket), do: {:noreply, socket}

  def handle_event("add_common_name", %{"name" => name}, socket) do
    case String.trim(name) do
      "" -> {:noreply, socket}
      name -> {:noreply, add(socket, %{action: :add, key: {:alias, name}})}
    end
  end

  # -- the lead Source, photos and the ID note -----------------------------------------

  def handle_event("lead_source", %{"default_source_id" => ""}, socket),
    do: {:noreply, editorial(socket, :default_source_id, nil)}

  def handle_event("lead_source", %{"default_source_id" => id}, socket),
    do: {:noreply, editorial(socket, :default_source_id, String.to_integer(id))}

  # Open or closed in the URL (`?edit&photos`), so the photo viewer's Edit
  # photos link opens it too.
  def handle_event("open_photos", _params, socket),
    do: {:noreply, push_patch(socket, to: "/gall/#{socket.assigns.gall.id}?edit&photos")}

  def handle_event("close_photos", _params, socket),
    do: {:noreply, push_patch(socket, to: "/gall/#{socket.assigns.gall.id}?edit")}

  def handle_event("open_note", _params, socket), do: {:noreply, load_notes(socket)}

  # Add from observation (`GallformersWeb.ObservationIntake`), this Gall given.
  def handle_event("open_observation", _params, socket),
    do: {:noreply, assign(socket, observation_open: true)}

  def handle_event("close_observation", _params, socket),
    do: {:noreply, assign(socket, observation_open: false)}

  def handle_event("close_note", _params, socket),
    do: {:noreply, assign(socket, note_dialog: nil)}

  # The old admin Gall page's note logic, moved: each save a new version
  # dated today, as the Gallformers Source; an unchanged or blank one stores
  # nothing.
  def handle_event("save_note", %{"note" => %{"text" => text}}, socket) do
    current = socket.assigns.note_dialog.notes |> List.first() |> then(&(&1 && &1.text))

    cond do
      String.trim(text) == "" ->
        {:noreply, note_message(socket, :danger, "A note needs text.")}

      current && String.trim(text) == String.trim(current) ->
        {:noreply, note_message(socket, :info, "The note is unchanged; nothing was stored.")}

      true ->
        {:noreply, store_note(socket, text)}
    end
  end

  # -- editorial fields -------------------------------------------------------------

  def handle_event("completeness", %{"value" => value}, socket),
    do: {:noreply, editorial(socket, :completeness, value == "true")}

  def handle_event("abundance", %{"abundance" => ""}, socket),
    do: {:noreply, editorial(socket, :abundance, nil)}

  def handle_event("abundance", %{"abundance" => id}, socket),
    do: {:noreply, editorial(socket, :abundance, String.to_integer(id))}

  def handle_event("edit_code", _params, socket),
    do:
      {:noreply,
       assign(socket,
         code_dialog: code_state(socket, socket.assigns.record.gallformers_code || "")
       )}

  def handle_event("validate_code", %{"code" => code}, socket),
    do: {:noreply, assign(socket, code_dialog: code_state(socket, code))}

  def handle_event("save_code", %{"code" => code}, socket) do
    state = code_state(socket, code)

    if state.taken? do
      {:noreply, assign(socket, code_dialog: state)}
    else
      value = if state.code == "", do: nil, else: state.code
      {:noreply, socket |> editorial(:code, value) |> assign(code_dialog: nil)}
    end
  end

  def handle_event("close_code", _params, socket),
    do: {:noreply, assign(socket, code_dialog: nil)}

  def handle_event("edit_name", _params, socket) do
    qualifier = GallNameParts.qualifier(socket.assigns.record)

    {:noreply,
     socket
     |> assign(qualifier: qualifier, qualifier_query: "", qualifier_results: [])
     |> name_state(%{}, nil)}
  end

  def handle_event("validate_name", %{"name" => params}, socket),
    do: {:noreply, name_state(socket, params, :validate)}

  def handle_event("save_name", params, socket) do
    params = Map.get(params, "name", %{})
    socket = name_state(socket, params, :validate)

    if socket.assigns.name_dialog.preview.taken? do
      {:noreply, socket}
    else
      parts =
        params
        |> GallNameParts.attrs(socket.assigns.qualifier)
        |> Map.take(~w(form_label descriptor host_qualifier_taxon_id name_override))
        |> Map.new(fn {k, v} -> {k, blank_nil(v)} end)

      {:noreply, socket |> editorial(:name_parts, parts) |> assign(name_dialog: nil)}
    end
  end

  def handle_event("close_name", _params, socket),
    do: {:noreply, assign(socket, name_dialog: nil)}

  def handle_event("search_qualifier", %{"value" => query}, socket),
    do: {:noreply, assign(socket, qualifier_query: query, qualifier_results: plants(query))}

  def handle_event("select_qualifier", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.qualifier_results, &("#{&1.id}" == id)) do
      nil ->
        {:noreply, socket}

      plant ->
        socket
        |> assign(
          qualifier: %{id: plant.id, name: plant.name},
          qualifier_query: "",
          qualifier_results: []
        )
        |> name_state(socket.assigns.name_dialog.params, :validate)
        |> then(&{:noreply, &1})
    end
  end

  def handle_event("clear_qualifier", _params, socket) do
    socket
    |> assign(qualifier: nil, qualifier_query: "", qualifier_results: [])
    |> name_state(socket.assigns.name_dialog.params, :validate)
    |> then(&{:noreply, &1})
  end

  defp editorial(socket, field, value),
    do:
      tray(socket, %{
        kind: :editorial,
        subject: {:gall, socket.assigns.gall.id},
        field: field,
        value: value
      })

  # The code as typed, and whether another Gall has it (the admin page's check).
  defp code_state(socket, code) do
    code = String.trim(code)

    %{
      code: code,
      taken?: code != "" and Catalog.gallformers_code_taken?(code, socket.assigns.gall.id)
    }
  end

  defp name_state(socket, params, action) do
    {form, preview} =
      GallNameParts.form(socket.assigns.record, params, socket.assigns.qualifier, action)

    assign(socket, name_dialog: %{params: params, form: form, preview: preview})
  end

  defp blank_nil(value) when value in [nil, ""], do: nil
  defp blank_nil(value) when is_binary(value), do: String.trim(value)
  defp blank_nil(value), do: value

  defp load_notes(socket) do
    notes =
      for document <- Sources.list_gall_notes(socket.assigns.gall.id) do
        text = document |> Sources.list_document_items() |> Enum.map_join("\n\n", & &1.text)
        %{id: document.id, version_date: document.version_date, text: text}
      end

    current = notes |> List.first() |> then(&((&1 && &1.text) || ""))

    assign(socket,
      note_dialog: %{
        notes: notes,
        form: to_form(%{"text" => current}, as: :note),
        message: nil
      }
    )
  end

  defp note_message(socket, kind, text),
    do: assign(socket, note_dialog: %{socket.assigns.note_dialog | message: {kind, text}})

  defp store_note(socket, text) do
    %{curator: curator, gall: gall} = socket.assigns

    with %{} = gallformers <- Sources.get_gallformers_source(),
         {:ok, document} <-
           Sources.store_note(curator, gallformers, gall.id, text, Date.utc_today()) do
      socket = load_notes(socket)

      case socket.assigns.note_dialog.notes do
        [%{id: id} | _] when id == document.id ->
          note_message(socket, :ok, "Saved as a new version.")

        _ ->
          note_message(
            socket,
            :warn,
            "That text is an earlier version's; Sources keep each text once, so nothing new was stored."
          )
      end
    else
      nil ->
        note_message(socket, :danger, "There is no Gallformers Source to hold the note.")

      {:error, reason} ->
        note_message(socket, :danger, "The note couldn't be stored: #{inspect(reason)}.")
    end
  end

  defp with_key(socket, text, fun) do
    case FactKey.decode(text) do
      {:ok, key} -> fun.(key)
      :error -> socket
    end
  end

  defp add(socket, spec),
    do: tray(socket, Map.merge(%{kind: :fact, gall_id: socket.assigns.gall.id}, spec))

  defp tray(socket, spec) do
    case Curation.add_item(socket.assigns.curator, spec) do
      {:ok, _item} -> load_pending(socket)
      {:error, reason} -> put_flash(socket, :error, refusal(reason))
    end
  end

  defp refusal(:waiting), do: "That change is already waiting to apply."
  defp refusal(:no_fact), do: "There is no such Fact on this Gall."
  defp refusal(:no_such_taxon), do: "That plant isn't in Gallformers."
  defp refusal(:invalid_value), do: "That value isn't one of the Trait's."
  defp refusal(reason), do: "The change couldn't go in your tray (#{reason})."

  defp plants(query) do
    if String.length(String.trim(query)) >= 2, do: Taxa.search_plants(query, 20), else: []
  end

  defp label(socket, {:host, id}), do: "host " <> host_name(socket.assigns.gall, id)
  defp label(socket, {:inducer, id}), do: "inducer " <> inducer_name(socket.assigns.gall, id)
  defp label(_socket, {:trait, trait, value}), do: "#{trait}: #{value}"
  defp label(_socket, key), do: FactKey.encode(key)

  defp host_name(gall, id),
    do: Enum.find_value(gall.hosts, &(&1.taxon_id == id && &1.name)) || Taxa.accepted_name(id)

  defp inducer_name(gall, id),
    do: Enum.find_value(gall.inducers, &(&1.taxon_id == id && &1.name)) || Taxa.accepted_name(id)

  # -- what the page shows ---------------------------------------------------------

  # The tray's mark for a key: its Fact item's action, else a note's.
  defp pending(pending, key) do
    case Map.get(pending, key, []) do
      [] ->
        nil

      items ->
        item = Enum.find(items, &(&1.kind == :fact)) || hd(items)
        action = if item.kind == :fact, do: item.spec.action, else: :note
        %{action: action, state: item.state}
    end
  end

  # Hosts and Trait values the tray adds that the Gall doesn't have yet.
  defp added(pending, match) do
    for {key, items} <- pending,
        match.(key),
        Enum.any?(items, &(&1.kind == :fact and &1.spec.action == :add)),
        do: key
  end

  defp sources(%{gall: gall, sources: labels}, key) do
    gall.attributions
    |> Map.get(key, [])
    |> Enum.map(&labels[&1.source_id])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp traits, do: @traits

  @impl true
  def render(assigns) do
    host_ids = MapSet.new(assigns.gall.hosts, & &1.taxon_id)
    values = assigns.gall.traits

    assigns =
      assign(assigns,
        added_hosts:
          added(assigns.pending, fn
            {:host, id} -> not MapSet.member?(host_ids, id)
            _ -> false
          end),
        added_names:
          added(assigns.pending, fn
            {:alias, name} -> name not in assigns.gall.common_names
            _ -> false
          end),
        added_values: fn trait ->
          added(assigns.pending, fn
            {:trait, ^trait, value} -> value not in Map.get(values, trait, [])
            _ -> false
          end)
        end
      )

    ~H"""
    <div id={@id} class="flex flex-col gap-section">
      <.panel id="editorial" title="Editorial">
        <div class="flex flex-wrap items-start gap-x-8 gap-y-4 text-ui">
          <div id="editorial-completeness" class="flex max-w-xs flex-col gap-1">
            <span class="gf-label">Completeness</span>
            <div class="flex flex-wrap items-center gap-2">
              <span>{if @record.datacomplete, do: "Complete", else: "In progress"}</span>
              <.button
                size="sm"
                variant="secondary"
                phx-click="completeness"
                phx-value-value={to_string(!@record.datacomplete)}
                phx-target={@myself}
                disabled={!@record.datacomplete and @lock != :unlocked}
              >
                Mark {if @record.datacomplete, do: "in progress", else: "complete"}
              </.button>
              <.tray_mark pending={@pending} field={:completeness} />
            </div>
            <p :if={!@record.datacomplete and @lock != :unlocked} class="gf-hint">
              It can't be complete: {lock_reason(@lock)}.
            </p>
          </div>

          <form
            id="editorial-abundance"
            phx-change="abundance"
            phx-target={@myself}
            class="flex flex-col gap-1"
          >
            <label class="gf-label" for="editorial-abundance-select">Abundance</label>
            <div class="flex flex-wrap items-center gap-2">
              <select id="editorial-abundance-select" name="abundance" class="gf-select h-8 w-auto">
                <option value="">Unknown</option>
                <option
                  :for={a <- @abundances}
                  value={a.id}
                  selected={a.id == @record.abundance_id}
                >
                  {a.abundance}
                </option>
              </select>
              <.tray_mark pending={@pending} field={:abundance} />
            </div>
          </form>

          <div id="editorial-code" class="flex flex-col gap-1">
            <span class="gf-label">Gallformers code</span>
            <div class="flex flex-wrap items-center gap-2">
              <span class="font-mono">{@record.gallformers_code || "None"}</span>
              <.button size="sm" variant="secondary" phx-click="edit_code" phx-target={@myself}>
                Change…
              </.button>
              <.tray_mark pending={@pending} field={:code} />
            </div>
          </div>

          <div id="editorial-name" class="flex flex-col gap-1">
            <span class="gf-label">Name</span>
            <div class="flex flex-wrap items-center gap-2">
              <.button size="sm" variant="secondary" phx-click="edit_name" phx-target={@myself}>
                Name parts…
              </.button>
              <.tray_mark pending={@pending} field={:name_parts} />
            </div>
          </div>

          <form
            id="editorial-lead"
            phx-change="lead_source"
            phx-target={@myself}
            class="flex flex-col gap-1"
          >
            <label class="gf-label" for="editorial-lead-source">Lead Source</label>
            <div class="flex flex-wrap items-center gap-2">
              <select
                id="editorial-lead-source"
                name="default_source_id"
                class="gf-select h-8 w-auto max-w-xs"
              >
                <option value="">None</option>
                <option
                  :for={source <- @lead_sources}
                  value={source.id}
                  selected={source.id == @record.default_source_id}
                >
                  {source.title}
                </option>
              </select>
              <.tray_mark pending={@pending} field={:default_source_id} />
            </div>
          </form>
        </div>
        <div class="mt-block flex flex-wrap gap-2 border-t border-line pt-block">
          <.button
            size="sm"
            variant="secondary"
            icon="ph-image"
            phx-click="open_photos"
            phx-target={@myself}
          >
            Photos…
          </.button>
          <.button
            size="sm"
            variant="secondary"
            icon="ph-article"
            phx-click="open_note"
            phx-target={@myself}
          >
            ID note…
          </.button>
          <.button size="sm" variant="secondary" icon="ph-map-trifold" phx-click="open_range">
            Range exclusions…
          </.button>
        </div>
      </.panel>

      <.panel
        :if={@photos_open}
        id="photos-panel"
        title="Photos"
        tabindex="-1"
        phx-mounted={JS.focus()}
        class="focus:outline-none"
      >
        <:header_action>
          <.button variant="ghost" size="sm" phx-click="close_photos" phx-target={@myself}>
            Done
          </.button>
        </:header_action>
        <p class="mb-block text-ui text-ink-2">
          Photos save as you change them; they don't go through the tray.
        </p>
        <.live_component
          module={GallformersWeb.Admin.ImagesComponent}
          id="photos-manager"
          owner={{:gall, @gall.id}}
          uploader={@curator.name}
          name={@gall.name}
        />
      </.panel>

      <.section title="Inducer">
        <ul :if={@gall.inducers != []} class="flex flex-col divide-y divide-line">
          <.fact_row
            :for={inducer <- @gall.inducers}
            fact_key={{:inducer, inducer.taxon_id}}
            sources={sources(assigns, {:inducer, inducer.taxon_id})}
            actions={[:note]}
            pending={pending(@pending, {:inducer, inducer.taxon_id})}
            target={@myself}
          >
            <.taxon_name name={inducer.name} />
          </.fact_row>
        </ul>
        <p :if={@gall.inducers == []} class="text-ui text-muted">
          No Inducer recorded: the Gall is undescribed.
        </p>
        <.edit_scope
          :if={@gall.inducers != []}
          kind={:elsewhere}
          href={"/admin/taxonomy/#{hd(@gall.inducers).taxon_id}"}
        >
          Correcting the Inducer is taxonomy: on <i>{hd(@gall.inducers).name}</i>'s page.
        </.edit_scope>
      </.section>

      <.section title="Hosts" count={length(@gall.hosts)}>
        <ul class="flex flex-col divide-y divide-line">
          <.fact_row
            :for={host <- @gall.hosts}
            fact_key={{:host, host.taxon_id}}
            sources={sources(assigns, {:host, host.taxon_id})}
            pending={pending(@pending, {:host, host.taxon_id})}
            target={@myself}
          >
            <.taxon_name name={host.name} genus_placeholder={host.rank == :genus} />
          </.fact_row>
          <.fact_row
            :for={{:host, id} = key <- @added_hosts}
            fact_key={key}
            pending={pending(@pending, key)}
            target={@myself}
          >
            <.taxon_name name={Taxa.accepted_name(id)} />
          </.fact_row>
        </ul>
        <.typeahead
          id="add-host"
          label="Add a host"
          placeholder="A plant's name"
          query={@host_query}
          results={@host_results}
          search_event="search_add_host"
          select_event="select_add_host"
          clear_event="clear_add_host"
          display_fn={& &1.name}
          target={@myself}
          class="mt-2 max-w-md"
        >
          <:result :let={plant}><.taxon_name name={plant.name} /></:result>
        </.typeahead>
      </.section>

      <.section title="Common names" count={length(@gall.common_names)}>
        <ul class="flex flex-col divide-y divide-line">
          <.fact_row
            :for={name <- @gall.common_names}
            fact_key={{:alias, name}}
            sources={sources(assigns, {:alias, name})}
            actions={[:withdraw, :note]}
            pending={pending(@pending, {:alias, name})}
            target={@myself}
          >
            {name}
          </.fact_row>
          <.fact_row
            :for={{:alias, name} = key <- @added_names}
            fact_key={key}
            pending={pending(@pending, key)}
            target={@myself}
          >
            {name}
          </.fact_row>
        </ul>
        <form
          id="add-common-name"
          phx-submit="add_common_name"
          phx-target={@myself}
          class="mt-2 flex max-w-md items-end gap-2"
        >
          <div class="min-w-0 flex-1">
            <label class="gf-label" for="add-common-name-name">Add a common name</label>
            <input id="add-common-name-name" name="name" class="gf-input" autocomplete="off" />
          </div>
          <.button type="submit" variant="secondary">Add</.button>
        </form>
      </.section>

      <.section id="gall-traits-section" title="Traits">
        <dl class="flex flex-col divide-y divide-line text-ui">
          <div
            :for={{label, trait} <- traits()}
            class="flex flex-wrap items-center gap-x-3 gap-y-1.5 py-1.5"
          >
            <dt class="w-24 shrink-0 text-meta text-muted">{label}</dt>
            <dd class="flex flex-1 flex-wrap items-center gap-1.5">
              <.fact_chip
                :for={value <- Map.get(@gall.traits, trait, [])}
                fact_key={{:trait, trait, value}}
                sources={sources(assigns, {:trait, trait, value})}
                pending={pending(@pending, {:trait, trait, value})}
                target={@myself}
              >
                {value}
              </.fact_chip>
              <.fact_chip
                :for={key <- @added_values.(trait)}
                fact_key={key}
                pending={pending(@pending, key)}
              >
                {elem(key, 2)}
              </.fact_chip>
              <form id={"add-trait-#{trait}"} phx-change="add_trait" phx-target={@myself}>
                <input type="hidden" name="trait" value={trait} />
                <select
                  name="value"
                  class="gf-select h-7 w-auto text-meta"
                  aria-label={"Add a #{label} value"}
                >
                  <option value="">+ Add</option>
                  <option
                    :for={v <- Map.get(@trait_options, trait, []) -- Map.get(@gall.traits, trait, [])}
                    value={v}
                  >
                    {v}
                  </option>
                </select>
              </form>
            </dd>
          </div>
        </dl>
      </.section>

      <.dialog
        :if={@observation_open}
        id="observation-dialog"
        title="Add from observation"
        size={:lg}
        show
        on_cancel={JS.push("close_observation", target: @myself)}
      >
        <.live_component
          module={GallformersWeb.ObservationIntake}
          id="observation-intake"
          curator={@curator}
          gall={%{id: @gall.id, name: @gall.name}}
        />
        <:actions>
          <.button
            type="button"
            variant="secondary"
            phx-click="close_observation"
            phx-target={@myself}
          >
            Done
          </.button>
        </:actions>
      </.dialog>

      <.dialog
        :if={@note_dialog}
        id="note-dialog"
        title="Gallformers ID note"
        size={:lg}
        show
        on_cancel={JS.push("close_note", target: @myself)}
      >
        <div class="flex flex-col gap-block">
          <p class="text-ui text-ink-2">
            Gallformers' own ID notes on this Gall. Each save is a new version dated today; the Gall page shows the newest. Notes save at once; they don't go through the tray.
          </p>
          <.notice :if={@note_dialog.message} kind={elem(@note_dialog.message, 0)}>
            {elem(@note_dialog.message, 1)}
          </.notice>
          <.form
            for={@note_dialog.form}
            id="note-form"
            phx-submit="save_note"
            phx-target={@myself}
            class="flex flex-col gap-2"
          >
            <.input
              field={@note_dialog.form[:text]}
              type="textarea"
              label="Note (Markdown)"
              rows="10"
            />
            <div class="flex justify-end">
              <.button type="submit" variant="primary">Save note</.button>
            </div>
          </.form>
          <.section :if={@note_dialog.notes != []} title="Versions, newest first" level={3}>
            <ol id="note-versions" class="flex flex-col gap-2">
              <li
                :for={{note, index} <- Enum.with_index(@note_dialog.notes)}
                id={"note-version-#{note.id}"}
                class="rounded-panel border border-line p-panel"
              >
                <div class="mb-1 flex items-center gap-2 text-meta text-muted">
                  {if note.version_date, do: note.version_date, else: "Undated (carried over)"}
                  <.chip :if={index == 0} variant={:ok} size="sm">Current</.chip>
                </div>
                <div class="whitespace-pre-wrap text-ui text-ink-2">{note.text}</div>
              </li>
            </ol>
          </.section>
        </div>
      </.dialog>

      <.dialog
        :if={@code_dialog}
        id="code-dialog"
        title="Change the Gallformers code"
        size={:sm}
        show
        on_cancel={JS.push("close_code", target: @myself)}
      >
        <form
          id="code-form"
          phx-change="validate_code"
          phx-submit="save_code"
          phx-target={@myself}
          class="flex flex-col gap-block"
        >
          <p class="text-ui text-ink-2">
            iNaturalist observations and other sites link to this Gall by its code: a new code breaks the links made with the old one. You'll be asked to confirm when you apply.
          </p>
          <div>
            <label class="gf-label" for="code-dialog-code">Code</label>
            <input
              id="code-dialog-code"
              name="code"
              value={@code_dialog.code}
              class={["gf-input font-mono", @code_dialog.taken? && "gf-input-error"]}
              autocomplete="off"
              phx-debounce="300"
            />
            <p :if={@code_dialog.taken?} class="mt-1 text-meta text-danger">
              “{@code_dialog.code}” is already used by another Gall.
            </p>
            <p class="gf-hint">Leave it blank to remove the code.</p>
          </div>
          <div class="flex justify-end gap-2">
            <.button type="button" variant="ghost" phx-click="close_code" phx-target={@myself}>
              Cancel
            </.button>
            <.button type="submit" variant="primary" disabled={@code_dialog.taken?}>
              Add to tray
            </.button>
          </div>
        </form>
      </.dialog>

      <.dialog
        :if={@name_dialog}
        id="name-dialog"
        title="The name's parts"
        show
        on_cancel={JS.push("close_name", target: @myself)}
      >
        <div class="flex flex-col gap-block">
          <p class="text-ui text-ink-2">
            The name is derived from the Gall's Inducer, its generation and these parts. An override replaces the name shown.
          </p>
          <dl class="flex flex-col gap-1 text-ui">
            <div class="flex flex-wrap gap-2">
              <dt class="text-muted">Derived name</dt>
              <dd>
                <%= case @name_dialog.preview.derived do %>
                  <% {:ok, derived} -> %>
                    <em id="derived-name">{derived}</em>
                  <% {:error, reason} -> %>
                    <span id="derived-name" class="text-warn">
                      none: {GallNameParts.derive_error(reason)}; give a name override
                    </span>
                <% end %>
              </dd>
            </div>
            <div class="flex flex-wrap gap-2">
              <dt class="text-muted">Name shown</dt>
              <dd><em id="name-shown">{@name_dialog.preview.shown}</em></dd>
            </div>
          </dl>
          <p :if={@name_dialog.preview.taken?} id="name-collision" class="text-ui text-danger">
            “{@name_dialog.preview.shown}” is already the name of another Gall.
          </p>
          <.typeahead
            id="name-dialog-qualifier"
            label="Host qualifier (written “on” the plant)"
            placeholder="A plant's name"
            query={@qualifier_query}
            results={@qualifier_results}
            selected={@qualifier}
            search_event="search_qualifier"
            select_event="select_qualifier"
            clear_event="clear_qualifier"
            display_fn={& &1.name}
            target={@myself}
          />
          <.form
            for={@name_dialog.form}
            id="name-dialog-form"
            phx-change="validate_name"
            phx-submit="save_name"
            phx-target={@myself}
            class="flex flex-col gap-block"
          >
            <div class="grid grid-cols-1 gap-block md:grid-cols-2">
              <.input
                field={@name_dialog.form[:form_label]}
                label="Form label"
                placeholder="e.g. bud, australis"
              />
              <.input
                field={@name_dialog.form[:descriptor]}
                label="Descriptor (undescribed Galls)"
                placeholder="e.g. q-havardii-cup-gall"
              />
            </div>
            <.input field={@name_dialog.form[:name_override]} label="Name override" />
            <p :for={message <- GallNameParts.errors(@name_dialog.form)} class="text-meta text-danger">
              Name {message}
            </p>
            <div class="flex justify-end gap-2">
              <.button type="button" variant="ghost" phx-click="close_name" phx-target={@myself}>
                Cancel
              </.button>
              <.button type="submit" variant="primary" disabled={@name_dialog.preview.taken?}>
                Add to tray
              </.button>
            </div>
          </.form>
        </div>
      </.dialog>

      <.dialog
        :if={@dialog}
        id="fact-dialog"
        title={dialog_title(@dialog)}
        show
        on_cancel={JS.push("close_dialog", target: @myself)}
      >
        <.typeahead
          :if={@dialog.action == :correct}
          id="fact-dialog-plant"
          label="The plant it should be"
          placeholder="A plant's name"
          query={@dialog_query}
          results={@dialog_results}
          search_event="search_dialog_plant"
          select_event="select_dialog_plant"
          clear_event="clear_dialog_plant"
          display_fn={& &1.name}
          target={@myself}
        >
          <:result :let={plant}><.taxon_name name={plant.name} /></:result>
        </.typeahead>
        <form
          :if={@dialog.action == :note}
          id="fact-dialog-note"
          phx-submit="note"
          phx-target={@myself}
          class="flex flex-col gap-block"
        >
          <div>
            <label class="gf-label" for="fact-dialog-note-text">Note</label>
            <textarea id="fact-dialog-note-text" name="text" rows="3" class="gf-textarea"></textarea>
            <p class="gf-hint">Shown with the Fact. A note doesn't change what the Fact says.</p>
          </div>
          <div class="flex justify-end gap-2">
            <.button type="button" variant="ghost" phx-click="close_dialog" phx-target={@myself}>
              Cancel
            </.button>
            <.button type="submit" variant="primary">Add to tray</.button>
          </div>
        </form>
      </.dialog>
    </div>
    """
  end

  attr :pending, :map, required: true
  attr :field, :atom, required: true

  # "in your tray" beside an editorial field with an item in the tray, the
  # item's words as its title.
  defp tray_mark(assigns) do
    assigns =
      assign(
        assigns,
        :item,
        assigns.pending |> Map.get({:editorial, assigns.field}, []) |> List.first()
      )

    ~H"""
    <span :if={@item} data-part="pending" title={@item.text}>
      <.chip variant={:info} size="sm">in your tray</.chip>
    </span>
    """
  end

  defp lock_reason({:locked, :no_sources}), do: "it has no Sources yet"
  defp lock_reason({:locked, :undescribed}), do: "it's undescribed (no species-rank Inducer)"

  defp dialog_title(%{action: :correct, label: label}), do: "Correct the #{label}"
  defp dialog_title(%{action: :note, label: label}), do: "A note on the #{label}"
end
