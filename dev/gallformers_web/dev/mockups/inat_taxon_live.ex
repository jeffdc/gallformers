defmodule GallformersWeb.Dev.Mockups.InatTaxonLive do
  @moduledoc """
  Mockup (matter `cb28`, "Add a taxon from iNaturalist"): a review question
  answered by finding the taxon on iNaturalist and bringing it into our tree,
  in a side panel over the review. `/dev/mockups/inat-taxon` (`?case=host`,
  the Rubus Host of package 119; `?case=family`, Floate 2010's Syrphidae).

  Real: iNaturalist's search and taxa (its public API, read live), and our
  tree: which of the taxon's ancestors, children and names we hold, read
  through `Gallformers.Taxa.resolve_name/2`; authorship from WCVP for plants.
  Not real: the question (written for the case), Add (nothing is written).
  PROPOSED: one search on the question ("Another plant…": Gallformers, WCVP
  and iNaturalist; "Another taxon…": Gallformers and iNaturalist), an
  iNaturalist result opening the import panel (`inat_taxon_panel`).
  """
  use GallformersWeb, :live_view

  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank
  alias GallformersWeb.ReviewComponents

  @api "https://api.inaturalist.org/v1"
  @user_agent "Gallformers (dev mockup)"

  @cases %{
    "host" => %{
      section: "Host plants",
      who: "InfluentialPoints 2026",
      written: "Rubus villosus var. frondosus",
      question:
        "Which plant does InfluentialPoints 2026 mean by “Rubus villosus var. frondosus”?",
      line:
        "WCVP: Rubus villosus var. frondosus Bigelow ex Torr., a synonym of Rubus pensilvanicus Poir., which WCVP leaves unplaced. We don't have it yet.",
      quote: "Rubus villosus var. frondosus (Rosaceae): curled-leaf pseudogalls.",
      suggest: ["Rubus pensilvanicus", "Rubus frondosus"],
      plant?: true
    },
    "family" => %{
      section: "Which taxon is it",
      who: "Floate 2010",
      written: "Syrphidae",
      question: "Which taxon does Floate 2010 mean by “Syrphidae”? We have none by that name.",
      line: nil,
      quote:
        "Such attacks are costly to the aphids but can kill predaceous maggots (Diptera: Syrphidae) to protect other aphids remaining in the gall.",
      suggest: [],
      plant?: false
    }
  }

  @impl true
  def mount(params, _session, socket) do
    case_id = if Map.has_key?(@cases, params["case"]), do: params["case"], else: "host"
    the_case = @cases[case_id]

    {:ok,
     assign(socket,
       page_title: "Mockup: a taxon from iNaturalist",
       case_id: case_id,
       q: the_case,
       panel?: false,
       step: :find,
       query: the_case.written,
       results: nil,
       taxon: nil,
       plan: nil,
       ticks: MapSet.new(),
       more?: false,
       higher?: false,
       searching?: false,
       card_query: the_case.written,
       card: %{gf: [], wcvp: [], inat: nil},
       done: nil,
       error: nil
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    case_id = if Map.has_key?(@cases, params["case"]), do: params["case"], else: "host"
    the_case = @cases[case_id]

    {:noreply,
     assign(socket,
       case_id: case_id,
       q: the_case,
       panel?: false,
       step: :find,
       query: the_case.written,
       results: nil,
       done: nil
     )}
  end

  # -- events ---------------------------------------------------------------------

  @impl true
  def handle_event("open", _params, socket),
    do: {:noreply, socket |> assign(panel?: true) |> search()}

  def handle_event("close", _params, socket), do: {:noreply, assign(socket, panel?: false)}

  # "Another plant…": one search over Gallformers, WCVP (plants) and iNaturalist.
  def handle_event("search_open", _params, socket),
    do: {:noreply, socket |> assign(searching?: true) |> card_search()}

  def handle_event("card_search", %{"q" => q}, socket),
    do: {:noreply, socket |> assign(card_query: q) |> card_search()}

  def handle_event("use_held", %{"name" => name}, socket),
    do: {:noreply, assign(socket, panel?: false, done: "#{name}, which we have")}

  def handle_event("search", %{"q" => q}, socket),
    do: {:noreply, socket |> assign(query: q, step: :find) |> search()}

  def handle_event("pick", %{"id" => id, "matched" => matched}, socket) do
    socket = assign(socket, panel?: true, step: :loading, error: nil)
    {:noreply, start_async(socket, :taxon, fn -> fetch_taxon(id, matched) end)}
  end

  # Opened from the question's search, "Other results" goes back to it.
  def handle_event("back", _params, socket), do: {:noreply, assign(socket, panel?: false)}

  def handle_event("tick", %{"key" => key}, socket) do
    ticks = socket.assigns.ticks
    ticks = if key in ticks, do: MapSet.delete(ticks, key), else: MapSet.put(ticks, key)
    {:noreply, assign(socket, ticks: ticks)}
  end

  def handle_event("more", _params, socket), do: {:noreply, assign(socket, more?: true)}
  def handle_event("higher", _params, socket), do: {:noreply, assign(socket, higher?: true)}

  def handle_event("add", _params, socket) do
    %{plan: plan} = socket.assigns
    {:noreply, assign(socket, panel?: false, done: "#{plan.name}, added from iNaturalist")}
  end

  @impl true
  def handle_async(:search, {:ok, {:ok, results}}, socket),
    do: {:noreply, assign(socket, results: results, error: nil)}

  def handle_async(:search, {:exit, {:shutdown, :cancel}}, socket), do: {:noreply, socket}

  def handle_async(:card_inat, {:ok, {:ok, results}}, socket),
    do: {:noreply, update(socket, :card, &%{&1 | inat: results})}

  def handle_async(:card_inat, {:exit, {:shutdown, :cancel}}, socket), do: {:noreply, socket}

  def handle_async(:card_inat, _failed, socket),
    do: {:noreply, update(socket, :card, &%{&1 | inat: []})}

  def handle_async(:search, _failed, socket),
    do: {:noreply, assign(socket, results: [], error: "iNaturalist couldn't be reached.")}

  def handle_async(:taxon, {:ok, {:ok, taxon, matched}}, socket) do
    plan = plan(taxon, matched)

    {:noreply,
     assign(socket,
       step: :look,
       taxon: taxon,
       plan: plan,
       ticks: plan.ticked,
       more?: false,
       higher?: false
     )}
  end

  def handle_async(:taxon, _failed, socket),
    do: {:noreply, assign(socket, step: :find, error: "iNaturalist couldn't be reached.")}

  defp card_search(socket) do
    q = String.trim(socket.assigns.card_query)
    plant? = socket.assigns.q.plant?

    gf =
      if String.length(q) < 2,
        do: [],
        else:
          if(plant?,
            do: Enum.map(Taxa.search_plants(q, 5), &%{id: &1.id, name: &1.name, meta: nil}),
            else:
              q
              |> Taxa.search()
              |> Enum.take(5)
              |> Enum.map(&%{id: &1.id, name: &1.name, meta: to_string(&1.rank)})
          )

    wcvp =
      if plant? and String.length(q) >= 3,
        do:
          Enum.map(
            Gallformers.Wcvp.Lookup.search(q, limit: 5, include_synonyms: true),
            &%{
              id: &1.plant_name_id,
              name: &1.taxon_name,
              meta: "#{&1.taxon_authors} · #{String.downcase(&1.taxon_status || "")}"
            }
          ),
        else: []

    socket
    |> assign(card: %{gf: gf, wcvp: wcvp, inat: nil})
    |> cancel_async(:card_inat)
    |> start_async(:card_inat, fn -> search_inat(q) end)
  end

  defp search(socket) do
    q = String.trim(socket.assigns.query)
    socket = assign(socket, results: nil)

    socket
    |> cancel_async(:search)
    |> start_async(:search, fn -> search_inat(q) end)
  end

  # -- iNaturalist (read live) ------------------------------------------------------

  defp get(path, params) do
    case Req.get(@api <> path,
           params: params,
           headers: [{"user-agent", @user_agent}],
           retry: false
         ) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      other -> {:error, other}
    end
  end

  defp search_inat(""), do: {:ok, []}

  defp search_inat(q) do
    with {:ok, %{"results" => results}} <- get("/taxa/autocomplete", q: q, per_page: 6) do
      {:ok, Enum.map(results, &result/1)}
    end
  end

  defp result(r) do
    %{
      id: r["id"],
      name: r["name"],
      rank: r["rank"],
      common: r["preferred_common_name"],
      matched: r["matched_term"],
      observations: r["observations_count"] || 0
    }
  end

  defp fetch_taxon(id, matched) do
    with {:ok, %{"results" => [t | _]}} <- get("/taxa/#{id}", all_names: true) do
      {:ok, t, matched}
    end
  end

  # -- the plan, against our tree ---------------------------------------------------

  defp plan(t, matched) do
    ancestors = t["ancestors"] || []
    kingdom = ancestors |> List.first() |> Kernel.||(%{}) |> Map.get("name")
    plant? = kingdom == "Plantae"

    rows =
      for a <- ancestors, do: row("a#{a["id"]}", a["name"], a["rank"], kingdom)

    held_at = rows |> Enum.with_index() |> Enum.filter(fn {r, _} -> r.held end) |> List.last()
    held_i = if held_at, do: elem(held_at, 1), else: -1

    rows =
      for {r, i} <- Enum.with_index(rows) do
        cond do
          r.held -> r
          r.ours == nil -> %{r | state: :skipped}
          held_at != nil and i > held_i -> %{r | state: :needed}
          true -> %{r | state: :higher}
        end
      end

    me = row("t#{t["id"]}", t["name"], t["rank"], kingdom)

    children =
      (t["children"] || [])
      |> Enum.filter(& &1["is_active"])
      |> Enum.map(&row("c#{&1["id"]}", &1["name"], &1["rank"], kingdom))
      |> Enum.map(fn c -> if c.held, do: %{c | state: :move}, else: %{c | state: :add} end)
      |> Enum.sort_by(&if(&1.held, do: 0, else: 1))

    names = t["names"] || []
    sci = t["name"]

    synonyms =
      for n <- names,
          n["lexicon"] == "scientific-names",
          n["name"] != sci,
          uniq: true,
          do: %{key: "s:" <> n["name"], name: n["name"], matched: n["name"] == matched}

    commons =
      for n <- names,
          n["lexicon"] == "english",
          uniq: true,
          do: %{
            key: "e:" <> n["name"],
            name: n["name"],
            preferred: n["name"] == t["preferred_common_name"]
          }

    new_names =
      Enum.map(Enum.filter(rows, &(&1.state == :needed)), & &1.name) ++
        if(me.held, do: [], else: [sci])

    authors = if plant?, do: wcvp_authors(new_names), else: %{}

    ticked =
      MapSet.new(
        Enum.map(Enum.filter(rows, &(&1.state == :needed)), & &1.key) ++
          Enum.map(Enum.filter(synonyms, & &1.matched), & &1.key) ++
          Enum.map(Enum.filter(commons, & &1.preferred), & &1.key)
      )

    %{
      id: t["id"],
      name: sci,
      rank: t["rank"],
      ours_rank: our_rank(t["rank"]),
      common: t["preferred_common_name"],
      observations: t["observations_count"] || 0,
      active?: t["is_active"] != false,
      kingdom: kingdom,
      plant?: plant?,
      me: me,
      rows: rows,
      held_any?: held_at != nil,
      children: children,
      synonyms: synonyms,
      commons: commons,
      authors: authors,
      new_names: new_names,
      ticked: ticked
    }
  end

  defp row(key, name, rank, kingdom) do
    ours = our_rank(rank)
    held = ours && held(name, ours, kingdom)
    %{key: key, name: name, rank: rank, ours: ours, held: held, state: :held}
  end

  defp our_rank(rank) when is_binary(rank) do
    atom = String.to_existing_atom(rank)
    if atom in Rank.all(), do: atom
  rescue
    ArgumentError -> nil
  end

  defp our_rank(_rank), do: nil

  # The taxon we hold by this name at this rank in this kingdom, with its parent.
  defp held(name, rank, kingdom) do
    case Taxa.resolve_name(name, rank: rank, kingdom: kingdom) do
      {:ok, t} -> %{id: t.id, parent: parent_name(t.parent_id)}
      _ -> nil
    end
  end

  defp parent_name(nil), do: nil

  defp parent_name(id) do
    case Taxa.get_taxon(id) do
      nil -> nil
      t -> Enum.find_value(t.names, &(&1.status == :accepted && &1.name))
    end
  end

  defp wcvp_authors(names) do
    Gallformers.Wcvp.Lookup.find_names(names)
    |> Enum.filter(&(&1.taxon_status in ["Accepted", "Unplaced"]))
    |> Map.new(&{String.downcase(&1.taxon_name), &1.taxon_authors})
  rescue
    _ -> %{}
  end

  defp counts(plan, ticks) do
    added =
      Enum.count(plan.rows, &(&1.state in [:needed, :higher] and &1.key in ticks)) +
        if(plan.me.held, do: 0, else: 1) +
        Enum.count(plan.children, &(&1.state == :add and &1.key in ticks))

    moved = Enum.count(plan.children, &(&1.state == :move and &1.key in ticks))
    names = Enum.count(plan.synonyms ++ plan.commons, &(&1.key in ticks))
    {added, moved, names}
  end

  defp add_label({added, moved, names}) do
    [
      added > 0 && "Add #{added} #{plural(added, "taxon", "taxa")}",
      moved > 0 && "move #{moved}",
      names > 0 && "#{names} #{plural(names, "name", "names")}"
    ]
    |> Enum.filter(& &1)
    |> case do
      [] -> "Use it"
      [one] -> one
      parts -> Enum.join(Enum.drop(parts, -1), ", ") <> " and " <> List.last(parts)
    end
  end

  defp thousands(n),
    do:
      n
      |> Integer.to_string()
      |> String.reverse()
      |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
      |> String.reverse()

  defp observations(n), do: "#{thousands(n)} #{plural(n, "observation", "observations")}"

  defp plural(1, one, _many), do: one
  defp plural(_n, _one, many), do: many

  defp italic?(rank),
    do: rank in ~w(genus subgenus section species subspecies variety form hybrid)

  # -- rendering ----------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user}>
      <div class="gf-density-reading grid items-start gap-section pb-section lg:grid-cols-12">
        <div class="flex min-w-0 flex-col gap-block lg:col-span-8">
          <.notice kind={:warn} title="Mockup: a taxon from iNaturalist (cb28)">
            iNaturalist's search and taxa are real, read live, and so is which of them we hold.
            The question is written for the case, and Add writes nothing.
            <:action>
              <.link patch={~p"/dev/mockups/inat-taxon?case=host"}>The Rubus Host</.link>
              · <.link patch={~p"/dev/mockups/inat-taxon?case=family"}>Syrphidae</.link>
            </:action>
          </.notice>

          <.notice :if={@done} kind={:ok}>Answered: {@done}.</.notice>

          <ReviewComponents.review_card
            id="question"
            section={@q.section}
            holds
            heading={@q.question}
            quotes={[%{text: @q.quote, where: nil}]}
            item_id={1}
            skip_key="q-1"
            on_skip="close"
          >
            <p :if={@q.line} class="text-meta text-ink-2">{@q.line}</p>
            <%!-- PROPOSED: one search for "Another plant…" (Gallformers, WCVP, iNaturalist) or "Another taxon…" (Gallformers, iNaturalist); an iNaturalist result opens the import panel --%>
            <ReviewComponents.review_option
              use
              id="o-0"
              name="o"
              value={0}
              checked={@searching?}
              label={if @q.plant?, do: "Another plant…", else: "Another taxon…"}
              summary={
                if @q.plant?,
                  do: "Search Gallformers, WCVP and iNaturalist by name.",
                  else: "Search Gallformers and iNaturalist by name."
              }
              on_pick="search_open"
            >
              <:follow>
                <.form for={%{}} phx-change="card_search" phx-submit="card_search">
                  <.search_field
                    name="q"
                    value={@card_query}
                    label={if @q.plant?, do: "Find a plant by name", else: "Find a taxon by name"}
                    debounce="400"
                  />
                </.form>
                <div class="rounded-panel border border-line bg-surface">
                  <.group title="In Gallformers" rows={@card.gf} empty="No match" action="Use this" />
                  <.group
                    :if={@q.plant?}
                    title="WCVP"
                    rows={@card.wcvp}
                    empty="No match"
                    action="Add it"
                  />
                  <.group
                    title="On iNaturalist"
                    rows={@card.inat}
                    empty={if @card.inat == nil, do: "Searching…", else: "No match"}
                    action="Look at it"
                    inat
                  />
                </div>
              </:follow>
            </ReviewComponents.review_option>
            <ReviewComponents.review_option
              use
              id="o-2"
              name="o"
              value={2}
              label={if @q.plant?, do: "Leave this Host out", else: "Leave this name out"}
              summary="Leaves out 1 statement."
              on_pick="close"
            />
          </ReviewComponents.review_card>
        </div>

        <div class="lg:col-span-4">
          <.panel_view
            :if={@panel?}
            step={@step}
            plan={@plan}
            ticks={@ticks}
            more?={@more?}
            higher?={@higher?}
            query={@query}
            results={@results}
            error={@error}
            q={@q}
          />
          <aside
            :if={!@panel?}
            class="rounded-panel border border-line bg-surface p-panel text-meta text-muted"
          >
            The review's rail is here; the panel takes its place while it is open.
          </aside>
        </div>
      </div>
    </Layouts.admin>
    """
  end

  attr :title, :string, required: true
  attr :rows, :any, required: true
  attr :empty, :string, required: true
  attr :action, :string, required: true
  attr :inat, :boolean, default: false

  # One group of the search's results.
  defp group(assigns) do
    ~H"""
    <p class="border-b border-line bg-surface-2 px-3 py-1 text-caption font-semibold text-muted">
      {@title}
    </p>
    <p :if={@rows in [nil, []]} class="px-3 py-1.5 text-ui text-muted">{@empty}</p>
    <div
      :for={r <- @rows || []}
      class="flex items-center justify-between gap-3 border-b border-line px-3 py-1.5 last:border-b-0"
    >
      <span class="min-w-0 text-ui text-ink">
        <span class={(!@inat or italic?(r.rank)) && "italic"}>{r.name}</span>
        <span :if={!@inat and r.meta} class="text-caption text-muted">{r.meta}</span>
        <span :if={@inat} class="text-caption text-muted">
          {[r.rank, r.common] |> Enum.filter(& &1) |> Enum.join(" · ")}
          <span :if={r.matched && r.matched != r.name}>· matched “{r.matched}”</span>
        </span>
      </span>
      <.button
        :if={@inat}
        size="sm"
        phx-click="pick"
        phx-value-id={r.id}
        phx-value-matched={r.matched || ""}
      >
        {@action}
      </.button>
      <.button :if={!@inat} size="sm" phx-click="use_held" phx-value-name={r.name}>{@action}</.button>
    </div>
    """
  end

  attr :step, :atom, required: true
  attr :plan, :any, required: true
  attr :ticks, :any, required: true
  attr :more?, :boolean, required: true
  attr :higher?, :boolean, required: true
  attr :query, :string, required: true
  attr :results, :any, required: true
  attr :error, :string, default: nil
  attr :q, :map, required: true

  # PROPOSED: inat_taxon_panel. In the rail's place on wide screens, a bottom sheet on phones (gf-sheet).
  defp panel_view(assigns) do
    ~H"""
    <aside class="gf-sheet gap-4" aria-label="From iNaturalist">
      <div class="flex items-center justify-between gap-3">
        <h2 class="font-brand text-section text-ink">From iNaturalist</h2>
        <.button icon="ph-x" label="Close" icon_only variant="ghost" phx-click="close" />
      </div>

      <%= case @step do %>
        <% :look -> %>
          <.look plan={@plan} ticks={@ticks} more?={@more?} higher?={@higher?} />
        <% :loading -> %>
          <p class="text-body text-ink-2">Reading it from iNaturalist…</p>
        <% _find -> %>
          <.find query={@query} results={@results} error={@error} suggest={@q.suggest} />
      <% end %>
    </aside>
    """
  end

  attr :query, :string, required: true
  attr :results, :any, required: true
  attr :error, :string, default: nil
  attr :suggest, :list, default: []

  defp find(assigns) do
    ~H"""
    <.form for={%{}} phx-change="search" phx-submit="search" class="flex flex-col gap-1">
      <.search_field name="q" value={@query} label="Search iNaturalist by name" debounce="400" />
      <p class="text-caption text-muted">A name, or an iNaturalist link or number.</p>
    </.form>
    <p :if={@error} class="text-body text-danger">{@error}</p>
    <p :if={@results == nil} class="text-body text-ink-2">Searching iNaturalist…</p>
    <div :if={@results == []} class="flex flex-col gap-2">
      <p class="text-body text-ink-2">
        iNaturalist has nothing by “{@query}”. Try another name the Source might mean.
      </p>
      <p :if={@suggest != []} class="flex flex-wrap items-center gap-2 text-meta text-ink-2">
        Names WCVP gives for it:
        <.button :for={n <- @suggest} size="sm" phx-click="search" phx-value-q={n}>
          <span class="italic">{n}</span>
        </.button>
      </p>
    </div>
    <ul :if={@results not in [nil, []]} class="flex flex-col">
      <li
        :for={r <- @results}
        class="flex items-center justify-between gap-3 border-b border-line py-2"
      >
        <span class="flex min-w-0 flex-col">
          <span class="text-body text-ink">
            <span class={italic?(r.rank) && "italic"}>{r.name}</span>
            <span class="text-meta text-muted">{r.rank}</span>
          </span>
          <span class="text-meta text-muted">
            {[r.common, observations(r.observations)]
            |> Enum.filter(& &1)
            |> Enum.join(" · ")}
          </span>
          <span :if={r.matched && r.matched != r.name} class="text-meta text-ink-2">
            Matched “{r.matched}”, a name iNaturalist files under it
          </span>
        </span>
        <.button size="sm" phx-click="pick" phx-value-id={r.id} phx-value-matched={r.matched || ""}>
          Look at it
        </.button>
      </li>
    </ul>
    """
  end

  attr :plan, :map, required: true
  attr :ticks, :any, required: true
  attr :more?, :boolean, required: true
  attr :higher?, :boolean, required: true

  defp look(assigns) do
    shown = if assigns.more?, do: assigns.plan.children, else: Enum.take(assigns.plan.children, 8)
    {above, below} = Enum.split_while(assigns.plan.rows, &(&1.state in [:higher, :skipped]))
    {above, below} = if assigns.higher?, do: {[], assigns.plan.rows}, else: {above, below}

    assigns =
      assign(assigns,
        shown: shown,
        counts: counts(assigns.plan, assigns.ticks),
        above: above,
        rows: below
      )

    ~H"""
    <button type="button" phx-click="back" class="w-fit text-meta text-link hover:underline">
      ← Other results
    </button>

    <div class="flex flex-col gap-0.5">
      <p class="text-section text-ink">
        <span class={italic?(@plan.rank) && "italic"}>{@plan.name}</span>
        <span class="text-meta text-muted">{@plan.rank}</span>
      </p>
      <p class="text-meta text-ink-2">
        {[@plan.common, observations(@plan.observations)]
        |> Enum.filter(& &1)
        |> Enum.join(" · ")} ·
        <a href={"https://www.inaturalist.org/taxa/#{@plan.id}"} target="_blank" rel="noopener">
          iNaturalist ↗
        </a>
      </p>
      <p :if={@plan.me.held} class="text-meta text-ok">
        We have it: the import links it and adds what you tick.
      </p>
      <p :if={!@plan.ours_rank} class="text-meta text-ink-2">
        iNaturalist ranks it a {@plan.rank}, which we don't use. Add it as:
        <select class="gf-select mt-1" name="rank">
          <option>section</option>
          <option>subgenus</option>
          <option>species</option>
        </select>
      </p>
    </div>

    <section class="flex flex-col gap-1">
      <h3 class="text-meta font-semibold text-muted">Where it goes</h3>
      <p :if={!@plan.held_any?} class="text-meta text-ink-2">
        We hold nothing above it: it goes in at the top of the tree, as our families do. Tick a rank above it to add that too.
      </p>
      <ol class="flex flex-col">
        <li
          :if={@above != []}
          class="flex items-center justify-between gap-3 border-b border-line py-1 text-ui"
        >
          <span class="min-w-0 text-ink-2">
            {List.first(@above).name} › … › {List.last(@above).name}
            <span class="text-caption text-muted">{length(@above)} ranks above it we don't hold</span>
          </span>
          <button type="button" phx-click="higher" class="text-caption text-link hover:underline">
            Show them
          </button>
        </li>
        <li
          :for={r <- @rows}
          class="flex items-center justify-between gap-3 border-b border-line py-1 text-ui"
        >
          <span class={["min-w-0", r.state == :skipped && "text-muted"]}>
            <span class={italic?(r.rank) && "italic"}>{r.name}</span>
            <span class="text-caption text-muted">{r.rank}</span>
          </span>
          <%= case r.state do %>
            <% :held -> %>
              <span class="text-caption text-ok">We have it</span>
            <% :skipped -> %>
              <span class="text-caption text-muted">A rank we don't use</span>
            <% _missing -> %>
              <label class="flex items-center gap-2 text-caption text-ink-2">
                <input
                  type="checkbox"
                  class="gf-checkbox"
                  checked={r.key in @ticks}
                  phx-click="tick"
                  phx-value-key={r.key}
                />
                {if r.state == :needed, do: "Add: needed to attach it", else: "Add"}
              </label>
          <% end %>
        </li>
        <li class="flex items-center justify-between gap-3 py-1 text-ui font-semibold">
          <span>
            <span class={italic?(@plan.rank) && "italic"}>{@plan.name}</span>
            <span class="text-caption font-normal text-muted">{@plan.rank}</span>
          </span>
          <span class="text-caption font-normal text-ink-2">
            {if @plan.me.held, do: "We have it", else: "Added"}
          </span>
        </li>
      </ol>
      <p :if={Enum.any?(@plan.rows, &(&1.state == :higher))} class="text-caption text-muted">
        A rank above one we have would put that one, and its siblings we hold, under it: they stay where they are unless you move them.
      </p>
    </section>

    <section :if={@plan.children != []} class="flex flex-col gap-1">
      <h3 class="text-meta font-semibold text-muted">
        Under it on iNaturalist <span class="font-normal">{length(@plan.children)}</span>
      </h3>
      <ul class="flex flex-col">
        <li
          :for={c <- @shown}
          class="flex items-center justify-between gap-3 border-b border-line py-1 text-ui"
        >
          <span class="min-w-0">
            <span class={italic?(c.rank) && "italic"}>{c.name}</span>
            <span :if={c.state == :move} class="text-caption text-ink-2">
              we have it under {c.held.parent || "the top"}
            </span>
          </span>
          <label class="flex items-center gap-2 text-caption text-ink-2">
            <input
              type="checkbox"
              class="gf-checkbox"
              checked={c.key in @ticks}
              phx-click="tick"
              phx-value-key={c.key}
            />
            {if c.state == :move, do: "Move here", else: "Add"}
          </label>
        </li>
      </ul>
      <button
        :if={!@more? and length(@plan.children) > 8}
        type="button"
        phx-click="more"
        class="w-fit text-meta text-link hover:underline"
      >
        Show {length(@plan.children) - 8} more
      </button>
    </section>

    <section :if={@plan.synonyms != [] or @plan.commons != []} class="flex flex-col gap-1">
      <h3 class="text-meta font-semibold text-muted">Names</h3>
      <label :for={s <- @plan.synonyms} class="flex items-center gap-2 text-ui text-ink">
        <input
          type="checkbox"
          class="gf-checkbox"
          checked={s.key in @ticks}
          phx-click="tick"
          phx-value-key={s.key}
        />
        <span class="italic">{s.name}</span>
        <span class="text-caption text-muted">
          {if s.matched, do: "synonym · the name that matched", else: "synonym"}
        </span>
      </label>
      <label :for={c <- @plan.commons} class="flex items-center gap-2 text-ui text-ink">
        <input
          type="checkbox"
          class="gf-checkbox"
          checked={c.key in @ticks}
          phx-click="tick"
          phx-value-key={c.key}
        />
        {c.name}
        <span class="text-caption text-muted">
          {if c.preferred, do: "common name · iNaturalist's", else: "common name"}
        </span>
      </label>
    </section>

    <section :if={@plan.new_names != []} class="flex flex-col gap-1">
      <h3 class="text-meta font-semibold text-muted">Authorship</h3>
      <div :for={n <- @plan.new_names} class="flex flex-col gap-0.5">
        <label class="text-ui text-ink"><span class="italic">{n}</span></label>
        <input
          type="text"
          class="gf-input"
          value={@plan.authors[String.downcase(n)]}
          placeholder="iNaturalist has no authors: add them if you know them"
        />
        <span :if={@plan.authors[String.downcase(n)]} class="text-caption text-muted">From WCVP</span>
      </div>
    </section>

    <div class="flex flex-col gap-2 border-t border-line pt-3">
      <p class="text-meta text-ink-2">
        {if @plan.plant?,
          do:
            "Marked as from iNaturalist, with its iNaturalist ID. Plants are edited directly, so no statements are recorded.",
          else: "Each is iNaturalist's statement (iNaturalist, accessed 8 Nov 2026), accepted by you."}
      </p>
      <div class="flex flex-wrap items-center gap-3">
        <.button variant="primary" phx-click="add">{add_label(@counts)}</.button>
        <.button variant="ghost" phx-click="close">Cancel</.button>
      </div>
      <p class="text-caption text-muted">
        Then the question is answered with <span class={italic?(@plan.rank) && "italic"}>{@plan.name}</span>.
      </p>
    </div>
    """
  end
end
