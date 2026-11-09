defmodule GallformersWeb.Admin.InatTaxonPanel do
  @moduledoc """
  Bringing a taxon in from iNaturalist (matter `cb28`): the
  `inat_taxon_panel` (`GallformersWeb.ReviewComponents.inat_taxon_panel/1`)
  with its state. It finds the taxon on iNaturalist
  (`Gallformers.Import.search_inat_taxa/1`, read in the background), shows it beside our tree
  (`Gallformers.Import.plan_inat_taxon/2`), lets the curator choose what to
  bring in, and brings it in (`Gallformers.Import.record_inat_taxon/3`).

  Attributes: `id`, `actor`, `start` (`{:taxon, inat_id, matched}` to open
  on a taxon, `{:query, name}` to search for a name, nil for an empty
  search), `back` (opened from a search of its caller's: "← Other results"
  closes it), `answering` (a question is answered with the taxon), `class`
  (the panel's placement in its caller's layout, e.g. its grid column).

  It tells its caller, as `{GallformersWeb.Admin.InatTaxonPanel, message}`
  sent to the LiveView: `{:imported, taxon_id}` once the taxon is in our
  tree, `:close` on Close, Cancel, or "← Other results" back to the
  caller's search.
  """
  use GallformersWeb, :live_component

  alias Gallformers.Import
  alias Gallformers.Sources
  alias Gallformers.Taxa.Rank
  alias GallformersWeb.ReviewComponents

  @unreachable "iNaturalist couldn't be reached."

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       start: :none,
       step: :find,
       query: "",
       results: [],
       suggest: [],
       error: nil,
       plan: nil,
       ticked: MapSet.new(),
       rank: nil,
       authorship: %{},
       more: false,
       higher: false,
       found: false,
       back: false,
       answering: false,
       class: nil
     )}
  end

  @impl true
  def update(assigns, socket) do
    start = Map.get(assigns, :start)
    fresh? = start != socket.assigns.start
    socket = assign(socket, assigns)

    {:ok, if(fresh?, do: begin(socket, start), else: socket)}
  end

  defp begin(socket, {:taxon, inat_id, matched}),
    do: socket |> assign(found: false) |> look(inat_id, matched)

  defp begin(socket, {:query, query}), do: socket |> assign(found: true) |> search(query)
  defp begin(socket, _none), do: assign(socket, step: :find, found: true, query: "", results: [])

  # -- events ----------------------------------------------------------------------

  @impl true
  def handle_event("search", %{"q" => query}, socket), do: {:noreply, search(socket, query)}

  def handle_event("pick", %{"id" => id} = params, socket) do
    matched = if params["matched"] in [nil, ""], do: nil, else: params["matched"]
    {:noreply, look(socket, String.to_integer(id), matched)}
  end

  # Back to the panel's own search, or to its caller's.
  def handle_event("back", _params, %{assigns: %{found: true}} = socket),
    do: {:noreply, assign(socket, step: :find, plan: nil, error: nil)}

  def handle_event("back", _params, socket), do: close(socket)
  def handle_event("close", _params, socket), do: close(socket)

  def handle_event("tick", %{"key" => key}, socket) do
    ticked = socket.assigns.ticked

    ticked =
      if MapSet.member?(ticked, key),
        do: MapSet.delete(ticked, key),
        else: MapSet.put(ticked, key)

    {:noreply, assign(socket, ticked: ticked, error: nil)}
  end

  def handle_event("more", _params, socket), do: {:noreply, assign(socket, more: true)}
  def handle_event("higher", _params, socket), do: {:noreply, assign(socket, higher: true)}

  # The rank to add a taxon of a rank we don't use as, or an authorship typed.
  def handle_event("choose", params, socket) do
    socket =
      case params do
        %{"rank" => rank} -> assign(socket, rank: rank_of(rank), error: nil)
        _ -> socket
      end

    socket =
      case params do
        %{"authorship" => typed} when is_map(typed) ->
          assign(socket, authorship: Map.merge(socket.assigns.authorship, typed))

        _ ->
          socket
      end

    {:noreply, socket}
  end

  def handle_event("add", _params, socket) do
    %{actor: actor, plan: plan} = socket.assigns

    choices = %{
      ticked: socket.assigns.ticked,
      rank: socket.assigns.rank,
      authorship: socket.assigns.authorship
    }

    case Import.record_inat_taxon(actor, plan, choices) do
      {:ok, %{taxon_id: taxon_id}} ->
        send(self(), {__MODULE__, {:imported, taxon_id}})
        {:noreply, assign(socket, error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, error: refusal(reason))}
    end
  end

  defp close(socket) do
    send(self(), {__MODULE__, :close})
    {:noreply, socket}
  end

  defp rank_of(rank) do
    Enum.find(Rank.all(), &(Atom.to_string(&1) == rank))
  end

  # -- iNaturalist, in the background ------------------------------------------------

  defp search(socket, query) do
    socket
    |> assign(step: :find, query: query, results: nil, suggest: [], error: nil)
    |> start_async(:search, fn -> found(query) end)
  end

  defp found(query) do
    case Import.search_inat_taxa(query) do
      {:ok, []} -> {:ok, [], wcvp_names(query)}
      {:ok, results} -> {:ok, results, []}
      {:error, reason} -> {:error, reason}
    end
  end

  defp look(socket, inat_id, matched) do
    socket
    |> assign(step: :loading, error: nil, more: false, higher: false, rank: nil)
    |> start_async(:taxon, fn -> Import.look_up_inat_taxon(inat_id, matched) end)
  end

  @impl true
  def handle_async(:search, {:ok, {:ok, results, suggest}}, socket),
    do: {:noreply, assign(socket, results: results, suggest: suggest)}

  def handle_async(:search, {:ok, {:error, _reason}}, socket),
    do: {:noreply, assign(socket, results: [], error: @unreachable)}

  def handle_async(:search, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, results: [], error: @unreachable)}

  def handle_async(:taxon, {:ok, {:ok, plan}}, socket) do
    {:noreply,
     assign(socket,
       step: :look,
       plan: plan,
       ticked: plan.ticked,
       authorship: plan.authorship
     )}
  end

  def handle_async(:taxon, _failed, socket),
    do: {:noreply, assign(socket, step: :find, error: @unreachable)}

  # The names WCVP gives for a name iNaturalist hasn't: the accepted names
  # of its records (a synonym's), for one-click searches.
  defp wcvp_names(query) do
    lookup = Application.get_env(:gallformers, :wcvp_lookup, Gallformers.Wcvp.Lookup)
    records = lookup.find_names([String.trim(query)])

    ids =
      for r <- records,
          r.accepted_plant_name_id not in [nil, "", r.plant_name_id],
          do: r.accepted_plant_name_id

    lookup.get_names(Enum.uniq(ids))
    |> Enum.map(& &1.taxon_name)
    |> Enum.reject(&(&1 == String.trim(query)))
    |> Enum.uniq()
  rescue
    _ -> []
  end

  # -- a refusal, in words -----------------------------------------------------------

  defp refusal(:rank_required), do: "Choose the rank to add it as."

  defp refusal(:inactive),
    do: "iNaturalist no longer uses this taxon: bring in the one that replaced it."

  defp refusal({:outranked, message}), do: message
  defp refusal({:still_held, message}), do: message
  defp refusal({:rejected, _listener, _reason} = reason), do: Import.taxonomy_refusal(reason)

  defp refusal(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.flat_map(fn {field, messages} -> Enum.map(messages, &"#{field} #{&1}") end)
    |> Enum.join("; ")
    |> then(&"Nothing was added: #{&1}.")
  end

  defp refusal(_reason), do: "Nothing was added: the tree refused it."

  @impl true
  def render(assigns) do
    assigns = assign(assigns, credit: Sources.inaturalist_title(Date.utc_today()))

    ~H"""
    <div class="contents">
      <ReviewComponents.inat_taxon_panel
        id={"#{@id}-panel"}
        step={@step}
        query={@query}
        results={@results}
        suggest={@suggest}
        error={@error}
        plan={@plan}
        ticked={@ticked}
        rank={@rank}
        authorship={@authorship}
        more={@more}
        higher={@higher}
        back={@back or @found}
        answering={@answering}
        credit={@credit}
        target={@myself}
        class={@class}
      />
    </div>
    """
  end
end
