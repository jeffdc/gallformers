defmodule GallformersWeb.Admin.TaxonomyLive.BasisPicker do
  @moduledoc """
  "Based on which Source?" (matter `f923` Task 8): the dialog the taxonomy
  admin opens before a change to a non-plant taxon (a move, a name, a
  synonym or common name, a new taxon), since the tree follows the Sources'
  accepted statements and a change is credited to the Source it follows.
  Three options, each with what choosing it does, and the input it needs
  shown once it is chosen:

    * **A Source in Gallformers** (recommended) — found by title or
      author (`Gallformers.Sources.search_sources/1`; Gallformers' own and
      retracted Sources left out). The last Source used on the page is
      chosen to start with.
    * **A new citation** — the paper's title, authors and date (DOI
      optional), made a Source with the change.
    * **No Source: Gallformers' own position** — the rare exception, with
      the reason.

  On confirm it sends the page `{GallformersWeb.Admin.TaxonomyLive.BasisPicker,
  {:chosen, basis}}` (`Gallformers.Import.record_taxonomy_change/3`'s
  basis); the page makes the change and closes the dialog, or passes back
  `error` (`:warn` when the tree won't follow it: an accepted newer paper
  decides it) to show here. The page's `cancel_event` closes it.
  """
  use GallformersWeb, :live_component

  import GallformersWeb.ReviewComponents, only: [review_option: 1]

  alias Gallformers.Sources
  alias GallformersWeb.Admin.TaxonomyLive.Errors

  @source_results 20

  # -- the page's side ---------------------------------------------------------

  @doc """
  The page's assigns for the dialog: no change pending, no error, no Source
  used yet.
  """
  @spec init(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def init(socket),
    do: assign(socket, pending: nil, basis_error: nil, basis_error_kind: :warn, last_source: nil)

  @doc """
  Opens the dialog for `change` (`Gallformers.Import.record_taxonomy_change/3`'s),
  with `summary` (what it does, in words), the confirm button's `label` and
  the flash `done` on success.
  """
  @spec ask(Phoenix.LiveView.Socket.t(), term(), String.t(), String.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  def ask(socket, change, summary, label, done) do
    assign(socket,
      pending: %{change: change, summary: summary, confirm: label, done: done},
      basis_error: nil
    )
  end

  @doc "Closes the dialog with nothing changed."
  @spec cancel(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def cancel(socket), do: assign(socket, pending: nil, basis_error: nil)

  @doc """
  Makes the pending change credited to `basis` as the signed-in admin.
  `{:ok, socket, result, done}` with the dialog closed and the Source
  remembered for the next change, or `{:error, socket}` with the reason in
  the dialog (as a warning when the tree won't follow it).
  """
  @spec run(Phoenix.LiveView.Socket.t(), term()) ::
          {:ok, Phoenix.LiveView.Socket.t(), term(), String.t()}
          | {:error, Phoenix.LiveView.Socket.t()}
  def run(%{assigns: %{pending: %{change: change, done: done}}} = socket, basis) do
    case Gallformers.Import.record_taxonomy_change(socket.assigns.actor, basis, change) do
      {:ok, result} ->
        socket =
          socket
          |> assign(pending: nil, basis_error: nil)
          |> assign(:last_source, remembered(basis) || socket.assigns.last_source)

        {:ok, socket, result, done}

      {:error, reason} ->
        kind =
          if match?({tag, _} when tag in [:outranked, :still_held], reason),
            do: :warn,
            else: :danger

        {:error, assign(socket, basis_error: Errors.text(reason), basis_error_kind: kind)}
    end
  end

  defp remembered({:source, id}), do: id |> Sources.get_source!() |> entry()

  defp remembered({:citation, attrs}) do
    case Sources.get_source_by_title(String.trim(attrs.title || "")) do
      nil -> nil
      source -> entry(source)
    end
  end

  defp remembered(_basis), do: nil

  defp entry(source) do
    %{
      id: source.id,
      title: source.title,
      short: Sources.short_name(source),
      dated?: source.authored_date != nil
    }
  end

  # -- the dialog --------------------------------------------------------------

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       choice: "source",
       source: nil,
       source_query: "",
       source_results: [],
       params: %{"title" => "", "authors" => "", "authored" => "", "doi" => "", "reason" => ""},
       missing: nil
     )}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      if socket.assigns[:remembered_applied],
        do: socket,
        else: assign(socket, source: assigns[:remembered], remembered_applied: true)

    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("pick", %{"choice" => choice}, socket)
      when choice in ~w(source citation gallformers),
      do: {:noreply, assign(socket, choice: choice, missing: nil)}

  def handle_event("search_source", %{"value" => query}, socket) do
    results =
      if String.length(String.trim(query)) >= 2, do: sources(query), else: []

    {:noreply, assign(socket, source_query: query, source_results: results)}
  end

  def handle_event("select_source", %{"id" => id}, socket) do
    source = Enum.find(socket.assigns.source_results, &(&1.id == String.to_integer(id)))

    {:noreply, assign(socket, source: source, source_query: "", source_results: [], missing: nil)}
  end

  def handle_event("clear_source", _params, socket),
    do: {:noreply, assign(socket, source: nil, source_query: "", source_results: [])}

  def handle_event("change", %{"basis" => params}, socket),
    do: {:noreply, assign(socket, params: Map.merge(socket.assigns.params, params))}

  def handle_event("confirm", params, socket) do
    socket = assign(socket, params: Map.merge(socket.assigns.params, params["basis"] || %{}))

    case basis(socket.assigns) do
      {:ok, basis} ->
        send(self(), {__MODULE__, {:chosen, basis}})
        {:noreply, assign(socket, missing: nil)}

      {:missing, message} ->
        {:noreply, assign(socket, missing: message)}
    end
  end

  defp basis(%{choice: "source", source: nil}), do: {:missing, "Pick the Source it follows."}
  defp basis(%{choice: "source", source: %{id: id}}), do: {:ok, {:source, id}}

  defp basis(%{choice: "citation", params: params}) do
    authors =
      params["authors"]
      |> String.split(";")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    {:ok,
     {:citation,
      %{
        title: params["title"],
        authors: authors,
        authored: params["authored"],
        doi: params["doi"]
      }}}
  end

  defp basis(%{choice: "gallformers", params: params}),
    do: {:ok, {:gallformers, params["reason"]}}

  # Sources a change can follow: not Gallformers' own, not retracted.
  defp sources(query) do
    own = Sources.own_source_ids()

    query
    |> Sources.search_sources()
    |> Enum.reject(&(&1.id in own or &1.retracted_by_id != nil))
    |> Enum.take(@source_results)
    |> Enum.map(&entry/1)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.dialog
        id={"#{@id}-dialog"}
        title="Based on which Source?"
        show
        on_cancel={JS.push(@cancel_event)}
      >
        <.form
          for={%{}}
          as={:basis}
          id={"#{@id}-form"}
          phx-change="change"
          phx-submit="confirm"
          phx-target={@myself}
          class="flex flex-col gap-block"
        >
          <p id={"#{@id}-change"} class="text-ui text-ink">{@change}</p>
          <p class="text-meta text-ink-2">
            The tree follows the Sources' statements: the change is recorded as the Source's, accepted by you, and competes by the Source's date.
          </p>

          <div id={"#{@id}-choices"} role="radiogroup" aria-label="Based on" class="grid gap-1.5">
            <.review_option
              id={"#{@id}-choice-source"}
              name="basis[choice]"
              value="source"
              checked={@choice == "source"}
              recommended
              label="A Source in Gallformers"
              summary="The paper the change follows. When the backscan imports it, its statement matches and raises no question."
              on_pick="pick"
              target={@myself}
            >
              <:follow>
                <.typeahead
                  id={"#{@id}-source"}
                  label="Source"
                  placeholder="Search Sources by title or author..."
                  search_event="search_source"
                  select_event="select_source"
                  clear_event="clear_source"
                  query={@source_query}
                  results={@source_results}
                  selected={@source}
                  display_fn={& &1.title}
                  target={@myself}
                >
                  <:result :let={source}>
                    <span class="font-semibold">{source.short}</span>
                    <span class="ml-1 text-meta text-ink-2">{source.title}</span>
                    <span :if={!source.dated?} class="ml-1 text-caption text-muted">(no date)</span>
                  </:result>
                </.typeahead>
              </:follow>
            </.review_option>

            <.review_option
              id={"#{@id}-choice-citation"}
              name="basis[choice]"
              value="citation"
              checked={@choice == "citation"}
              label="A new citation"
              summary="A paper Gallformers doesn't hold yet: its title, authors and date make it a Source now. Complete it later in the Source editor."
              on_pick="pick"
              target={@myself}
            >
              <:follow>
                <.input
                  id={"#{@id}-cite-title"}
                  name="basis[title]"
                  value={@params["title"]}
                  label="Title"
                  required
                />
                <.input
                  id={"#{@id}-cite-authors"}
                  name="basis[authors]"
                  value={@params["authors"]}
                  label="Authors"
                  placeholder="Smith, J.; Jones, K."
                  required
                />
                <p class="gf-hint">Separate the authors with semicolons.</p>
                <div class="grid gap-block sm:grid-cols-2">
                  <.input
                    id={"#{@id}-cite-authored"}
                    name="basis[authored]"
                    value={@params["authored"]}
                    label="Date"
                    placeholder="2008, 2008-05 or 2008-05-14"
                    required
                  />
                  <.input
                    id={"#{@id}-cite-doi"}
                    name="basis[doi]"
                    value={@params["doi"]}
                    label="DOI (optional)"
                  />
                </div>
              </:follow>
            </.review_option>

            <.review_option
              id={"#{@id}-choice-gallformers"}
              name="basis[choice]"
              value="gallformers"
              checked={@choice == "gallformers"}
              label="No Source: Gallformers' own position"
              summary="Only when no paper supports it, such as an undescribed Gall's Inducer. Recorded as Gallformers' statement, dated today, with your reason."
              on_pick="pick"
              target={@myself}
            >
              <:follow>
                <.input
                  id={"#{@id}-reason"}
                  name="basis[reason]"
                  type="textarea"
                  value={@params["reason"]}
                  label="Reason"
                  placeholder="Why Gallformers takes this position, and on what it rests"
                  required
                />
              </:follow>
            </.review_option>
          </div>

          <.notice :if={@missing} id={"#{@id}-missing"} kind={:danger}>{@missing}</.notice>
          <.notice :if={@error} id={"#{@id}-error"} kind={@error_kind}>{@error}</.notice>
        </.form>
        <:actions>
          <.button phx-click={JS.push(@cancel_event)}>Cancel</.button>
          <.button id={"#{@id}-confirm"} type="submit" form={"#{@id}-form"} variant="primary">
            {@confirm_label}
          </.button>
        </:actions>
      </.dialog>
    </div>
    """
  end
end
