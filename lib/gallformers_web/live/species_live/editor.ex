defmodule GallformersWeb.SpeciesLive.Editor do
  @moduledoc """
  Edit mode's Names and placement panel on a species page (`GallformersWeb.SpeciesLive`,
  matter `803b`, "The species page"): the organism's name (with its rank
  and authorship), its placement, its synonyms and its common names, each a
  row of one list, label beside value and actions (as the Host page's
  Editorial panel sets its rows).

  Outside Plantae the tree follows the Sources' statements (matter `f923`),
  so every change asks "Based on which Source?" before it is made
  (`GallformersWeb.Admin.TaxonomyLive.TaxonChanges` builds it, the
  `GallformersWeb.Admin.TaxonomyLive.BasisPicker` dialog asks, and the page
  runs it on the Source chosen): nothing goes into the change tray.

  The page holds the state and forwards the events in `events/0`
  (`handle_event/3`).
  """
  use GallformersWeb, :html

  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank
  alias GallformersWeb.Admin.TaxonomyLive.BasisPicker
  alias GallformersWeb.Admin.TaxonomyLive.TaxonChanges
  alias Phoenix.LiveView.Socket

  @events ~w(open_name close_name rename open_synonym close_synonym add_synonym
             remove_synonym open_common_name close_common_name add_common_name
             remove_common_name open_move close_move search_parent select_parent
             clear_parent move cancel_basis)

  @doc "The events the page forwards to `handle_event/3`."
  @spec events() :: [String.t()]
  def events, do: @events

  @doc "The editor's assigns, nothing open, and the dialog's (`BasisPicker.init/1`)."
  @spec init(Socket.t()) :: Socket.t()
  def init(socket) do
    socket
    |> BasisPicker.init()
    |> Phoenix.Component.assign(
      editor_open: nil,
      parent_query: "",
      parent_results: [],
      selected_parent: nil
    )
  end

  @doc "Closes whatever form the editor has open."
  @spec close(Socket.t()) :: Socket.t()
  def close(socket) do
    Phoenix.Component.assign(socket,
      editor_open: nil,
      parent_query: "",
      parent_results: [],
      selected_parent: nil
    )
  end

  @doc """
  One of the editor's events (`events/0`) on the page's socket, which has
  `species` (`Gallformers.Taxa.ReadModels.SpeciesPage`).
  """
  @spec handle_event(String.t(), map(), Socket.t()) :: Socket.t()
  def handle_event(open, _params, socket)
      when open in ~w(open_name open_synonym open_common_name open_move) do
    socket |> close() |> Phoenix.Component.assign(editor_open: String.replace(open, "open_", ""))
  end

  def handle_event(closing, _params, socket)
      when closing in ~w(close_name close_synonym close_common_name close_move),
      do: close(socket)

  def handle_event("rename", %{"rename" => %{"name" => name} = params}, socket) do
    %{species: species} = socket.assigns

    case String.trim(name) do
      "" ->
        socket

      name ->
        socket
        |> close()
        |> TaxonChanges.name(Taxa.get_taxon!(species.id), species.name, name, params)
    end
  end

  def handle_event("add_synonym", %{"synonym" => %{"name" => name}}, socket) do
    %{species: species} = socket.assigns

    case String.trim(name) do
      "" -> socket
      name -> socket |> close() |> TaxonChanges.add_synonym(species.id, name, species.name)
    end
  end

  def handle_event("remove_synonym", %{"id" => id}, socket) do
    %{species: species} = socket.assigns
    id = String.to_integer(id)
    name = Enum.find_value(species.synonyms, &(&1.id == id && &1.name))
    TaxonChanges.remove_synonym(socket, id, name, species.name)
  end

  def handle_event("add_common_name", %{"common_name" => %{"name" => name}}, socket) do
    %{species: species} = socket.assigns

    case String.trim(name) do
      "" -> socket
      name -> socket |> close() |> TaxonChanges.add_common_name(species.id, name, species.name)
    end
  end

  def handle_event("remove_common_name", %{"id" => id}, socket) do
    %{species: species} = socket.assigns
    id = String.to_integer(id)
    name = Enum.find_value(species.common_names, &(&1.id == id && &1.name))
    TaxonChanges.remove_common_name(socket, id, name, species.name)
  end

  def handle_event("search_parent", %{"value" => query}, socket) do
    taxon = Taxa.get_taxon!(socket.assigns.species.id)

    Phoenix.Component.assign(socket,
      parent_query: query,
      parent_results: TaxonChanges.parent_candidates(taxon, query)
    )
  end

  def handle_event("select_parent", %{"id" => id}, socket) do
    selected = Enum.find(socket.assigns.parent_results, &(&1.id == String.to_integer(id)))

    Phoenix.Component.assign(socket,
      selected_parent: selected,
      parent_query: "",
      parent_results: []
    )
  end

  def handle_event("clear_parent", _params, socket),
    do:
      Phoenix.Component.assign(socket, selected_parent: nil, parent_query: "", parent_results: [])

  def handle_event("move", _params, socket) do
    %{species: species, selected_parent: parent} = socket.assigns

    case parent do
      nil -> socket
      parent -> socket |> close() |> TaxonChanges.move(species.id, species.name, parent)
    end
  end

  def handle_event("cancel_basis", _params, socket), do: BasisPicker.cancel(socket)

  # -- render ----------------------------------------------------------------

  @doc """
  The Names and placement panel: Name, Placement, Synonyms and Common names, each with
  its actions; the open form under its row; the rename dialog.
  """
  attr :species, :map, required: true
  attr :parent, :map, default: nil, doc: "the taxon it is placed under (a lineage entry)"
  attr :open, :string, default: nil, doc: "the form open: name, synonym, common_name, move"
  attr :parent_query, :string, default: ""
  attr :parent_results, :list, default: []
  attr :selected_parent, :map, default: nil

  def editor(assigns) do
    ~H"""
    <div id="species-editor">
      <.panel id="species-editorial" title="Names and placement">
        <dl class="flex flex-col divide-y divide-line text-ui">
          <div id="species-editor-name" class="flex flex-wrap items-baseline gap-x-3 gap-y-1 py-1.5">
            <dt class="w-28 shrink-0 text-meta text-muted">Name</dt>
            <dd class="flex min-w-0 flex-1 flex-wrap items-baseline gap-x-3 gap-y-1">
              <span class="min-w-0 flex-1">
                <.taxon_name name={@species.name} />
                <span :if={@species.authorship} class="text-ink-2">{@species.authorship}</span>
                <span class="text-meta text-muted">· {rank_label(@species.rank)}</span>
              </span>
              <.button variant="ghost" size="sm" phx-click="open_name">Rename…</.button>
            </dd>
          </div>

          <div
            id="species-editor-placement"
            class="flex flex-wrap items-baseline gap-x-3 gap-y-1 py-1.5"
          >
            <dt class="w-28 shrink-0 text-meta text-muted">Placed under</dt>
            <dd class="flex min-w-0 flex-1 flex-col gap-1">
              <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                <span class="min-w-0 flex-1">
                  <.taxon_name :if={@parent} name={@parent.name} rank={name_rank(@parent.rank)} />
                  <span :if={@parent} class="text-meta text-muted">
                    · {rank_label(@parent.rank)}
                  </span>
                  <span :if={!@parent} class="text-muted">Not placed under any taxon.</span>
                </span>
                <.button :if={@open != "move"} variant="ghost" size="sm" phx-click="open_move">
                  Move…
                </.button>
              </div>
              <div :if={@open == "move"} class="flex max-w-md flex-col gap-2 py-1">
                <.typeahead
                  id="species-parent-picker"
                  label="Move under"
                  placeholder="Search for the new genus..."
                  search_event="search_parent"
                  select_event="select_parent"
                  clear_event="clear_parent"
                  query={@parent_query}
                  results={@parent_results}
                  selected={@selected_parent}
                  display_fn={fn p -> "#{p.name} (#{p.rank})" end}
                >
                  <:result :let={parent}>
                    <.taxon_name name={parent.name} rank={name_rank(parent.rank)} />
                    <span class="ml-1 text-caption text-muted">({parent.rank})</span>
                  </:result>
                </.typeahead>
                <div class="flex gap-2">
                  <.button
                    id="species-move-button"
                    size="sm"
                    variant="primary"
                    phx-click="move"
                    disabled={is_nil(@selected_parent)}
                  >
                    Move
                  </.button>
                  <.button size="sm" variant="ghost" phx-click="close_move">Cancel</.button>
                </div>
              </div>
            </dd>
          </div>

          <div
            id="species-editor-synonyms"
            class="flex flex-wrap items-baseline gap-x-3 gap-y-1 py-1.5"
          >
            <dt class="w-28 shrink-0 text-meta text-muted">Synonyms</dt>
            <dd class="flex min-w-0 flex-1 flex-col gap-1">
              <.name_rows
                names={@species.synonyms}
                remove_event="remove_synonym"
                empty="No synonyms."
                italic
              />
              <.button
                :if={@open != "synonym"}
                variant="ghost"
                size="sm"
                icon="ph-plus"
                phx-click="open_synonym"
                class="self-start"
              >
                Add a synonym
              </.button>
              <.form
                :if={@open == "synonym"}
                for={%{}}
                as={:synonym}
                id="species-synonym-form"
                phx-submit="add_synonym"
                class="flex max-w-md flex-col gap-2 py-1"
              >
                <.input
                  id="species-synonym-name"
                  name="synonym[name]"
                  value=""
                  label="Synonym"
                  autocomplete="off"
                  phx-mounted={JS.focus()}
                />
                <div class="flex gap-2">
                  <.button type="submit" size="sm" variant="primary">Add synonym…</.button>
                  <.button type="button" size="sm" variant="ghost" phx-click="close_synonym">
                    Cancel
                  </.button>
                </div>
              </.form>
            </dd>
          </div>

          <div
            id="species-editor-common-names"
            class="flex flex-wrap items-baseline gap-x-3 gap-y-1 py-1.5"
          >
            <dt class="w-28 shrink-0 text-meta text-muted">Common names</dt>
            <dd class="flex min-w-0 flex-1 flex-col gap-1">
              <.name_rows
                names={@species.common_names}
                remove_event="remove_common_name"
                empty="No common names."
              />
              <.button
                :if={@open != "common_name"}
                variant="ghost"
                size="sm"
                icon="ph-plus"
                phx-click="open_common_name"
                class="self-start"
              >
                Add a common name
              </.button>
              <.form
                :if={@open == "common_name"}
                for={%{}}
                as={:common_name}
                id="species-common-name-form"
                phx-submit="add_common_name"
                class="flex max-w-md flex-col gap-2 py-1"
              >
                <.input
                  id="species-common-name"
                  name="common_name[name]"
                  value=""
                  label="Common name"
                  autocomplete="off"
                  phx-mounted={JS.focus()}
                />
                <div class="flex gap-2">
                  <.button type="submit" size="sm" variant="primary">Add common name…</.button>
                  <.button type="button" size="sm" variant="ghost" phx-click="close_common_name">
                    Cancel
                  </.button>
                </div>
              </.form>
            </dd>
          </div>
        </dl>
        <:footer>
          <p class="text-meta text-ink-2">
            The tree follows the Sources' statements: each change asks which Source it follows before it is made.
          </p>
        </:footer>
      </.panel>

      <.dialog
        :if={@open == "name"}
        id="species-name-dialog"
        title={"Rename #{@species.name}"}
        size={:sm}
        show
        on_cancel={JS.push("close_name")}
      >
        <.form
          for={%{}}
          as={:rename}
          id="species-name-form"
          phx-submit="rename"
          class="flex flex-col gap-block"
        >
          <.input
            id="species-new-name"
            name="rename[name]"
            value={@species.name}
            label="Accepted name"
          />
          <.input
            id="species-new-rank"
            name="rename[rank]"
            type="select"
            label="Rank"
            options={TaxonChanges.rank_options()}
            value={Atom.to_string(@species.rank)}
          />
          <.input
            id="species-new-authorship"
            name="rename[authorship]"
            value={@species.authorship || ""}
            label="Authorship"
            placeholder="(Weld, 1959)"
          />
          <p class="gf-hint">The old name is kept as a synonym.</p>
        </.form>
        <:actions>
          <.button type="button" variant="ghost" phx-click="close_name">Cancel</.button>
          <.button type="submit" form="species-name-form" variant="primary">Change…</.button>
        </:actions>
      </.dialog>
    </div>
    """
  end

  attr :names, :list, required: true, doc: "`%{id, name}` (a synonym also `sensu`)"
  attr :remove_event, :string, required: true
  attr :empty, :string, required: true
  attr :italic, :boolean, default: false

  defp name_rows(assigns) do
    ~H"""
    <ul :if={@names != []} class="flex flex-col">
      <li :for={n <- @names} class="flex flex-wrap items-baseline gap-x-3">
        <span class="min-w-0 flex-1">
          <.taxon_name :if={@italic} name={n.name} />
          <span :if={!@italic}>{n.name}</span>
          <span :if={n[:sensu]} class="text-meta text-muted">sensu {n.sensu}</span>
        </span>
        <.button
          variant="ghost"
          size="sm"
          phx-click={@remove_event}
          phx-value-id={n.id}
          aria-label={"Take out #{n.name}"}
        >
          Take out…
        </.button>
      </li>
    </ul>
    <p :if={@names == []} class="text-muted">{@empty}</p>
    """
  end

  defp rank_label(rank), do: TaxonChanges.rank_label(rank)

  # Names at species rank and below are italicized like a species.
  defp name_rank(rank) do
    if rank in Rank.species_and_below(),
      do: "species",
      else: Atom.to_string(rank)
  end
end
