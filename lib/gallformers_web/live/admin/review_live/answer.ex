defmodule GallformersWeb.Admin.ReviewLive.Answer do
  @moduledoc """
  Answering one question of a Source's review (matter `6611`): what a
  question's row on the old step pages (`GallformersWeb.Admin.ReviewLive.ItemRow`)
  and its card in the one-at-a-time review share. The choice picked and what
  its follow-up input holds (a name search, a value, the statements a Gall
  disagrees with settled, a value per Gall, the Galls of identical disputes
  ticked); the searches; the decision that makes, or what is still missing,
  and what it does; deciding through `Gallformers.Import` as the page's
  actor, with a refusal in words; the question's notes; a Host's WCVP panel
  read in the background; and the follow-up inputs themselves (`picker/1`).

  A LiveComponent using it assigns `state/0` on mount, then `entry`,
  `actor`, `definitions`, `source_name` and `choices` (`visible_choices/1`),
  and hands the events in `events/0` (and every `"search_"` one) and its
  async results to `handle_event/3` and `handle_async/3`.
  """
  use GallformersWeb, :html

  import Phoenix.LiveView, only: [start_async: 3]
  import GallformersWeb.ReviewComponents

  alias Gallformers.Catalog
  alias Gallformers.Import
  alias Gallformers.Import.ReviewContext
  alias Gallformers.Places
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank
  alias GallformersWeb.Admin.Review.Choice
  alias GallformersWeb.Admin.Review.Questions
  alias GallformersWeb.Admin.ReviewLive.Document

  @results 10

  # What "Keep as text" sends from a Gall's category select.
  @text "__text__"

  @events ~w(pick pick_tree settle note_draft save_note select_pick clear_pick pick_value
             pick_galls pick_gall fill_galls filter_values toggle_value toggle_member
             pick_missed_taxon)

  @doc ~S|The events `handle_event/3` takes, besides every "search_" one.|
  def events, do: @events

  @doc ~S|What a Gall's category select sends for "Keep as text".|
  def text_value, do: @text

  @doc "The state of an unanswered question, assigned on mount."
  def state,
    do: [
      choice: nil,
      note: "",
      notes: [],
      pick: empty_pick(),
      galls: %{},
      unticked: MapSet.new(),
      settled: %{},
      host: nil,
      error: nil
    ]

  @doc "A follow-up input with nothing in it."
  def empty_pick,
    do: %{query: "", results: [], selected: nil, value: nil, values: [], kind: nil}

  defp wcvp_lookup, do: Application.get_env(:gallformers, :wcvp_lookup, Gallformers.Wcvp.Lookup)

  @doc ~S|The open disputes a grouped question decides together, or [].|
  def members(%{members: [_ | _] = members}),
    do: for(m <- members, m.item.status == :open, do: m.item)

  def members(_entry), do: []

  @doc ~S|The question's choices the back end takes (`pending` ones left out).|
  def visible_choices(entry), do: Enum.reject(entry.question.choices, & &1.pending)

  @doc ~S|The choice picked, or nil.|
  def chosen(%{choice: i, choices: choices}) when is_integer(i), do: Enum.at(choices, i)
  def chosen(_assigns), do: nil

  # -- events --------------------------------------------------------------------

  @doc ~S|Picking, searching, settling, ticking and noting, for the events in `events/0`.|
  def handle_event("pick", params, socket) do
    choice =
      case Integer.parse(params["choice"] || "") do
        {i, ""} -> i
        _ -> socket.assigns.choice
      end

    same? = choice == socket.assigns.choice
    pick = if same?, do: socket.assigns.pick, else: first_results(socket.assigns, choice)
    settled = if same?, do: socket.assigns.settled, else: %{}

    {:noreply, assign(socket, choice: choice, pick: pick, settled: settled, error: nil)}
  end

  # What a synonym becomes when the Source is right: "own" or "move".
  def handle_event("pick_tree", %{"value" => value}, socket) when value in ~w(own move),
    do: {:noreply, assign(socket, pick: %{empty_pick() | kind: value}, error: nil)}

  # Keep, leave out, or ("other") read as another plant one of the Source's
  # statements a chosen Gall disagrees with. The plant search starts with
  # the Host genus's sections, if any; settling the Host otherwise clears it.
  def handle_event("settle", %{"key" => key, "value" => value}, socket)
      when value in ~w(keep leave other) do
    %{pick: pick, settled: settled} = socket.assigns

    pick =
      cond do
        value == "other" and pick == empty_pick() ->
          first_results(socket.assigns, socket.assigns.choice)

        value == "other" ->
          pick

        settled[key] == "other" ->
          empty_pick()

        true ->
          pick
      end

    {:noreply,
     assign(socket,
       settled: Map.put(settled, key, value),
       pick: pick,
       error: nil
     )}
  end

  def handle_event("note_draft", %{"note" => note}, socket),
    do: {:noreply, assign(socket, note: note)}

  def handle_event("save_note", %{"note" => note}, socket) do
    %{actor: actor, entry: entry} = socket.assigns

    case Import.add_note(actor, entry.item, note) do
      {:ok, _note} ->
        {:noreply, assign(socket, note: "", notes: Import.notes_for(entry.item), error: nil)}

      {:error, %Ecto.Changeset{errors: errors}} ->
        message =
          if Keyword.has_key?(errors, :text),
            do: "Write the note first.",
            else: refusal(:gone)

        {:noreply, assign(socket, note: note, error: message)}
    end
  end

  def handle_event("search_" <> what, %{"value" => query}, socket)
      when what in ~w(taxon gall plant place parent) do
    socket = update(socket, :pick, &%{&1 | query: query})

    if String.length(String.trim(query)) < 2 do
      {:noreply, update(socket, :pick, &%{&1 | results: []})}
    else
      search(socket, what, String.trim(query))
    end
  end

  def handle_event("select_pick", %{"id" => id}, socket) do
    selected = Enum.find(socket.assigns.pick.results, &(to_string(&1.id) == id))
    {:noreply, update(socket, :pick, &%{&1 | selected: selected, query: "", results: []})}
  end

  def handle_event("clear_pick", _params, socket),
    do: {:noreply, update(socket, :pick, &%{&1 | selected: nil, query: "", results: []})}

  def handle_event("pick_value", params, socket) do
    value = blank_nil(params["value"])
    kind = Map.get(params, "kind", socket.assigns.pick.kind) |> blank_nil()

    pick =
      if kind == socket.assigns.pick.kind,
        do: %{socket.assigns.pick | value: value},
        else: %{empty_pick() | kind: kind}

    {:noreply, assign(socket, pick: pick, error: nil)}
  end

  # A Gall's category select: picks the per-Gall answer.
  def handle_event("pick_galls", params, socket) do
    galls = Map.merge(socket.assigns.galls, Map.get(params, "gall", %{}))
    per_gall = Enum.find_index(socket.assigns.choices, &(&1.picker == :galls))

    {:noreply,
     assign(socket, galls: galls, choice: per_gall || socket.assigns.choice, error: nil)}
  end

  # A Gall's value, on the per-Gall choices of a Trait term.
  def handle_event("pick_gall", %{"key" => ref, "value" => value}, socket),
    do: {:noreply, assign(socket, galls: Map.put(socket.assigns.galls, ref, value), error: nil)}

  # Each Gall with a recommended value and none chosen gets it.
  def handle_event("fill_galls", _params, socket) do
    galls =
      for g <- socket.assigns.entry.question.galls,
          g.default != nil,
          not Map.has_key?(socket.assigns.galls, g.ref),
          into: socket.assigns.galls,
          do: {g.ref, default_value(g.default)}

    {:noreply, assign(socket, galls: galls, error: nil)}
  end

  # The search over a Trait's values.
  def handle_event("filter_values", %{"q" => query}, socket),
    do: {:noreply, update(socket, :pick, &%{&1 | query: query})}

  # A value ticked or unticked, for a term naming several.
  def handle_event("toggle_value", %{"value" => value}, socket) do
    values = socket.assigns.pick.values

    values =
      if value in values, do: List.delete(values, value), else: values ++ [value]

    {:noreply, update(socket, :pick, &%{&1 | values: values})}
  end

  # A Gall ticked or unticked, on a question for identical disputes.
  def handle_event("pick_missed_taxon", %{"value" => id}, socket),
    do: {:noreply, assign(socket, pick: missed_pick(socket.assigns.entry, id), error: nil)}

  def handle_event("toggle_member", %{"id" => id}, socket) do
    id = String.to_integer(id)
    unticked = socket.assigns.unticked

    unticked =
      if MapSet.member?(unticked, id),
        do: MapSet.delete(unticked, id),
        else: MapSet.put(unticked, id)

    {:noreply, assign(socket, unticked: unticked, error: nil)}
  end

  @doc ~S|A plant search's WCVP results, and a Host's WCVP panel.|
  def handle_async(:wcvp_search, {:ok, {query, results}}, socket) do
    if query == String.trim(socket.assigns.pick.query) do
      tree = Enum.reject(socket.assigns.pick.results, &(&1.group == "WCVP"))
      {:noreply, update(socket, :pick, &%{&1 | results: tree ++ results})}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:wcvp_search, {:exit, _reason}, socket), do: {:noreply, socket}

  def handle_async(:host_panel, {:ok, host}, socket), do: {:noreply, assign(socket, host: host)}

  def handle_async(:host_panel, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, host: :failed)}

  @doc ~S|Starts reading a Host's WCVP panel the first time its question opens.|
  # A Host's WCVP panel, read once, when its row first opens: it runs the
  # Host suggestions, so not for every row of the list.
  def read_host(%{assigns: %{open: true, host: nil} = assigns} = socket) do
    if wcvp_panel?(assigns.entry) do
      written = assigns.entry.question.written
      genera = Map.get(assigns.entry, :genera, [])

      socket
      |> assign(host: :loading)
      |> start_async(:host_panel, fn ->
        ReviewContext.host(written, wcvp: wcvp_lookup(), genera: genera)
      end)
    else
      socket
    end
  end

  def read_host(socket), do: socket

  @doc ~S|Whether a question shows a WCVP panel: a Host named by its own name, still open.|
  # A Host named by its own name (not only a common name), still open.
  def wcvp_panel?(%{item: item, question: question}) do
    question.section.id == :hosts and item.status == :open and
      (item.subject || %{})["common_name"] != true and is_binary(question.written)
  end

  @doc ~S|The plant a Host's "Add a new plant" link starts with (`Loader`).|
  # The plant a Host's "Create a new plant" link starts with (`Loader`).
  def new_plant(entry), do: Map.get(entry, :new_plant)

  # A search that lists first the candidates the question doesn't offer,
  # or (a Host dispute's plant meant, or the plant a Gall's genus Host goes
  # on) the genus's sections.
  defp first_results(assigns, i) do
    choice = is_integer(i) && Enum.at(assigns.choices, i)

    case {choice, plant_sections(choice)} do
      {%Choice{picker: :missed_statement}, _} -> missed_pick(assigns.entry, nil)
      {_, sections} -> sections_or_first(choice, sections, assigns)
    end
  end

  defp sections_or_first(choice, sections, assigns) do
    case sections do
      [_ | _] = sections -> %{empty_pick() | results: Enum.map(sections, &section_result/1)}
      [] -> first_pick(choice, assigns.entry.question.others)
    end
  end

  defp plant_sections(%Choice{picker: {:reading, _name}, sections: sections}), do: sections
  defp plant_sections(%Choice{picker: :statements, sections: sections}), do: sections
  defp plant_sections(_choice), do: []

  defp first_pick(%Choice{picker: {:trait_values, _trait}, values: values}, _others),
    do: %{empty_pick() | values: values}

  # A new species' genus, held by the tree, picked to start with.
  defp first_pick(%Choice{picker: {:parent, _rank}, prefill: %{id: id, name: name}}, _others),
    do: %{empty_pick() | selected: %{id: id, name: name, meta: nil, group: nil}}

  defp first_pick(%Choice{picker: picker}, [_ | _] = others) when picker in [:taxon, :gall] do
    results = for c <- others, do: %{id: c.id, name: c.name, meta: "a possible match", group: nil}
    %{empty_pick() | results: results}
  end

  defp first_pick(_choice, _others), do: empty_pick()

  defp section_result(section),
    do: %{
      id: "taxon:#{section.id}",
      name: section.name,
      meta: section_meta(section.common_name),
      group: "Sections"
    }

  defp section_meta(nil), do: "section"
  defp section_meta(common_name), do: "section · #{common_name}"

  defp blank_nil(""), do: nil
  defp blank_nil(value), do: value

  # A missed name's taxon (`id`, a string from the select, or nil for its
  # first) and the pick it starts: its Galls listed first.
  defp missed_taxon(entry, id) do
    taxa = Map.get(entry, :missed, %{taxa: []}).taxa
    Enum.find(taxa, List.first(taxa), &(to_string(&1.id) == to_string(id)))
  end

  defp missed_pick(entry, id) do
    case missed_taxon(entry, id) do
      nil ->
        empty_pick()

      taxon ->
        meta = if taxon.plant?, do: "on #{taxon.name}", else: "induced by #{taxon.name}"
        results = for g <- taxon.galls, do: %{id: g.id, name: g.name, meta: meta, group: nil}
        %{empty_pick() | value: to_string(taxon.id), results: results}
    end
  end

  # -- searching -----------------------------------------------------------------

  defp search(socket, "taxon", query) do
    results =
      query
      |> Taxa.search()
      |> Enum.take(@results)
      |> Enum.map(&%{id: &1.id, name: &1.name, meta: taxon_meta(&1), group: nil})

    {:noreply, update(socket, :pick, &%{&1 | results: results})}
  end

  # A new taxon's parent: the taxa ranked above it.
  defp search(socket, "parent", query) do
    ranks =
      case chosen(socket.assigns) do
        %Choice{picker: {:parent, rank}} -> Enum.filter(Rank.all(), &Rank.below?(rank, &1))
        _ -> []
      end

    results =
      query
      |> Taxa.search(ranks: ranks)
      |> Enum.take(@results)
      |> Enum.map(&%{id: &1.id, name: &1.name, meta: taxon_meta(&1), group: nil})

    {:noreply, update(socket, :pick, &%{&1 | results: results})}
  end

  defp search(socket, "gall", query) do
    results =
      query
      |> Catalog.search_galls()
      |> Enum.take(@results)
      |> Enum.map(&%{id: &1.id, name: &1.name, meta: aliases(&1.aliases), group: nil})

    {:noreply, update(socket, :pick, &%{&1 | results: results})}
  end

  defp search(socket, "place", query) do
    results =
      query
      |> Places.search_places(@results)
      |> Enum.map(&%{id: &1.code, name: &1.name, meta: &1.code, group: nil})

    {:noreply, update(socket, :pick, &%{&1 | results: results})}
  end

  # Plants in the tree, and (for a Host) plants in WCVP to add.
  defp search(socket, "plant", query) do
    tree =
      query
      |> Taxa.search_plants(@results)
      |> Enum.map(
        &%{
          id: "taxon:#{&1.id}",
          name: &1.name,
          meta: aliases(&1.aliases),
          group: "In Gallformers"
        }
      )

    tree = tree ++ section_hits(socket.assigns, query)
    socket = update(socket, :pick, &%{&1 | results: tree})

    if wcvp_choice?(socket.assigns) and String.length(query) >= 3 do
      {:noreply,
       start_async(socket, :wcvp_search, fn ->
         results =
           query
           |> wcvp_lookup().search(limit: @results)
           |> Enum.map(
             &%{
               id: "wcvp:#{&1.plant_name_id}",
               name: &1.taxon_name,
               meta: &1.taxon_authors,
               group: "WCVP"
             }
           )

         {query, results}
       end)}
    else
      {:noreply, socket}
    end
  end

  # Sections too, where a Host may be one: a Host dispute's plant meant, a
  # common-name Host's other plant (no synonym added to it).
  defp section_hits(assigns, query) do
    if sections?(chosen(assigns)) do
      query
      |> Taxa.search(ranks: [:section], kingdom: "Plantae")
      |> Enum.take(@results)
      |> Enum.map(
        &%{id: "taxon:#{&1.id}", name: &1.name, meta: taxon_meta(&1), group: "Sections"}
      )
    else
      []
    end
  end

  defp sections?(%Choice{picker: {:reading, _name}}), do: true

  defp sections?(%Choice{picker: :statements, statements: statements}),
    do: Enum.any?(statements, &(Map.get(&1, :as) == "host_taxon_id"))

  defp sections?(%Choice{picker: :plant, as: "common_name"}), do: true
  defp sections?(_choice), do: false

  # Only a Host's plant search may add a plant from WCVP.
  defp wcvp_choice?(assigns), do: match?(%Choice{picker: :plant}, chosen(assigns))

  defp taxon_meta(hit) do
    [hit.rank && to_string(hit.rank), aliases(hit.aliases)]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.join(" · ")
  end

  defp aliases([]), do: nil
  defp aliases(list), do: "also " <> Enum.join(Enum.take(list, 3), ", ")

  # -- deciding --------------------------------------------------------------------

  @doc ~S|The decision the answer makes: `{:ok, decision}`, or `{:error, what is missing}`.|
  def decision(assigns) do
    with {:ok, choice} <- chosen_choice(assigns), do: choice_decision(choice, assigns)
  end

  defp chosen_choice(assigns) do
    case chosen(assigns) do
      nil -> {:error, "Choose an answer above."}
      choice -> {:ok, choice}
    end
  end

  defp choice_decision(%Choice{decision: decision}, _assigns) when is_map(decision),
    do: {:ok, decision}

  defp choice_decision(%Choice{picker: :galls} = choice, assigns) do
    by_gall = Map.new(assigns.entry.question.galls, &{&1.ref, Map.get(assigns.galls, &1.ref)})

    case Enum.count(by_gall, fn {_ref, value} -> value in [nil, ""] end) do
      0 ->
        by_gall = Map.new(by_gall, fn {ref, v} -> {ref, if(v == @text, do: nil, else: v)} end)
        {:ok, Questions.picked_decision(choice, {:galls, by_gall})}

      n ->
        {:error, "Choose for #{n} more #{if n == 1, do: "Gall", else: "Galls"}."}
    end
  end

  # Identical disputes: kept for each Gall still ticked.
  defp choice_decision(%Choice{picker: :keep_galls} = choice, assigns) do
    ids = Enum.map(members(assigns.entry), & &1.id)
    except = Enum.filter(ids, &MapSet.member?(assigns.unticked, &1))

    if except == ids do
      drop = Enum.find(assigns.choices, &(&1.decision == %{"skip" => true}))

      {:error, "Every Gall is unticked: choose “#{(drop && drop.label) || "Drop it"}” instead."}
    else
      {:ok, Questions.picked_decision(choice, {:except, except})}
    end
  end

  # Each statement the Gall disagrees with settled; a Host read as another
  # plant, the plant picked.
  defp choice_decision(%Choice{picker: :statements} = choice, assigns) do
    reading = reading_id(assigns.pick)

    settled =
      Map.new(choice.statements, fn s ->
        case assigns.settled[s.key] do
          "keep" -> {s.key, :keep}
          "leave" -> {s.key, :leave}
          "other" when is_integer(reading) -> {s.key, {:reading, reading}}
          _ -> {s.key, nil}
        end
      end)

    case Enum.count(settled, fn {_key, v} -> v == nil end) do
      0 ->
        {:ok, Questions.picked_decision(choice, {:statements, settled})}

      n ->
        {:error,
         "Settle #{n} more #{if n == 1, do: "statement", else: "statements"} " <>
           "#{assigns.source_name || "the Source"} disagrees on."}
    end
  end

  # A section of the genus, picked from the list by name.
  # A missed name stated on the Gall picked: a Host when its taxon is a
  # plant, else the Gall's Inducer.
  defp choice_decision(%Choice{picker: :missed_statement} = choice, assigns) do
    case {missed_taxon(assigns.entry, assigns.pick.value), assigns.pick.selected} do
      {%{} = taxon, %{id: gall_id}} when is_integer(gall_id) ->
        kind = if taxon.plant?, do: "host_of", else: "inducer_of"
        {:ok, Questions.picked_decision(choice, {:missed, kind, taxon.id, gall_id})}

      _ ->
        {:error, "Pick the Gall from the search."}
    end
  end

  defp choice_decision(%Choice{picker: :section} = choice, %{pick: pick}) do
    case Enum.find(choice.sections, &(&1.name == pick.value)) do
      nil -> {:error, missing(:section, pick)}
      section -> {:ok, Questions.picked_decision(choice, {:taxon, section.id})}
    end
  end

  defp choice_decision(%Choice{picker: picker} = choice, %{pick: pick}) do
    case picked(picker, pick) do
      nil -> {:error, missing(picker, pick)}
      picked -> {:ok, Questions.picked_decision(choice, picked)}
    end
  end

  defp picked(:taxon, %{selected: %{id: id}}), do: {:taxon, id}
  defp picked(:gall, %{selected: %{id: id}}), do: {:gall, id}
  defp picked(:place, %{selected: %{id: code}}), do: {:place, code}
  defp picked(:plant, %{selected: %{id: "taxon:" <> id}}), do: {:taxon, String.to_integer(id)}
  defp picked(:plant, %{selected: %{id: "wcvp:" <> id}}), do: {:wcvp, id}

  defp picked({:trait_value, _trait}, %{value: value}) when is_binary(value),
    do: {:trait_value, value}

  defp picked({:trait_values, _trait}, %{values: [_, _ | _] = values}),
    do: {:trait_values, values}

  defp picked(:statement, %{kind: "trait", value: value}) when is_binary(value) do
    [trait, v] = String.split(value, "|", parts: 2)
    {:trait, trait, v}
  end

  defp picked(:statement, %{kind: "host", selected: %{id: "taxon:" <> id}}),
    do: {:host, String.to_integer(id)}

  defp picked(:statement, %{kind: "place", selected: %{id: code}}), do: {:place, code}
  defp picked(:tree, %{kind: "own"}), do: :split

  defp picked(:tree, %{kind: "move", selected: %{id: id}}) when is_integer(id),
    do: {:synonym_of, id}

  defp picked(:generation, %{value: value}) when is_binary(value), do: {:generation, value}

  defp picked(:reason, %{value: reason}) when is_binary(reason) do
    if String.trim(reason) == "", do: nil, else: {:reason, reason}
  end

  defp picked({:parent, _rank}, %{selected: %{id: id}}) when is_integer(id), do: {:taxon, id}
  defp picked({:parent, _rank}, _pick), do: :unplaced

  defp picked({:reading, _name}, %{selected: %{id: "taxon:" <> id}}),
    do: {:taxon, String.to_integer(id)}

  defp picked(_picker, _pick), do: nil

  defp reading_id(%{selected: %{id: "taxon:" <> id}}), do: String.to_integer(id)
  defp reading_id(_pick), do: nil

  @doc ~S|A Gall's recommended value as the per-Gall choices send it.|
  # A Gall's recommended value as the per-Gall choices send it.
  def default_value(:text), do: @text
  def default_value(value), do: value

  # What the chosen option still needs.
  defp missing(:taxon, _pick), do: "Pick a taxon from the search."
  defp missing(:gall, _pick), do: "Pick a Gall from the search."
  defp missing(:plant, _pick), do: "Pick a plant from the search."
  defp missing(:place, _pick), do: "Pick a place from the search."

  defp missing({:trait_value, trait}, _pick),
    do: "Choose a #{humanize(trait)} value from the list."

  defp missing({:trait_values, trait}, _pick),
    do: "Tick at least two #{humanize(trait)} values, or choose a single value above."

  defp missing(:statement, %{kind: "trait"}), do: "Choose the Trait value to state."
  defp missing(:statement, %{kind: "host"}), do: "Pick the Host from the search."
  defp missing(:statement, %{kind: "place"}), do: "Pick the place from the search."
  defp missing(:statement, _pick), do: "Choose what to state."
  defp missing(:tree, %{kind: "move"}), do: "Pick the species it belongs to."
  defp missing(:tree, _pick), do: "Choose what the name becomes."
  defp missing(:generation, _pick), do: "Choose its generation."
  defp missing({:reading, _name}, _pick), do: "Pick the plant meant from the search."
  defp missing(:section, _pick), do: "Choose the section from the list."
  defp missing(:reason, _pick), do: "Write why you decline it."

  @doc ~S|What deciding does, or what is missing: `{ok?, text}`.|
  # What Decide does, or what is missing: `{ok?, text}`.
  def effect(assigns) do
    case decision(assigns) do
      {:ok, _decision} -> {true, effect_for(chosen(assigns), assigns)}
      {:error, message} -> {false, message}
    end
  end

  # What a follow-up's picks do: a synonym's new place in the tree, the
  # statements left out or read as another plant, a new Gall's generation.
  defp effect_for(%Choice{picker: :tree, effects: effects}, %{pick: pick}) do
    case pick do
      %{kind: "own"} -> effects[:split]
      %{selected: %{name: name}} -> String.replace(effects[:synonym_of], "%{taxon}", name)
    end
  end

  defp effect_for(%Choice{picker: :statements} = choice, assigns) do
    plant = get_in(assigns.pick, [:selected, :name])

    parts =
      for s <- choice.statements,
          text =
            (case assigns.settled[s.key] do
               "leave" -> s.left
               "other" -> s.read && String.replace(s.read, "%{taxon}", plant || "another plant")
               _ -> nil
             end),
          is_binary(text),
          do: text

    Enum.join([hint_or_label(choice) | parts], " ")
  end

  # A Trait term's value or values picked: what the Galls get.
  defp effect_for(%Choice{picker: {:trait_value, _}, effect: effect}, %{pick: pick})
       when is_binary(effect),
       do: String.replace(effect, "%{value}", pick.value)

  defp effect_for(%Choice{picker: {:trait_values, _}, effect: effect}, %{pick: pick})
       when is_binary(effect),
       do: String.replace(effect, "%{value}", and_list(pick.values))

  # The per-Gall choices: how many Galls get a value, how many keep the words.
  defp effect_for(%Choice{picker: :galls} = choice, assigns) do
    n = length(assigns.entry.question.galls)
    kept = Enum.count(assigns.galls, fn {_ref, v} -> v == @text end)
    placed = n - kept

    counts =
      "#{placed} #{if placed == 1, do: "Gall gets", else: "Galls get"} the value you chose" <>
        if(kept > 0,
          do: "; #{kept} #{if kept == 1, do: "keeps", else: "keep"} the Source's words",
          else: ""
        ) <>
        "."

    Enum.join(Enum.filter([counts, choice.effect], & &1), " ")
  end

  # Identical disputes kept for the Galls still ticked.
  defp effect_for(%Choice{picker: :keep_galls}, assigns) do
    n = length(members(assigns.entry))
    dropped = Enum.count(members(assigns.entry), &MapSet.member?(assigns.unticked, &1.id))

    every = if n == 2, do: "both Galls", else: "all #{n} Galls"

    case dropped do
      0 ->
        "It goes in for #{every}, as the producer wrote it."

      d ->
        "Kept for #{n - d} of the #{n} Galls; #{d} dropped, their words staying in the " <>
          "Source's text."
    end
  end

  # A Host dispute kept, its Host read as the plant picked.
  defp effect_for(%Choice{picker: {:reading, _name}, effect: effect}, %{pick: pick})
       when is_binary(effect),
       do: String.replace(effect, "%{taxon}", pick.selected.name)

  # A section of the genus picked.
  defp effect_for(%Choice{picker: :missed_statement}, assigns) do
    taxon = missed_taxon(assigns.entry, assigns.pick.value)
    gall = assigns.pick.selected.name
    who = assigns.source_name || "the Source"

    if taxon.plant?,
      do: "Adds that #{taxon.name} is a Host of #{gall}, in #{who}'s words.",
      else: "Adds that #{taxon.name} induces #{gall}, in #{who}'s words."
  end

  defp effect_for(%Choice{picker: :section, effect: effect}, %{pick: %{value: name}})
       when is_binary(effect),
       do: String.replace(effect, "%{taxon}", "sect. #{name}")

  defp effect_for(%Choice{effect: effect}, _assigns) when is_binary(effect), do: effect

  # A new taxon: under the parent picked, else unplaced (the choice's note).
  defp effect_for(%Choice{picker: {:parent, _rank}} = choice, %{pick: %{selected: %{name: name}}}),
       do: "#{hint_or_label(choice)} It goes under #{name}."

  defp effect_for(%Choice{picker: :generation} = choice, %{pick: %{value: value}}),
    do: "#{hint_or_label(choice)} It is created as the #{value} generation."

  defp effect_for(%Choice{note: note} = choice, assigns) when is_binary(note),
    do: effect_text(choice, assigns.pick) <> " " <> note

  defp effect_for(choice, assigns), do: effect_text(choice, assigns.pick)

  defp effect_text(%Choice{picker: picker} = choice, %{selected: %{name: name}})
       when picker in [:taxon, :gall, :plant, :place, :statement],
       do: "#{name}. #{hint_or_label(choice)}"

  defp effect_text(choice, _pick), do: hint_or_label(choice)

  defp hint_or_label(%Choice{hint: hint}) when is_binary(hint) and hint != "", do: hint
  defp hint_or_label(%Choice{label: label}), do: String.trim_trailing(label, "…") <> "."

  @doc """
  Decides the question as `decision`, telling the page as `from` (`{from,
  {:decided, item}}`); a refusal goes in `error`.
  """
  def decide(socket, decision, from) do
    %{actor: actor, entry: entry} = socket.assigns

    result =
      case members(entry) do
        [] ->
          Import.decide_queue_item(actor, entry.item, decision)

        items ->
          with {:ok, [item | _]} <- Import.decide_group(actor, items, decision), do: {:ok, item}
      end

    case result do
      {:ok, item} ->
        send(self(), {from, {:decided, item}})
        {:noreply, assign(socket, open: false, error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, error: refusal(reason))}
    end
  end

  @doc ~S|Where a refused Undo points to change the record instead.|
  # Where a refused Undo points to change the record instead.
  def record_path({:taxon, id}), do: ~p"/admin/taxonomy/#{id}"
  def record_path({:gall, id}), do: ~p"/gall/#{id}"

  @doc ~S|The link's words for `record_path/1`.|
  def record_label({:taxon, _id}), do: "Open in the taxonomy admin"
  def record_label({:gall, _id}), do: "Open the Gall's page"

  @doc ~S|A refused decision, in words.|
  def refusal(:already_decided), do: "This item has been decided already; reload to see it."
  def refusal(:gone), do: "Another decision settled this item; reload to see what is left."
  def refusal(:no_proposal), do: "This item has no proposal to reject."

  def refusal(:not_one_group),
    do: "These disputes are no longer one question; reload to see them."

  def refusal(:invalid_decision), do: "The decision was refused."

  # A taxonomic decision the tree refused, in its words.
  def refusal({:rejected, _listener, _reason} = reason), do: Import.taxonomy_refusal(reason)
  def refusal(%Ecto.Changeset{} = changeset), do: changeset_error(changeset)

  defp changeset_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.flat_map(fn {_field, messages} -> messages end)
    |> Enum.join("; ")
    |> then(&"The decision was refused: #{&1}.")
  end

  @doc "Identical disputes' Galls, each with its quotes, ticked to keep."
  attr :id, :string, required: true
  attr :members, :list, required: true
  attr :unticked, :any, required: true
  attr :target, :any, required: true
  attr :document, :map, default: nil

  def keep_galls(assigns) do
    assigns = assign(assigns, open: Enum.filter(assigns.members, &(&1.item.status == :open)))

    ~H"""
    <div id={@id} class="grid gap-2">
      <.review_term_gall
        :for={m <- @open}
        id={"#{@id}-#{m.item.id}"}
        name={m.question.about || "a Gall"}
        quotes={m.quotes}
      >
        <:passage :let={quote} :if={@document}>
          <.review_passage blocks={Document.passage(@document, quote)} />
        </:passage>
        <label for={"#{@id}-#{m.item.id}-tick"} class="inline-flex items-center gap-2 text-meta">
          <input
            type="checkbox"
            id={"#{@id}-#{m.item.id}-tick"}
            class="gf-checkbox"
            checked={not MapSet.member?(@unticked, m.item.id)}
            phx-click="toggle_member"
            phx-value-id={m.item.id}
            phx-target={@target}
          /> Keep it for this Gall
        </label>
      </.review_term_gall>
    </div>
    """
  end

  # -- pickers ---------------------------------------------------------------------

  @doc "The follow-up input a chosen answer needs: a search, a list, a select."
  attr :id, :string, required: true
  attr :picker, :any, required: true
  attr :pick, :map, required: true
  attr :definitions, :map, required: true
  attr :target, :any, required: true
  attr :choice, :any, default: nil, doc: "the chosen `GallformersWeb.Admin.Review.Choice`"
  attr :settled, :map, default: %{}, doc: "the statements settled so far, by key"
  attr :who, :string, default: nil, doc: "what the page calls the Source"
  attr :entry, :map, default: nil, doc: "the question's entry (a missed name's taxa)"

  # What a synonym becomes when the Source is right.
  def picker(%{picker: :tree} = assigns) do
    ~H"""
    <div class="grid gap-2">
      <.review_segmented
        id={"#{@id}-tree"}
        key="tree"
        label="What the name becomes"
        options={[{"own", "A species of its own again"}, {"move", "A synonym of another species"}]}
        value={@pick.kind}
        on_pick="pick_tree"
        target={@target}
      />
      <p :if={@pick.kind == "own"} class="text-meta text-ink-2">{@choice.note}</p>
      <.name_search
        :if={@pick.kind == "move"}
        id={@id}
        what="taxon"
        label="Find the species it belongs to"
        pick={@pick}
        target={@target}
      />
    </div>
    """
  end

  # The Source's statements the chosen Gall disagrees with.
  def picker(%{picker: :statements} = assigns) do
    ~H"""
    <.review_settle_list
      id={"#{@id}-settle"}
      who={@who || "The Source"}
      statements={@choice.statements}
      settled={@settled}
      on_settle="settle"
      target={@target}
    >
      <:reading>
        <.name_search
          id={@id}
          what="plant"
          label="Find the plant meant"
          pick={@pick}
          target={@target}
        />
      </:reading>
    </.review_settle_list>
    """
  end

  # A section of the genus a common-name Host points to, each with its
  # common name.
  def picker(%{picker: :section} = assigns) do
    assigns =
      assign(assigns, values: for(s <- assigns.choice.sections, do: {s.name, s.common_name}))

    ~H"""
    <div id={@id} class="grid gap-2">
      <.review_value_list
        id={"#{@id}-sections"}
        values={@values}
        selected={List.wrap(@pick.value)}
        on_pick="pick_value"
        target={@target}
      />
    </div>
    """
  end

  # Why a taxonomic statement is declined: a reason, required.
  # A missed name stated: which of its taxa (when it names several), then
  # which Gall, those on the plant or that it induces first.
  def picker(%{picker: :missed_statement} = assigns) do
    taxa = Map.get(assigns.entry || %{}, :missed, %{taxa: []}).taxa
    assigns = assign(assigns, taxa: taxa)

    ~H"""
    <div class="grid gap-2">
      <.form
        :if={length(@taxa) > 1}
        for={%{}}
        id={"#{@id}-taxon"}
        phx-change="pick_missed_taxon"
        phx-target={@target}
      >
        <label for={"#{@id}-taxon-select"} class="gf-label">Which taxon</label>
        <select id={"#{@id}-taxon-select"} name="value" class="gf-select">
          <option :for={t <- @taxa} value={t.id} selected={@pick.value == to_string(t.id)}>
            {t.name}
          </option>
        </select>
      </.form>
      <.name_search id={@id} what="gall" label="Which Gall?" pick={@pick} target={@target} />
    </div>
    """
  end

  def picker(%{picker: :reason} = assigns) do
    ~H"""
    <.form for={%{}} id={@id} phx-change="pick_value" phx-target={@target} class="grid gap-1">
      <label for={"#{@id}-reason"} class="gf-label">Why you decline it</label>
      <textarea id={"#{@id}-reason"} name="value" rows="3" class="gf-textarea">{@pick.value}</textarea>
      <p :if={@choice.note} class="text-meta text-muted">{@choice.note}</p>
    </.form>
    """
  end

  # A new Gall's generation: those Gallformers holds a Gall of can't be chosen.
  def picker(%{picker: :generation} = assigns) do
    ~H"""
    <.form for={%{}} id={@id} phx-change="pick_value" phx-target={@target} class="grid gap-1">
      <label for={"#{@id}-value"} class="gf-label">Generation</label>
      <select id={"#{@id}-value"} name="value" class="gf-select">
        <option value="">Choose a generation</option>
        <option
          :for={g <- @choice.generations}
          value={g.value}
          selected={@pick.value == g.value}
          disabled={g.held}
        >
          {g.value}{if g.held, do: " (Gallformers holds it)"}
        </option>
      </select>
    </.form>
    """
  end

  # Another value of the Trait: searched, each defined.
  # A new taxon's parent: the tree's genus to start with, or a search; none
  # picked, it is added unplaced.
  def picker(%{picker: {:parent, _rank}} = assigns) do
    ~H"""
    <div class="grid gap-2">
      <.name_search
        id={@id}
        what="parent"
        label="Where it goes in the tree: find the taxon it goes under"
        pick={@pick}
        target={@target}
      />
    </div>
    """
  end

  def picker(%{picker: {:trait_value, trait}} = assigns) do
    query = String.downcase(String.trim(assigns.pick.query || ""))

    values =
      assigns.definitions
      |> Map.get(trait, %{})
      |> Enum.sort()
      |> Enum.filter(fn {value, _d} -> String.contains?(String.downcase(value), query) end)

    assigns = assign(assigns, trait: trait, values: values)

    ~H"""
    <div id={@id} class="grid gap-2">
      <.form for={%{}} id={"#{@id}-filter"} phx-change="filter_values" phx-target={@target}>
        <.search_field
          id={"#{@id}-filter-q"}
          name="q"
          value={@pick.query}
          label={"Search #{humanize(@trait)} values"}
          debounce="150"
        />
      </.form>
      <.review_value_list
        id={"#{@id}-values"}
        values={@values}
        selected={List.wrap(@pick.value)}
        on_pick="pick_value"
        target={@target}
      />
    </div>
    """
  end

  # Several values of the Trait: the readers' first, ticked to start with.
  def picker(%{picker: {:trait_values, trait}} = assigns) do
    defs = Map.get(assigns.definitions, trait, %{})
    readers = Enum.filter(assigns.choice.values, &Map.has_key?(defs, &1))
    rest = defs |> Map.keys() |> Enum.sort() |> Enum.reject(&(&1 in readers))
    values = for v <- readers ++ rest, do: {v, defs[v]}
    assigns = assign(assigns, values: values, readers: readers)

    ~H"""
    <div id={@id} class="grid gap-2">
      <.review_value_list
        id={"#{@id}-values"}
        type="checkbox"
        values={@values}
        selected={@pick.values}
        noted={@readers}
        note="a reader chose it"
        on_pick="toggle_value"
        target={@target}
      />
    </div>
    """
  end

  def picker(%{picker: :statement} = assigns) do
    ~H"""
    <div class="grid gap-2">
      <.form for={%{}} id={"#{@id}-kind"} phx-change="pick_value" phx-target={@target}>
        <label for={"#{@id}-kind-select"} class="gf-label">State</label>
        <select id={"#{@id}-kind-select"} name="kind" class="gf-select">
          <option value="">Choose what to state</option>
          <option value="trait" selected={@pick.kind == "trait"}>a Trait value</option>
          <option value="host" selected={@pick.kind == "host"}>a Host</option>
          <option value="place" selected={@pick.kind == "place"}>a place where it is recorded</option>
        </select>
        <%= if @pick.kind == "trait" do %>
          <label for={"#{@id}-value"} class="gf-label mt-2">Trait value</label>
          <select id={"#{@id}-value"} name="value" class="gf-select">
            <option value="">Choose a value</option>
            <optgroup :for={{trait, values} <- Enum.sort(@definitions)} label={humanize(trait)}>
              <option
                :for={{value, _definition} <- Enum.sort(values)}
                value={"#{trait}|#{value}"}
                selected={@pick.value == "#{trait}|#{value}"}
              >
                {humanize(trait)}: {value}
              </option>
            </optgroup>
          </select>
        <% end %>
      </.form>
      <.name_search
        :if={@pick.kind == "host"}
        id={@id}
        what="plant"
        label="Find the Host by name"
        pick={@pick}
        target={@target}
      />
      <.name_search
        :if={@pick.kind == "place"}
        id={@id}
        what="place"
        label="Find the place by name"
        pick={@pick}
        target={@target}
      />
    </div>
    """
  end

  def picker(assigns) do
    assigns = assign(assigns, what: search_what(assigns.picker))

    ~H"""
    <.name_search id={@id} what={@what} label={search_label(@picker)} pick={@pick} target={@target} />
    """
  end

  defp search_what(:taxon), do: "taxon"
  defp search_what(:gall), do: "gall"
  defp search_what(:plant), do: "plant"
  defp search_what(:place), do: "place"
  defp search_what({:reading, _name}), do: "plant"

  defp search_label(:taxon), do: "Find a taxon by name or synonym"
  defp search_label(:gall), do: "Find a Gall by name, Inducer or Host"
  defp search_label(:plant), do: "Find a plant by name (Gallformers and WCVP)"
  defp search_label(:place), do: "Find a place by name"
  defp search_label({:reading, _name}), do: "Find the plant meant"

  attr :id, :string, required: true
  attr :what, :string, required: true
  attr :label, :string, required: true
  attr :pick, :map, required: true
  attr :target, :any, required: true

  defp name_search(assigns) do
    ~H"""
    <.typeahead
      id={@id}
      label={@label}
      placeholder="Type a name…"
      search_event={"search_#{@what}"}
      select_event="select_pick"
      clear_event="clear_pick"
      query={@pick.query}
      results={@pick.results}
      selected={@pick.selected}
      display_fn={& &1.name}
      group_key={if @what == "plant", do: :group}
      target={@target}
    >
      <:result :let={result}>
        <span class="italic">{result.name}</span>
        <span :if={result.meta} class="text-caption text-muted ml-1">{result.meta}</span>
      </:result>
    </.typeahead>
    """
  end

  @doc ~S|A Trait or other key in words ("plant_part" is "plant part").|
  def humanize(text), do: text |> to_string() |> String.replace("_", " ")

  @doc ~S|"a, b and c".|
  def and_list([]), do: ""
  def and_list([one]), do: one
  def and_list(list), do: Enum.join(Enum.drop(list, -1), ", ") <> " and " <> List.last(list)
end
