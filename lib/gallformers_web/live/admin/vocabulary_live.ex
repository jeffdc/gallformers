defmodule GallformersWeb.Admin.VocabularyLive do
  @moduledoc """
  The Trait vocabulary (`/admin/vocabulary`, superadmin only; matter
  `d213`, Task D), replacing 6611's vocabulary requests. Categories (the
  Trait values the ID tool filters on) change rarely, and only here; the
  Sources' terms under them are added by the import.

    * **Terms**, by Trait (`Gallformers.Catalog.list_trait_term_mappings/0`,
      the generation names left out): status, category, how it was placed
      and how many Galls use it (`Gallformers.Catalog.term_gall_counts/0`),
      filtered by Trait, status or a search. "Change…" moves a placed term
      to another category (its attributions move with it), marks it as used
      in more than one sense, or places an ambiguous one under one
      category. Each change goes through
      `Gallformers.Import.record_term_edit/3`, so it replays.
    * **Add a category**, with its definition (required), replayed
      (`Gallformers.Import.record_trait_value_added/2`).
    * **Terms that fit no category** (`Gallformers.Catalog.list_no_fit_terms/0`),
      most used first; placing one under a category settles its text uses
      into Facts (`Gallformers.Import.place_term/4`).
    * **Spot checks**: the placements made by agreement not yet checked,
      most Galls first, and the placed terms whose producer suggested
      another category (`Gallformers.Import.list_term_spot_checks/0`), each
      with "Looks right" (recorded as a spot check) and "Move…".
    * **Seed terms** (Task F): the terms gathered from producer packages
      before go-live (`mix gallformers.import.term_candidates`,
      `Gallformers.Import.list_term_candidates/1`), by Trait, most used
      first, each with the categories its uses suggest and, opened, a few
      example quotes. Each is placed under its single suggestion (when its
      uses all agree) or another category, marked ambiguous, marked as
      fitting no category (each a ruling as `:superadmin`, replayed:
      `Gallformers.Import.decide_term_candidate/3`), or skipped for now
      (hidden until the page is reloaded; it stays open). Ticked rows whose
      uses agree are placed in bulk after an inline confirmation
      (`Gallformers.Import.place_term_candidates/2`). Decided ones are
      shown on asking.

  The `:superadmin` live session checks the role; this view's own hook
  names the signed-in user as the actor its writes record.
  """
  use GallformersWeb, :live_view

  import GallformersWeb.ReviewComponents,
    only: [review_quote: 1, review_row: 1, review_section: 1, review_tag: 1]

  alias Ecto.Changeset
  alias Gallformers.Catalog
  alias Gallformers.Catalog.Vocab.TraitTermMapping
  alias Gallformers.Catalog.Vocab.TraitValue
  alias Gallformers.Import
  alias Gallformers.Import.TermCandidate

  on_mount {GallformersWeb.Live.UserAuth, :require_admin_actor}

  # The most term rows listed at once; a filter narrows the rest.
  @max_rows 300

  @status_words %{
    placed: "Placed",
    ambiguous: "Used in more than one sense",
    no_fit: "Fits no category"
  }

  @placed_by_words %{
    seed: "Seeded",
    agreement: "Producer and checker agreed",
    curator: "Curator",
    superadmin: "Superadmin"
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Vocabulary",
       filters: %{"trait" => "", "status" => "", "q" => ""},
       changing: nil,
       add_params: %{"trait" => "", "value" => "", "definition" => ""},
       add_errors: [],
       seed_open: MapSet.new(),
       seed_ticked: MapSet.new(),
       seed_skipped: MapSet.new(),
       seed_closed: MapSet.new(),
       seed_show_decided: false,
       seed_confirm: false
     )
     |> load()}
  end

  # -- events ------------------------------------------------------------------

  @impl true
  def handle_event("filter", params, socket) do
    filters = Map.merge(socket.assigns.filters, Map.take(params, ["trait", "status", "q"]))
    {:noreply, assign(socket, filters: filters)}
  end

  def handle_event("change", %{"where" => where, "id" => id}, socket) do
    key = {where, String.to_integer(id)}
    changing = if socket.assigns.changing == key, do: nil, else: key
    {:noreply, assign(socket, changing: changing)}
  end

  def handle_event("move", %{"term_id" => id, "category" => category}, socket)
      when category != "" do
    term = term!(socket, id)

    edit(socket, {:move, term.trait, term.term, category}, fn moved ->
      "Moved “#{moved.term}” to #{category}; its Galls' Facts moved with it."
    end)
  end

  def handle_event("mark_ambiguous", %{"term_id" => id} = params, socket) do
    term = term!(socket, id)
    candidates = params |> Map.get("candidates", []) |> List.wrap() |> Enum.reject(&(&1 == ""))

    edit(socket, {:mark_ambiguous, term.trait, term.term, candidates, :superadmin}, fn t ->
      "“#{t.term}” is marked as used in more than one sense; each use is decided on its own."
    end)
  end

  def handle_event("mark_unambiguous", %{"term_id" => id, "category" => category}, socket)
      when category != "" do
    term = term!(socket, id)

    edit(socket, {:mark_unambiguous, term.trait, term.term, category, :superadmin}, fn t ->
      "“#{t.term}” is placed under #{category}; it maps on its own again."
    end)
  end

  def handle_event("add_category", params, socket) do
    attrs = %{trait: params["trait"], value: params["value"], definition: params["definition"]}

    case Import.record_trait_value_added(socket.assigns.actor, attrs) do
      {:ok, value} ->
        {:noreply,
         socket
         |> assign(
           add_params: %{"trait" => "", "value" => "", "definition" => ""},
           add_errors: []
         )
         |> put_flash(:info, "Added the #{humanize(value.trait)} category “#{value.value}”.")
         |> load()}

      {:error, %Changeset{} = changeset} ->
        {:noreply,
         assign(socket,
           add_params: Map.take(params, ["trait", "value", "definition"]),
           add_errors: changeset.errors
         )}
    end
  end

  def handle_event("place_no_fit", %{"trait" => trait, "term" => term, "category" => c}, socket)
      when c != "" do
    case Import.place_term(socket.assigns.actor, trait, term, c) do
      {:ok, placed} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Placed “#{placed.term}” under #{c}; the Galls that kept it as text now state it."
         )
         |> load()}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, failure(reason)) |> load()}
    end
  end

  def handle_event("spot_ok", %{"trait" => trait, "term" => term} = params, socket) do
    actor = socket.assigns.actor

    # A term that is a category's own name has no row of its own yet.
    result =
      with nil <- Catalog.get_term(trait, term),
           category when is_binary(category) <- params["category"],
           {:ok, _} <-
             Import.record_term_edit(actor, {:place, trait, term, category, :superadmin}) do
        Import.record_term_edit(actor, {:spot_check, trait, term})
      else
        %TraitTermMapping{} -> Import.record_term_edit(actor, {:spot_check, trait, term})
        nil -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end

    case result do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Checked “#{term}”.") |> load()}
      {:error, reason} -> {:noreply, socket |> put_flash(:error, failure(reason)) |> load()}
    end
  end

  # -- seed terms (Task F) -------------------------------------------------------

  def handle_event("seed_toggle", %{"id" => id}, socket),
    do: {:noreply, update(socket, :seed_open, &toggle(&1, int(id)))}

  def handle_event("seed_section", %{"section" => trait}, socket),
    do: {:noreply, update(socket, :seed_closed, &toggle(&1, trait))}

  def handle_event("seed_tick", %{"id" => id}, socket),
    do:
      {:noreply,
       socket |> update(:seed_ticked, &toggle(&1, int(id))) |> assign(seed_confirm: false)}

  def handle_event("seed_tick_agreeing", _params, socket) do
    agreeing = for c <- seed_listed(socket.assigns), agreed(c), into: MapSet.new(), do: c.id
    {:noreply, assign(socket, seed_ticked: MapSet.union(socket.assigns.seed_ticked, agreeing))}
  end

  def handle_event("seed_show_decided", _params, socket) do
    {:noreply, socket |> update(:seed_show_decided, &(not &1)) |> load()}
  end

  def handle_event("seed_skip", %{"id" => id}, socket) do
    id = int(id)

    {:noreply,
     socket
     |> update(:seed_skipped, &MapSet.put(&1, id))
     |> update(:seed_ticked, &MapSet.delete(&1, id))}
  end

  def handle_event("seed_unskip", _params, socket),
    do: {:noreply, assign(socket, seed_skipped: MapSet.new())}

  def handle_event("seed_place", %{"candidate_id" => id, "category" => category}, socket)
      when category != "" do
    seed_decide(socket, id, {:place, category}, &"Placed “#{&1.term}” under #{category}.")
  end

  def handle_event("seed_ambiguous", %{"candidate_id" => id} = params, socket) do
    candidates = params |> Map.get("candidates", []) |> List.wrap() |> Enum.reject(&(&1 == ""))

    if candidates == [] do
      {:noreply, put_flash(socket, :error, "Tick the categories the term is used in.")}
    else
      seed_decide(
        socket,
        id,
        {:ambiguous, candidates},
        &"“#{&1.term}” is marked as used in more than one sense; each use is decided on its own."
      )
    end
  end

  def handle_event("seed_no_fit", %{"id" => id}, socket) do
    seed_decide(socket, id, :no_fit, &"“#{&1.term}” fits no category; it stays text.")
  end

  def handle_event("seed_bulk_place", _params, socket),
    do: {:noreply, assign(socket, seed_confirm: true)}

  def handle_event("seed_bulk_cancel", _params, socket),
    do: {:noreply, assign(socket, seed_confirm: false)}

  def handle_event("seed_bulk_confirm", _params, socket) do
    {agreeing, _rest} = seed_ticked_split(socket.assigns)

    {:ok, %{placed: placed, failed: failed}} =
      Import.place_term_candidates(socket.assigns.actor, agreeing)

    socket =
      socket
      |> assign(seed_confirm: false, seed_ticked: MapSet.new())
      |> put_flash(:info, "Placed #{terms_text(placed)} under their single suggestion.")

    socket =
      case failed do
        [] ->
          socket

        failed ->
          put_flash(
            socket,
            :error,
            Enum.map_join(failed, " ", fn {c, reason} -> "“#{c.term}”: #{failure(reason)}" end)
          )
      end

    {:noreply, load(socket)}
  end

  # A select left on its prompt.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp seed_decide(socket, id, decision, done) do
    candidate = Import.get_term_candidate!(int(id))

    case Import.decide_term_candidate(socket.assigns.actor, candidate, decision) do
      {:ok, decided} ->
        {:noreply,
         socket
         |> update(:seed_open, &MapSet.delete(&1, decided.id))
         |> update(:seed_ticked, &MapSet.delete(&1, decided.id))
         |> assign(seed_confirm: false)
         |> put_flash(:info, done.(decided))
         |> load()}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, failure(reason)) |> load()}
    end
  end

  defp toggle(set, value),
    do:
      if(MapSet.member?(set, value), do: MapSet.delete(set, value), else: MapSet.put(set, value))

  defp int(id) when is_integer(id), do: id
  defp int(id) when is_binary(id), do: String.to_integer(id)

  defp edit(socket, edit, done) do
    case Import.record_term_edit(socket.assigns.actor, edit) do
      {:ok, term} ->
        {:noreply, socket |> assign(changing: nil) |> put_flash(:info, done.(term)) |> load()}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, failure(reason)) |> load()}
    end
  end

  defp failure(%Changeset{} = changeset) do
    changeset
    |> Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
    |> then(&"The change was refused: #{&1}.")
  end

  defp failure({:placed, term}), do: "“#{term.term}” is placed under another category."
  defp failure({:ambiguous, term}), do: "“#{term.term}” is used in more than one sense."
  defp failure({:not_placed, term}), do: "“#{term.term}” isn't placed under a category."
  defp failure({:not_ambiguous, term}), do: "“#{term.term}” isn't marked ambiguous."
  defp failure(:not_found), do: "That term is not in the vocabulary."
  defp failure({:decided, candidate}), do: "“#{candidate.term}” is already decided."
  defp failure(reason), do: "The change was refused: #{inspect(reason)}."

  # -- loading -------------------------------------------------------------------

  defp load(socket) do
    terms = Enum.reject(Catalog.list_trait_term_mappings(), &(&1.trait == "generation"))
    counts = Catalog.term_gall_counts()
    values = Catalog.list_trait_values()

    assign(socket,
      terms: terms,
      counts: counts,
      values: Enum.group_by(values, & &1.trait, & &1.value),
      no_fit: Catalog.list_no_fit_terms(),
      agreement: agreement(terms, counts),
      suggested: suggested(terms),
      seed: Import.list_term_candidates(decided: socket.assigns.seed_show_decided)
    )
  end

  # The seed candidates listed: the skipped ones left out.
  defp seed_listed(%{seed: seed, seed_skipped: skipped}),
    do: Enum.reject(seed, &MapSet.member?(skipped, &1.id))

  # The ticked candidates still open: {those whose uses agree, the others}.
  defp seed_ticked_split(%{seed_ticked: ticked} = assigns) do
    assigns
    |> seed_listed()
    |> Enum.filter(&(MapSet.member?(ticked, &1.id) and not TermCandidate.decided?(&1)))
    |> Enum.split_with(&agreed/1)
  end

  defp agreed(candidate),
    do: not TermCandidate.decided?(candidate) and TermCandidate.agreed_category(candidate) != nil

  # Placements by agreement not yet checked, most Galls first, then newest.
  defp agreement(terms, counts) do
    terms
    |> Enum.filter(
      &(&1.status == :placed and &1.placed_by == :agreement and is_nil(&1.spot_checked_at))
    )
    |> Enum.sort_by(&{-galls(counts, &1), -unix(&1.placed_at)})
  end

  defp unix(%DateTime{} = at), do: DateTime.to_unix(at)
  defp unix(_at), do: 0

  # Placed terms the producer suggested another category for, by term, the
  # ones checked since left out.
  defp suggested(terms) do
    checked =
      for t <- terms, t.spot_checked_at, into: MapSet.new(), do: {t.trait, t.normalized_term}

    Import.list_term_spot_checks()
    |> Enum.filter(&(is_binary(&1.trait) and is_binary(&1.term)))
    |> Enum.group_by(&{&1.trait, TraitTermMapping.normalize(&1.term)})
    |> Enum.reject(fn {key, _} -> MapSet.member?(checked, key) end)
    |> Enum.map(fn {{trait, _}, [first | _] = facts} ->
      %{
        trait: trait,
        term: first.term,
        category: first.category,
        suggested: facts |> Enum.flat_map(& &1.suggested) |> Enum.uniq(),
        facts: length(facts)
      }
    end)
    |> Enum.sort_by(&{-&1.facts, &1.trait, &1.term})
  end

  defp term!(socket, id) do
    id = if is_binary(id), do: String.to_integer(id), else: id
    Enum.find(socket.assigns.terms, &(&1.id == id)) || raise "no term #{id}"
  end

  # -- what the page shows ---------------------------------------------------------

  defp filtered(terms, %{"trait" => trait, "status" => status, "q" => q}) do
    q = q |> String.trim() |> TraitTermMapping.normalize()

    Enum.filter(terms, fn t ->
      (trait == "" or t.trait == trait) and
        (status == "" or Atom.to_string(t.status) == status) and
        (q == "" or String.contains?(t.normalized_term, q) or
           Enum.any?(t.categories, &String.contains?(&1, q)))
    end)
  end

  defp galls(counts, %{trait: trait, normalized_term: n}), do: Map.get(counts, {trait, n}, 0)

  defp category_text(%{status: :placed, categories: categories}), do: Enum.join(categories, ", ")

  defp category_text(%{status: :ambiguous, candidates: candidates}),
    do: "one of " <> Enum.join(candidates, ", ")

  defp category_text(_term), do: "—"

  defp status_word(status), do: Map.fetch!(@status_words, status)
  defp placed_by_word(nil), do: ""
  defp placed_by_word(by), do: Map.fetch!(@placed_by_words, by)

  defp humanize(text), do: String.replace(text, "_", " ")

  defp facts_text(1), do: "1 Fact"
  defp facts_text(n), do: "#{n} Facts"

  defp terms_text(1), do: "1 term"
  defp terms_text(n), do: "#{n} terms"

  defp bulk_text(agreeing, mixed) do
    their = if agreeing == 1, do: "its", else: "their"
    ask = "Place #{terms_text(agreeing)} under #{their} single suggestion, for every Source?"

    case mixed do
      0 -> ask
      1 -> ask <> " 1 ticked term has uses that disagree; it is left."
      n -> ask <> " #{n} ticked terms have uses that disagree; they are left."
    end
  end

  # "globular 7 · set aside 4"
  defp suggestions_text(suggestions) do
    Enum.map_join(suggestions, " · ", fn s -> "#{s["category"] || "set aside"} #{s["count"]}" end)
  end

  defp decision_text(%{"place" => c}), do: "Placed under #{c}"

  defp decision_text(%{"ambiguous" => cs}),
    do: "Used in more than one sense: #{Enum.join(cs, ", ")}"

  defp decision_text(%{"no_fit" => true}), do: "Fits no category"
  defp decision_text(_decision), do: "Decided"

  # Where an example use is from: its package, Gall and suggested category.
  defp example_where(use) do
    [use["source"], use["gall"], use["category"] || "set aside"]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  # The seed candidates listed, by Trait in the vocabulary's order.
  defp seed_groups(assigns) do
    by_trait = assigns |> seed_listed() |> Enum.group_by(& &1.trait)
    for trait <- TraitValue.traits(), rows = by_trait[trait], do: {trait, rows}
  end

  defp slug(text), do: text |> String.downcase() |> String.replace(~r/[^a-z0-9]+/u, "-")

  defp errors(errors, field), do: translate_errors(errors, field)

  # -- rendering -------------------------------------------------------------------

  @impl true
  def render(assigns) do
    shown = filtered(assigns.terms, assigns.filters)

    assigns =
      assign(assigns,
        shown: Enum.take(shown, @max_rows),
        matching: length(shown),
        traits: TraitValue.traits(),
        statuses: Map.keys(@status_words)
      )

    {seed_agreeing, seed_mixed} = seed_ticked_split(assigns)

    assigns =
      assign(assigns,
        seed_groups: seed_groups(assigns),
        seed_left: Enum.count(assigns.seed, &(not TermCandidate.decided?(&1))),
        seed_agreeing: length(seed_agreeing),
        seed_mixed: length(seed_mixed)
      )

    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title="Vocabulary">
      <div class="space-y-3">
        <.header>
          Vocabulary
          <:subtitle>
            The Trait categories the ID tool filters on, and the Sources' terms under them. Terms
            are added by the import; categories change rarely, and only here.
          </:subtitle>
        </.header>

        <.seed_terms
          groups={@seed_groups}
          left={@seed_left}
          values={@values}
          open={@seed_open}
          ticked={@seed_ticked}
          skipped={MapSet.size(@seed_skipped)}
          closed={@seed_closed}
          show_decided={@seed_show_decided}
          confirm={@seed_confirm}
          agreeing={@seed_agreeing}
          mixed={@seed_mixed}
        />

        <section id="spot-checks" class="gf-card mt-4 overflow-hidden">
          <div class="px-4 py-2.5 border-b border-gray-200">
            <h2 class="text-lg font-semibold text-gray-900">Placements to spot-check</h2>
            <p class="text-sm text-gray-500">
              Terms placed for every Source because the producer and the checker agreed, most Galls
              first, and placed terms the producer suggested another category for. Two readers can
              share a blind spot.
            </p>
          </div>
          <p
            :if={@agreement == [] and @suggested == []}
            class="px-4 py-2 text-sm text-gray-500"
          >
            Nothing to check.
          </p>
          <div class="divide-y divide-gray-200">
            <div
              :for={t <- @agreement}
              id={"agreement-#{t.trait}-#{slug(t.term)}"}
              class="px-4 py-2 grid gap-2"
            >
              <div class="flex flex-wrap items-center gap-2">
                <.review_tag>{humanize(t.trait)}</.review_tag>
                <b class="text-gray-900">“{t.term}”</b>
                <span class="text-gray-400" aria-hidden="true">→</span>
                <span>{category_text(t)}</span>
                <span class="text-sm text-gray-500">
                  · {galls(@counts, t)} Galls · by agreement
                </span>
                <span class="flex-1"></span>
                <.button
                  size="sm"
                  variant="soft"
                  phx-click="spot_ok"
                  phx-value-trait={t.trait}
                  phx-value-term={t.term}
                >
                  Looks right
                </.button>
                <.button
                  size="sm"
                  variant="ghost"
                  phx-click="change"
                  phx-value-where="agreement"
                  phx-value-id={t.id}
                >
                  Move…
                </.button>
              </div>
              <.term_change
                :if={@changing == {"agreement", t.id}}
                id={"agreement-#{t.id}"}
                term={t}
                values={Map.get(@values, t.trait, [])}
              />
            </div>
            <div
              :for={s <- @suggested}
              id={"suggested-#{s.trait}-#{slug(s.term)}"}
              class="px-4 py-2 flex flex-wrap items-center gap-2"
            >
              <.review_tag>{humanize(s.trait)}</.review_tag>
              <b class="text-gray-900">“{s.term}”</b>
              <span class="text-gray-400" aria-hidden="true">→</span>
              <span>{s.category}</span>
              <span class="text-sm text-gray-500">
                · the producer suggested {Enum.join(s.suggested, ", ")} ({facts_text(s.facts)})
              </span>
              <span class="flex-1"></span>
              <.button
                size="sm"
                variant="soft"
                phx-click="spot_ok"
                phx-value-trait={s.trait}
                phx-value-term={s.term}
                phx-value-category={s.category}
              >
                Looks right
              </.button>
            </div>
          </div>
        </section>

        <section id="no-fit" class="gf-card mt-4 overflow-hidden">
          <div class="px-4 py-2.5 border-b border-gray-200">
            <h2 class="text-lg font-semibold text-gray-900">Terms that fit no category</h2>
            <p class="text-sm text-gray-500">
              Kept as text on their Galls. When several pile up, a category may be missing: add it
              below, then place the terms under it. Placing a term gives every Gall that kept it as
              text its Fact.
            </p>
          </div>
          <p :if={@no_fit == []} class="px-4 py-2 text-sm text-gray-500">None.</p>
          <div class="divide-y divide-gray-200">
            <.form
              :for={n <- @no_fit}
              for={%{}}
              id={"no-fit-#{n.trait}-#{slug(n.term)}"}
              phx-submit="place_no_fit"
              class="px-4 py-2 flex flex-wrap items-center gap-2"
            >
              <input type="hidden" name="trait" value={n.trait} />
              <input type="hidden" name="term" value={n.term} />
              <.review_tag>{humanize(n.trait)}</.review_tag>
              <b class="text-gray-900">“{n.term}”</b>
              <span class="text-sm text-gray-500">
                · {n.uses} {if n.uses == 1, do: "use", else: "uses"} kept as text
              </span>
              <span class="flex-1"></span>
              <label for={"no-fit-#{n.trait}-#{slug(n.term)}-category"} class="sr-only">
                Category
              </label>
              <select
                id={"no-fit-#{n.trait}-#{slug(n.term)}-category"}
                name="category"
                class="gf-select w-auto"
              >
                <option value="">Place under…</option>
                <option :for={v <- Map.get(@values, n.trait, [])} value={v}>{v}</option>
              </select>
              <.button type="submit" size="sm" variant="soft">Place for every Source</.button>
            </.form>
          </div>
        </section>

        <section id="add-category-card" class="gf-card mt-4 px-4 py-3">
          <h2 class="text-lg font-semibold text-gray-900">Add a category</h2>
          <p class="text-sm text-gray-500">
            A new Trait value: the ID tool lists it, and producers and curators apply it by its
            definition.
          </p>
          <.form
            for={%{}}
            id="add-category"
            phx-submit="add_category"
            class="grid gap-2 max-w-2xl mt-2"
          >
            <.input
              id="add-category-trait"
              type="select"
              name="trait"
              label="Trait"
              options={Enum.map(@traits, &{humanize(&1), &1})}
              prompt="Choose a Trait"
              value={@add_params["trait"]}
              errors={errors(@add_errors, :trait)}
            />
            <.input
              id="add-category-value"
              name="value"
              label="Category"
              value={@add_params["value"]}
              errors={errors(@add_errors, :value)}
            />
            <.input
              id="add-category-definition"
              type="textarea"
              name="definition"
              label="Definition"
              value={@add_params["definition"]}
              placeholder="What the category means, so producers and curators apply it alike"
              errors={errors(@add_errors, :definition)}
            />
            <div>
              <.button type="submit" variant="primary" size="sm">Add the category</.button>
            </div>
          </.form>
        </section>

        <section id="terms" class="gf-card mt-4 overflow-hidden">
          <div class="px-4 py-2.5 border-b border-gray-200 grid gap-2">
            <h2 class="text-lg font-semibold text-gray-900">
              Terms <span class="font-medium text-gray-500 tabular-nums">· {@matching}</span>
            </h2>
            <.form
              for={%{}}
              id="term-filters"
              phx-change="filter"
              phx-submit="filter"
              class="flex flex-wrap items-end gap-2"
            >
              <div>
                <label for="term-filters-trait" class="gf-label">Trait</label>
                <select id="term-filters-trait" name="trait" class="gf-select w-auto">
                  <option value="">Every Trait</option>
                  <option :for={t <- @traits} value={t} selected={@filters["trait"] == t}>
                    {humanize(t)}
                  </option>
                </select>
              </div>
              <div>
                <label for="term-filters-status" class="gf-label">Status</label>
                <select id="term-filters-status" name="status" class="gf-select w-auto">
                  <option value="">Any</option>
                  <option
                    :for={s <- @statuses}
                    value={s}
                    selected={@filters["status"] == Atom.to_string(s)}
                  >
                    {status_word(s)}
                  </option>
                </select>
              </div>
              <.search_input
                id="term-filters-q"
                name="q"
                value={@filters["q"]}
                placeholder="Find a term or category…"
                phx-debounce="200"
                class="flex-1 min-w-[12rem]"
              />
            </.form>
            <p :if={@matching > length(@shown)} class="text-sm text-gray-500">
              Showing the first {length(@shown)}; narrow the filter to see the rest.
            </p>
          </div>
          <div class="overflow-x-auto">
            <.table id="term-rows" rows={@shown} row_id={&"term-#{&1.id}"} variant="compact">
              <:col :let={t} label="Term"><b>{t.term}</b></:col>
              <:col :let={t} label="Trait">{humanize(t.trait)}</:col>
              <:col :let={t} label="Status">{status_word(t.status)}</:col>
              <:col :let={t} label="Category">{category_text(t)}</:col>
              <:col :let={t} label="Placed by">{placed_by_word(t.placed_by)}</:col>
              <:col :let={t} label="Galls">
                <span data-role="galls" class="tabular-nums">{galls(@counts, t)}</span>
              </:col>
              <:action :let={t}>
                <div class="grid gap-2 justify-items-end">
                  <.button
                    size="sm"
                    variant="ghost"
                    phx-click="change"
                    phx-value-where="term"
                    phx-value-id={t.id}
                  >
                    Change…
                  </.button>
                  <.term_change
                    :if={@changing == {"term", t.id}}
                    id={"term-#{t.id}"}
                    term={t}
                    values={Map.get(@values, t.trait, [])}
                  />
                </div>
              </:action>
            </.table>
          </div>
        </section>
      </div>
    </Layouts.admin>
    """
  end

  # What a superadmin may change about a term: a placed one moves to
  # another category or is marked ambiguous; an ambiguous one is placed
  # under one category; one that fits none is placed (as from its list).
  attr :id, :string, required: true
  attr :term, :map, required: true
  attr :values, :list, required: true

  defp term_change(%{term: %{status: :placed}} = assigns) do
    ~H"""
    <div class="grid gap-2 text-left font-normal min-w-[16rem]">
      <.form for={%{}} id={"#{@id}-move"} phx-submit="move" class="flex flex-wrap gap-2">
        <input type="hidden" name="term_id" value={@term.id} />
        <label for={"#{@id}-move-category"} class="sr-only">Move to</label>
        <select id={"#{@id}-move-category"} name="category" class="gf-select w-auto">
          <option value="">Move to…</option>
          <option :for={v <- @values -- @term.categories} value={v}>{v}</option>
        </select>
        <.button type="submit" size="sm" variant="soft">Move, with its Facts</.button>
      </.form>
      <.form for={%{}} id={"#{@id}-ambiguous"} phx-submit="mark_ambiguous" class="grid gap-1">
        <input type="hidden" name="term_id" value={@term.id} />
        <span class="text-sm text-gray-700">Used in more than one sense? Its senses:</span>
        <div class="flex flex-wrap gap-x-3 gap-y-1">
          <label :for={v <- @values} class="text-sm flex items-center gap-1">
            <input
              type="checkbox"
              name="candidates[]"
              value={v}
              checked={v in @term.categories}
              class="gf-checkbox"
            />
            {v}
          </label>
        </div>
        <div>
          <.button type="submit" size="sm" variant="secondary">Mark as ambiguous</.button>
        </div>
      </.form>
    </div>
    """
  end

  defp term_change(%{term: %{status: :ambiguous}} = assigns) do
    ~H"""
    <.form
      for={%{}}
      id={"#{@id}-unambiguous"}
      phx-submit="mark_unambiguous"
      class="flex flex-wrap gap-2 text-left font-normal"
    >
      <input type="hidden" name="term_id" value={@term.id} />
      <label for={"#{@id}-unambiguous-category"} class="sr-only">Place under</label>
      <select id={"#{@id}-unambiguous-category"} name="category" class="gf-select w-auto">
        <option value="">Place under one category…</option>
        <option :for={v <- @values} value={v} selected={v == hd(@term.candidates ++ [nil])}>
          {v}
        </option>
      </select>
      <.button type="submit" size="sm" variant="soft">Mark as unambiguous</.button>
    </.form>
    """
  end

  defp term_change(assigns) do
    ~H"""
    <.form
      for={%{}}
      id={"#{@id}-place"}
      phx-submit="place_no_fit"
      class="flex flex-wrap gap-2 text-left font-normal"
    >
      <input type="hidden" name="trait" value={@term.trait} />
      <input type="hidden" name="term" value={@term.term} />
      <label for={"#{@id}-place-category"} class="sr-only">Place under</label>
      <select id={"#{@id}-place-category"} name="category" class="gf-select w-auto">
        <option value="">Place under…</option>
        <option :for={v <- @values} value={v}>{v}</option>
      </select>
      <.button type="submit" size="sm" variant="soft">Place for every Source</.button>
    </.form>
    """
  end

  # -- seed terms (Task F) -------------------------------------------------------

  attr :groups, :list, required: true, doc: "`{trait, candidates}`, in the vocabulary's order"
  attr :left, :integer, required: true
  attr :values, :map, required: true
  attr :open, :any, required: true
  attr :ticked, :any, required: true
  attr :skipped, :integer, required: true
  attr :closed, :any, required: true
  attr :show_decided, :boolean, required: true
  attr :confirm, :boolean, required: true
  attr :agreeing, :integer, required: true
  attr :mixed, :integer, required: true

  defp seed_terms(assigns) do
    ~H"""
    <section id="seed-terms" class="gf-card mt-4 overflow-hidden">
      <div class="px-4 py-2.5 border-b border-gray-200 grid gap-2">
        <div>
          <h2 class="text-lg font-semibold text-gray-900">
            Seed terms <span class="font-medium text-gray-500 tabular-nums">· {@left} to decide</span>
          </h2>
          <p class="text-sm text-gray-500">
            The terms producers wrote before go-live, with the categories they suggested. Ruling on
            them now places each once for every Source, so early Sources don't bring a question for
            every term.
          </p>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <.button id="seed-tick-agreeing" size="sm" variant="ghost" phx-click="seed_tick_agreeing">
            Tick every term whose uses agree
          </.button>
          <.button
            id="seed-bulk-place"
            size="sm"
            variant="soft"
            phx-click="seed_bulk_place"
            disabled={@agreeing == 0}
          >
            Place each ticked term under its single suggestion…
          </.button>
          <span class="flex-1"></span>
          <.button
            :if={@skipped > 0}
            id="seed-unskip"
            size="sm"
            variant="ghost"
            phx-click="seed_unskip"
          >
            Show the {@skipped} skipped
          </.button>
          <.button id="seed-show-decided" size="sm" variant="ghost" phx-click="seed_show_decided">
            {if @show_decided, do: "Hide decided", else: "Show decided"}
          </.button>
        </div>
      </div>
      <div
        :if={@confirm}
        id="seed-bulk-confirm"
        class="flex flex-wrap items-center gap-2 px-4 py-2.5 bg-yellow-50 text-yellow-900 text-sm border-b border-gray-200"
      >
        <span class="flex-1 min-w-[16rem]">{bulk_text(@agreeing, @mixed)}</span>
        <.button size="sm" variant="primary" phx-click="seed_bulk_confirm">
          Place {terms_text(@agreeing)}
        </.button>
        <.button size="sm" variant="secondary" phx-click="seed_bulk_cancel">Cancel</.button>
      </div>
      <p :if={@groups == []} class="px-4 py-2 text-sm text-gray-500">No seed terms to decide.</p>
    </section>

    <.review_section
      :for={{trait, rows} <- @groups}
      id={"seed-terms-#{trait}"}
      section={trait}
      title={"Seed terms: #{humanize(trait)}"}
      count={"· #{Enum.count(rows, &(not TermCandidate.decided?(&1)))} to decide"}
      closed={MapSet.member?(@closed, trait)}
      on_toggle="seed_section"
    >
      <.seed_row
        :for={c <- rows}
        candidate={c}
        values={Map.get(@values, c.trait, [])}
        open={MapSet.member?(@open, c.id)}
        ticked={MapSet.member?(@ticked, c.id)}
      />
    </.review_section>
    """
  end

  attr :candidate, :map, required: true
  attr :values, :list, required: true
  attr :open, :boolean, required: true
  attr :ticked, :boolean, required: true

  defp seed_row(assigns) do
    c = assigns.candidate

    assigns =
      assign(assigns,
        id: "seed-#{c.id}",
        decided: TermCandidate.decided?(c),
        agreed: TermCandidate.agreed_category(c),
        suggested: TermCandidate.suggested_categories(c)
      )

    ~H"""
    <.review_row
      id={@id}
      open={@open}
      decided={@decided}
      on_toggle={JS.push("seed_toggle", value: %{id: @candidate.id})}
    >
      <:written>
        <span class="inline-flex items-center gap-2">
          <input
            :if={not @decided}
            type="checkbox"
            id={"#{@id}-tick"}
            class="gf-checkbox"
            checked={@ticked}
            phx-click="seed_tick"
            phx-value-id={@candidate.id}
            aria-label={"Tick “#{@candidate.term}”"}
          />
          <span>“{@candidate.term}”</span>
          <span class="text-sm font-normal text-gray-500">
            · <span data-role="uses" class="tabular-nums">{@candidate.total}</span>
            {if @candidate.total == 1, do: "use", else: "uses"}
          </span>
        </span>
      </:written>
      <:answer>
        <span :if={@decided} class="text-gray-700">{decision_text(@candidate.decision)}</span>
        <span :if={not @decided} class="text-gray-700">
          Suggested: {suggestions_text(@candidate.suggestions)}
        </span>
      </:answer>
      <:actions :if={not @decided}>
        <.button
          :if={@agreed}
          size="sm"
          variant="soft"
          phx-click="seed_place"
          phx-value-candidate_id={@candidate.id}
          phx-value-category={@agreed}
        >
          Place under {@agreed}
        </.button>
        <.button size="sm" variant="ghost" phx-click="seed_no_fit" phx-value-id={@candidate.id}>
          Fits no category
        </.button>
        <.button size="sm" variant="ghost" phx-click="seed_skip" phx-value-id={@candidate.id}>
          Skip for now
        </.button>
      </:actions>
      <:detail>
        <div class="grid gap-2">
          <.review_quote
            :for={use <- @candidate.uses}
            :if={use["quote"]}
            text={use["quote"]}
            where={example_where(use)}
          />
        </div>
        <div :if={not @decided} class="grid gap-3">
          <.form
            for={%{}}
            id={"#{@id}-place"}
            phx-submit="seed_place"
            class="flex flex-wrap items-center gap-2"
          >
            <input type="hidden" name="candidate_id" value={@candidate.id} />
            <label for={"#{@id}-place-category"} class="sr-only">Place under</label>
            <select id={"#{@id}-place-category"} name="category" class="gf-select w-auto">
              <option value="">Place under another category…</option>
              <option :for={v <- @values} value={v}>{v}</option>
            </select>
            <.button type="submit" size="sm" variant="soft">Place for every Source</.button>
          </.form>
          <.form for={%{}} id={"#{@id}-ambiguous"} phx-submit="seed_ambiguous" class="grid gap-1">
            <input type="hidden" name="candidate_id" value={@candidate.id} />
            <span class="text-sm text-gray-700">Used in more than one sense? Its senses:</span>
            <div class="flex flex-wrap gap-x-3 gap-y-1">
              <label :for={v <- @values} class="text-sm flex items-center gap-1">
                <input
                  type="checkbox"
                  name="candidates[]"
                  value={v}
                  checked={v in @suggested}
                  class="gf-checkbox"
                />
                {v}
              </label>
            </div>
            <div>
              <.button type="submit" size="sm" variant="secondary">Mark as ambiguous</.button>
            </div>
          </.form>
        </div>
      </:detail>
    </.review_row>
    """
  end
end
