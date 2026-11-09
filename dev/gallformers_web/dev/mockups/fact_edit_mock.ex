defmodule GallformersWeb.Dev.Mockups.FactEditMock do
  @moduledoc """
  What the three Fact-edit mockups share (matter `d3b0`, "The edit
  framework (in design)"): `/dev/mockups/gall-facts/:id`,
  `/dev/mockups/genus-facts/:name` and `/dev/mockups/species-facts/:id`.
  The question they answer: should every Fact edit begin and end in the
  Facts panel, the main view becoming presentation (with "✎ in Facts"
  links) and editorial fields edited in place?

  The data is real, read through the read models:
  `Gallformers.Import.facts_for_gall/1` for a Gall's Facts,
  `Gallformers.Import.FactsView.statements/1` for every Source's
  statement of each (date, words, whether it counts),
  `Gallformers.Import.taxonomic_position/1`, `taxon_splits/1` and
  `facts_for_source/2` for a taxon's taxonomic statements, and `Gallformers.Taxa`
  for what the tree holds without a statement. The searches in the forms
  are real (`GallformersWeb.Choices.hosts/2`,
  `Gallformers.Taxa.search/2`).

  Every action is fake: it changes the LiveView's assigns only (the open
  form and the mock tray). Nothing is written; the real tray
  (`Gallformers.Curation`, `GallformersWeb.TrayLive`) is never called.

  The proposed pieces, each marked `<!-- PROPOSED: name -->` in the
  markup and used by these mockups only:

    * `facts_panel` — `facts_view` in an Edit mode: each Fact with every
      Source's statement on its own line, the Gallformers-change actions on
      the Fact, "+ Add" per category, and "Correct <Source>'s statement…"
      on each line;
    * `statement_line` — one Source's statement of a Fact: who, when, its
      words, whether it counts;
    * `fact_link` — "✎ in Facts" on the main view: focuses and highlights
      the Fact in the panel;
    * `authority_tray` — the change tray with its items grouped by
      authority, each group one package on apply.
  """
  use GallformersWeb, :html

  import GallformersWeb.FactsComponents, only: [fact_editor: 1, entries: 1]
  import GallformersWeb.ReviewComponents, only: [review_value_list: 1]

  alias Gallformers.{Catalog, Import, Sources, Taxa}
  alias Phoenix.LiveView.Socket

  @results 8

  @trait_order ~w(detachable color texture shape season alignment walls plant_part form cells)
  @trait_labels %{
    "detachable" => "Detachable",
    "color" => "Color",
    "texture" => "Texture",
    "shape" => "Shape",
    "season" => "Season",
    "alignment" => "Alignment",
    "walls" => "Walls",
    "plant_part" => "Location",
    "form" => "Form",
    "cells" => "Cells"
  }

  @events ~w(mock_open mock_add mock_choice mock_submit edit_cancel search_taxon select_taxon
             clear_taxon toggle_value mock_editorial mock_editorial_select mock_flash
             mock_tray_toggle tray_discard tray_review mock_review_close remove_item apply_item
             apply_all toggle_confirm set_evidence search_evidence_source select_evidence_source
             clear_evidence_source)

  @doc "The events the mockups forward to `handle/3`."
  @spec events() :: [String.t()]
  def events, do: @events

  # -- state -------------------------------------------------------------------------

  @doc """
  The mock state on `socket`, whose `:panel` holds the Facts panel's
  categories: nothing open, and the tray seeded with `seed` (examples, so
  the first screen shows the grouping) unless `seed` is empty.
  """
  @spec init(Socket.t(), [map()]) :: Socket.t()
  def init(socket, seed) do
    gallformers = Sources.get_gallformers_source()

    socket
    |> assign(
      mock_edit: nil,
      mock_pick: empty_pick(),
      mock_error: nil,
      mock_items: [],
      mock_next: 1,
      # :wide — open on wide screens, closed on phones, until toggled.
      mock_tray_open: :wide,
      mock_review: false,
      mock_confirmed: [],
      mock_evidence: %{text: "", observations: [], source_id: nil},
      mock_evidence_source: nil,
      mock_source_query: "",
      mock_source_results: [],
      mock_gf: %{id: gallformers && gallformers.id, name: "Gallformers"}
    )
    |> then(fn socket -> Enum.reduce(seed, socket, &add_item(&2, &1)) end)
  end

  defp empty_pick, do: %{query: "", results: [], selected: nil, values: [], note: ""}

  @doc """
  Example tray items from `panel`: a Gallformers note on its first Fact, a
  correction of the first statement of a Source not Gallformers' own, and
  the `editorial` examples given.
  """
  @spec examples([map()], [String.t()]) :: [map()]
  def examples(panel, editorial) do
    facts = all_facts(panel)

    note =
      case Enum.filter(facts, &(&1.kind == :host)) ++ facts do
        [fact | _] ->
          [
            %{
              key: fact.key,
              group: :gallformers,
              kind: :fact,
              text: "Note on #{fact.text}: (example) worth checking against the newest revision",
              flags: [gallformers_flag()],
              evidence: nil
            }
          ]

        [] ->
          []
      end

    # Prefer a statement whose words differ from what the Fact shows: a
    # likely misreading.
    worded =
      Enum.sort_by(
        facts,
        &if(Enum.any?(&1.lines, fn l -> not l.own? and l.words != [] end), do: 0, else: 1)
      )

    correction =
      Enum.find_value(worded, [], fn fact ->
        case Enum.find(fact.lines, &(not &1.own? and &1.words != [])) ||
               Enum.find(fact.lines, &(not &1.own?)) do
          nil ->
            nil

          line ->
            [
              %{
                key: fact.key,
                group: {:source, line.source_id, line.name},
                kind: :fact,
                text: "#{line.name}: #{fact.text} → (example) its statement read again",
                flags: [correction_flag(line)],
                evidence: %{
                  text: "Misread: (example) the import took the wrong line of its table",
                  observations: [],
                  source: %{id: line.source_id, title: line.name}
                }
              }
            ]
        end
      end)

    editorial =
      for text <- editorial,
          do: %{
            field: :example,
            group: :editorial,
            kind: :editorial,
            text: text,
            flags: [%{kind: :editorial, text: "editorial"}]
          }

    note ++ correction ++ editorial
  end

  defp add_item(socket, item) do
    id = socket.assigns.mock_next

    assign(socket,
      mock_items: socket.assigns.mock_items ++ [Map.put(item, :id, id)],
      mock_next: id + 1
    )
  end

  # -- events ------------------------------------------------------------------------

  @doc "One of `events/0` on the mockup's socket (with `:panel`)."
  @spec handle(String.t(), map(), Socket.t()) :: Socket.t()
  def handle("mock_open", %{"key" => key, "action" => action} = params, socket) do
    case find_fact(socket.assigns.panel, key) do
      nil ->
        socket

      fact ->
        authority =
          case action do
            "source_correct" ->
              Enum.find(fact.lines, &(to_string(&1.source_id) == params["source"]))

            _ ->
              nil
          end

        edit = %{
          key: key,
          action: action,
          kind: fact.kind,
          trait: fact[:trait],
          text: fact.text,
          line: authority,
          choice: nil,
          what: nil
        }

        open(socket, edit)
    end
  end

  def handle("mock_add", %{"category" => category, "kind" => kind} = params, socket) do
    trait = params["trait"]

    edit = %{
      key: Enum.join(["add", category, trait], "-") |> String.trim_trailing("-"),
      action: "add",
      kind: String.to_existing_atom(kind),
      trait: trait,
      text: nil,
      line: nil,
      choice: nil,
      what: params["what"]
    }

    open(socket, edit)
  end

  def handle("mock_choice", %{"choice" => choice}, socket),
    do: assign(socket, mock_edit: %{socket.assigns.mock_edit | choice: choice}, mock_error: nil)

  def handle("edit_cancel", _params, socket), do: close(socket)

  def handle("search_taxon", %{"value" => query}, socket) do
    query = String.trim(query)

    results =
      if String.length(query) < 2, do: [], else: choices(socket.assigns.mock_edit, query)

    assign(socket, mock_pick: %{socket.assigns.mock_pick | query: query, results: results})
  end

  def handle("select_taxon", %{"id" => id}, socket) do
    pick = socket.assigns.mock_pick
    selected = Enum.find(pick.results, &(to_string(&1.id) == id))

    assign(socket,
      mock_pick: %{pick | selected: selected, query: "", results: []},
      mock_error: nil
    )
  end

  def handle("clear_taxon", _params, socket),
    do:
      assign(socket,
        mock_pick: %{socket.assigns.mock_pick | selected: nil, query: "", results: []}
      )

  def handle("toggle_value", %{"value" => value}, socket) do
    pick = socket.assigns.mock_pick

    values =
      if value in pick.values, do: List.delete(pick.values, value), else: pick.values ++ [value]

    assign(socket, mock_pick: %{pick | values: values}, mock_error: nil)
  end

  def handle("mock_submit", params, socket) do
    %{mock_edit: edit, mock_pick: pick} = socket.assigns
    note = params |> Map.get("note", "") |> String.trim()
    text = params |> Map.get("text", "") |> String.trim()
    pick = %{pick | note: note}

    case item_for(edit, pick, text, params["where"]) do
      {:ok, item} ->
        socket
        |> add_item(Map.put(item, :key, edit.key))
        |> close()
        |> assign(
          mock_tray_open:
            if(socket.assigns.mock_tray_open == false,
              do: true,
              else: socket.assigns.mock_tray_open
            )
        )

      {:error, message} ->
        assign(socket, mock_pick: pick, mock_error: message)
    end
  end

  def handle("mock_editorial", %{"field" => field, "text" => text}, socket) do
    socket
    |> drop_field(field)
    |> add_item(%{
      field: field,
      group: :editorial,
      kind: :editorial,
      text: text,
      flags: [%{kind: :editorial, text: "editorial"}]
    })
  end

  def handle("mock_editorial_select", %{"field" => field, "label" => label} = params, socket) do
    value = params["value"]
    text = "#{label}: #{if value in [nil, ""], do: "none", else: value}"
    handle("mock_editorial", %{"field" => field, "text" => text}, socket)
  end

  def handle("mock_flash", %{"message" => message}, socket),
    do: Phoenix.LiveView.put_flash(socket, :info, message)

  def handle("mock_tray_toggle", %{"open" => open}, socket),
    do: assign(socket, mock_tray_open: open == "true")

  def handle("tray_discard", _params, socket),
    do: assign(socket, mock_items: [], mock_review: false, mock_confirmed: [])

  def handle("tray_review", _params, socket), do: assign(socket, mock_review: true)
  def handle("mock_review_close", _params, socket), do: assign(socket, mock_review: false)

  def handle("remove_item", %{"id" => id}, socket) do
    items = Enum.reject(socket.assigns.mock_items, &(to_string(&1.id) == id))
    assign(socket, mock_items: items, mock_review: socket.assigns.mock_review and items != [])
  end

  def handle(apply, _params, socket) when apply in ["apply_item", "apply_all"] do
    Phoenix.LiveView.put_flash(
      socket,
      :info,
      "Mockup: nothing is applied. Each group would apply as one package of its Source, through the one ingestion path."
    )
  end

  def handle("toggle_confirm", %{"id" => id}, socket) do
    id = String.to_integer(id)
    confirmed = socket.assigns.mock_confirmed

    assign(socket,
      mock_confirmed: if(id in confirmed, do: List.delete(confirmed, id), else: [id | confirmed])
    )
  end

  def handle("set_evidence", %{"evidence" => evidence}, socket) do
    assign(socket,
      mock_evidence: %{
        socket.assigns.mock_evidence
        | text: evidence["text"] || "",
          observations: []
      }
    )
  end

  def handle("search_evidence_source", %{"value" => query}, socket) do
    query = String.trim(query)

    results =
      if String.length(query) < 3,
        do: [],
        else:
          query
          |> Sources.search_sources()
          |> Enum.take(@results)
          |> Enum.map(&%{id: &1.id, title: &1.title})

    assign(socket, mock_source_query: query, mock_source_results: results)
  end

  def handle("select_evidence_source", %{"id" => id}, socket) do
    source = Enum.find(socket.assigns.mock_source_results, &(to_string(&1.id) == id))
    assign(socket, mock_evidence_source: source, mock_source_query: "", mock_source_results: [])
  end

  def handle("clear_evidence_source", _params, socket),
    do: assign(socket, mock_evidence_source: nil)

  defp open(socket, edit),
    do: assign(socket, mock_edit: edit, mock_pick: empty_pick(), mock_error: nil)

  defp close(socket), do: assign(socket, mock_edit: nil, mock_pick: empty_pick(), mock_error: nil)

  defp drop_field(socket, field),
    do: assign(socket, mock_items: Enum.reject(socket.assigns.mock_items, &(&1[:field] == field)))

  # The search a form's taxon field runs: plants for a Host, other taxa for
  # an Inducer, a parent or an accepted taxon.
  defp choices(%{kind: :host}, query), do: GallformersWeb.Choices.hosts(query, @results)

  defp choices(_edit, query) do
    query
    |> Taxa.search()
    |> Enum.reject(&(&1.kingdom == "Plantae"))
    |> Enum.take(@results)
    |> Enum.map(&%{id: &1.id, name: &1.name, meta: meta(&1.rank, &1.aliases), group: "Taxa"})
  end

  defp meta(rank, aliases) do
    [rank && to_string(rank), aliases != [] && "also " <> Enum.join(Enum.take(aliases, 3), ", ")]
    |> Enum.filter(&is_binary/1)
    |> Enum.join(" · ")
  end

  # -- the tray item an open form makes ------------------------------------------------

  defp item_for(%{action: action} = edit, pick, text, where) do
    with :ok <- check(edit, pick, text) do
      {:ok, item(action, edit, pick, value_text(edit, pick, text, where))}
    end
  end

  defp check(%{action: action}, %{note: ""}, _text) when action in ~w(withdraw note),
    do: {:error, if(action == "note", do: "Write the note.", else: "Say why it goes.")}

  defp check(%{action: "source_correct"}, %{note: ""}, _text),
    do: {:error, "Say what was misread: the correction is audited with it."}

  defp check(%{action: "source_correct", choice: nil}, _pick, _text),
    do: {:error, "Choose what the Source says."}

  defp check(%{action: "source_correct", choice: "withdraw"}, _pick, _text), do: :ok

  defp check(%{action: action} = edit, pick, text) when action in ~w(correct add source_correct),
    do: check_value(edit, pick, text)

  defp check(_edit, _pick, _text), do: :ok

  defp check_value(%{kind: kind}, %{selected: nil}, _text)
       when kind in [:host, :inducer, :placement],
       do: {:error, "Pick it from the search."}

  defp check_value(%{kind: :trait}, %{values: []}, _text), do: {:error, "Pick one value or more."}

  defp check_value(%{kind: kind}, _pick, "")
       when kind not in [:host, :inducer, :placement, :trait],
       do: {:error, "Write what it should be."}

  defp check_value(_edit, _pick, _text), do: :ok

  defp value_text(%{kind: kind}, %{selected: %{name: name}}, _text, _where)
       when kind in [:host, :inducer, :placement],
       do: name

  defp value_text(%{kind: :trait}, %{values: values}, _text, _where), do: Enum.join(values, ", ")

  defp value_text(%{kind: :range}, _pick, text, where) when where not in [nil, ""],
    do: "#{where} #{text}"

  defp value_text(_edit, _pick, text, _where), do: text

  defp item("withdraw", edit, pick, _value),
    do: %{
      group: :gallformers,
      kind: :fact,
      text: "Withdraw #{edit.text}",
      flags: [
        %{kind: :supersedes, text: "denies it: its standing may change"},
        gallformers_flag()
      ],
      evidence: %{text: pick.note, observations: [], source: nil}
    }

  defp item("note", edit, pick, _value),
    do: %{
      group: :gallformers,
      kind: :fact,
      text: "Note on #{edit.text}: #{pick.note}",
      flags: [gallformers_flag()],
      evidence: nil
    }

  defp item("correct", edit, pick, value),
    do: %{
      group: :gallformers,
      kind: :fact,
      text: "Correct #{edit.text} → #{value}",
      flags: [%{kind: :supersedes, text: "denies the old one"}, gallformers_flag()],
      evidence: if(pick.note != "", do: %{text: pick.note, observations: [], source: nil})
    }

  defp item("add", edit, pick, value),
    do: %{
      group: :gallformers,
      kind: :fact,
      text: "Add #{edit.what || "a Fact"}: #{value}",
      flags: [gallformers_flag()],
      evidence: if(pick.note != "", do: %{text: pick.note, observations: [], source: nil})
    }

  defp item("source_correct", %{line: line} = edit, pick, value) do
    said =
      if edit.choice == "withdraw",
        do: "it doesn't say #{edit.text}",
        else: "#{edit.text} → #{value}"

    %{
      group: if(line.gallformers?, do: :gallformers, else: {:source, line.source_id, line.name}),
      kind: :fact,
      text: "#{line.name}: #{said}",
      flags: [correction_flag(line)],
      evidence: %{
        text: "Misread: #{pick.note}",
        observations: [],
        source: %{id: line.source_id, title: line.name}
      }
    }
  end

  defp gallformers_flag,
    do: %{kind: :adds_statement, text: "Gallformers' statement, dated when applied"}

  defp correction_flag(line),
    do: %{kind: :adds_statement, text: "#{line.name}'s statement, at its date (#{line.date})"}

  # -- the panel's data ----------------------------------------------------------------

  @doc "Every Fact of the panel's categories (their sub-groups' too)."
  @spec all_facts([map()]) :: [map()]
  def all_facts(panel) do
    Enum.flat_map(panel, fn c -> c.facts ++ Enum.flat_map(c.subs, & &1.facts) ++ c.past end)
  end

  @doc "The Fact of `panel` keyed `key`, or nil."
  @spec find_fact([map()], String.t()) :: map() | nil
  def find_fact(panel, key), do: Enum.find(all_facts(panel), &(&1.key == key))

  @doc """
  The Facts panel of Gall `gall_id`: its Facts by category
  (`Gallformers.Import.facts_for_gall/1`), each with every Source's
  statement of it. Each Fact carries `ref`, what the main view links it by
  (`{:host, taxon_id}`, `{:trait, trait, value}`, `{:alias, name}`,
  `{:inducer, taxon_id}`).
  """
  @spec gall_panel(integer()) :: [map()]
  def gall_panel(gall_id) do
    all = gall_id |> Import.facts_for_gall() |> entries()
    lines = statement_lines(Enum.map(all, & &1.fact_id))
    {current, past} = all |> Enum.map(&gall_fact(&1, lines)) |> Enum.split_with(&current?/1)
    by = Enum.group_by(current, & &1.category)
    past_by = Enum.group_by(past, & &1.category)

    traits = Map.get(by, :traits, [])
    recorded = traits |> Enum.map(& &1.trait) |> Enum.uniq()

    trait_subs =
      for trait <- Enum.sort_by(recorded, &trait_index/1) do
        %{
          id: "traits-#{trait}",
          label: trait_label(trait),
          trait: trait,
          add: %{kind: :trait, what: "a #{trait_label(trait)} value", trait: trait},
          facts: Enum.filter(traits, &(&1.trait == trait))
        }
      end

    [
      category(:inducer, "Inducer", Map.get(by, :inducer, []), past_by,
        add: %{kind: :inducer, what: "an Inducer", label: "Add an Inducer"},
        empty: "No Inducer: the Gall is undescribed."
      ),
      category(:hosts, "Hosts", Map.get(by, :hosts, []), past_by,
        add: %{kind: :host, what: "a Host", label: "Add a host"}
      ),
      category(:traits, "Traits", [], past_by,
        subs: trait_subs,
        missing: @trait_order -- recorded,
        empty: "No Traits recorded."
      ),
      category(:range, "Range", Map.get(by, :range, []), past_by,
        add: %{kind: :range, what: "a place", label: "Add a place"},
        hint:
          "The range follows the Hosts' ranges; a place here adjusts it (not in, only in) or records where the Gall was found.",
        empty: "Nothing beyond the Hosts' ranges."
      ),
      category(:descriptions, "Descriptions", Map.get(by, :descriptions, []), past_by,
        add: %{kind: :description, what: "a description", label: "Add a description"},
        empty: "No Source's description."
      ),
      category(:aliases, "Aliases", Map.get(by, :aliases, []), past_by,
        add: %{kind: :alias, what: "a common name", label: "Add a common name"},
        empty: "No common names."
      )
    ] ++
      if(Map.has_key?(by, :other),
        do: [category(:other, "Other", by.other, past_by, [])],
        else: []
      )
  end

  defp category(id, title, facts, past_by, opts) do
    %{
      id: to_string(id),
      title: title,
      facts: facts,
      past: Map.get(past_by, id, []),
      subs: Keyword.get(opts, :subs, []),
      missing: Keyword.get(opts, :missing, []),
      add: opts[:add],
      hint: opts[:hint],
      empty: Keyword.get(opts, :empty, "None.")
    }
  end

  defp current?(fact), do: fact.standing in [nil, :current]

  defp trait_index(trait), do: Enum.find_index(@trait_order, &(&1 == trait)) || 99

  @doc "A Trait's label on the Gall page (`plant_part` is Location)."
  @spec trait_label(String.t()) :: String.t()
  def trait_label(trait), do: Map.get(@trait_labels, trait, humanize(trait))

  defp gall_fact(entry, lines) do
    base = %{
      key: "f#{entry.fact_id}",
      fact_id: entry.fact_id,
      category: entry.category,
      standing: entry.standing,
      lines: Map.get(lines, entry.fact_id, []),
      held_note: nil,
      ref: nil,
      trait: nil
    }

    entry |> gall_value(base.lines) |> then(&Map.merge(base, &1)) |> drop_same_words()
  end

  # A Source's words that read as the Fact shows say nothing more (as
  # `facts_view` leaves them out).
  defp drop_same_words(%{label: label, lines: lines} = fact) do
    shown = label |> label_words() |> MapSet.new(&String.downcase/1)

    lines =
      for line <- lines,
          do: %{
            line
            | words: Enum.reject(line.words, &MapSet.member?(shown, String.downcase(&1)))
          }

    %{fact | lines: lines}
  end

  defp label_words({:taxon, name, _rank}), do: [name]
  defp label_words({:placed, name, _rank}), do: [name]

  defp label_words({:name, name, _rank, authorship}),
    do: Enum.reject([name, authorship], &is_nil/1)

  defp label_words({:synonym, name, _rank, _sensu}), do: [name]
  defp label_words({:prefixed, _prefix, text}), do: [text]
  defp label_words({_kind, text}) when is_binary(text), do: [text]
  defp label_words(_label), do: []

  defp gall_value(%{category: :inducer, value: %{subject: s}}, _lines),
    do: %{
      kind: :inducer,
      label: taxon_label(s),
      text: "the Inducer #{s[:name]}",
      ref: {:inducer, s[:taxon_id]}
    }

  defp gall_value(%{category: :hosts, value: %{subject: s}}, _lines),
    do: %{
      kind: :host,
      label: taxon_label(s),
      text: "the Host #{s[:name]}",
      ref: {:host, s[:taxon_id]}
    }

  defp gall_value(%{kind: :trait, value: %{trait: trait, value: value}}, _lines),
    do: %{
      kind: :trait,
      trait: trait,
      label: {:text, value},
      text: "#{trait_label(trait)}: #{value}",
      ref: {:trait, trait, value}
    }

  defp gall_value(%{kind: kind, value: v} = entry, _lines) when kind in [:range, :occurrence] do
    prefix =
      case {kind, v[:adjustment]} do
        {:occurrence, _} -> "recorded in"
        {_, :exclude} -> "not in"
        {_, :only} -> "only in"
        _ -> "in"
      end

    place = (v[:place] && (v.place.name || v.place.code)) || entry.words.value_as_written || "?"
    %{kind: :range, label: {:prefixed, prefix, place}, text: "#{prefix} #{place}"}
  end

  defp gall_value(%{kind: :alias, value: v}, _lines),
    do: %{
      kind: :alias,
      label: {:text, v.name},
      text: "the name “#{v.name}”",
      ref: {:alias, v.name}
    }

  defp gall_value(%{kind: :description}, lines) do
    quote = lines |> Enum.flat_map(& &1.quotes) |> Enum.map(& &1.quote) |> List.first()
    %{kind: :description, label: {:clamp, quote || "A description"}, text: "a description"}
  end

  defp gall_value(%{kind: kind}, _lines),
    do: %{kind: :other, label: {:text, humanize(kind)}, text: humanize(kind)}

  defp taxon_label(%{name: name} = t) when is_binary(name), do: {:taxon, name, t[:rank]}
  defp taxon_label(_t), do: {:text, "not settled"}

  @doc """
  The Facts panel of taxon `taxon_id`'s taxonomy: its placement, its name
  with authorship, its synonyms, its common names, its splits and lumps.
  Each is the current Fact when a Source states it
  (`Gallformers.Import.taxonomic_position/1`, `taxon_splits/1`, the
  Sources' taxonomic statements), with every statement of it; else what
  the tree holds, with no statement (the old site's data). Statements
  that don't count (awaiting a curator, declined) sit under their Fact's
  History.
  """
  @spec taxon_panel(integer()) :: [map()]
  def taxon_panel(taxon_id) do
    taxon = Taxa.get_taxon!(taxon_id)
    accepted = Enum.find(taxon.names, &(&1.status == :accepted))
    parent = taxon_id |> Taxa.lineage() |> Enum.drop(-1) |> List.last()
    position = Import.taxonomic_position(taxon_id)
    acts = acts_about(taxon_id)
    act_ids = acts |> Enum.map(& &1.fact_id) |> Enum.uniq()

    split_ids = taxon_id |> Import.taxon_splits() |> Enum.map(& &1.fact_id)

    ids =
      [position.placement && position.placement.fact_id, position.name && position.name.fact_id]
      |> Enum.reject(&is_nil/1)
      |> Kernel.++(act_ids ++ split_ids)
      |> Enum.uniq()

    lines = statement_lines(ids)
    by_fact = acts |> Enum.uniq_by(& &1.fact_id) |> Enum.group_by(& &1.kind)

    {act_facts, act_past} =
      by_fact
      |> Map.values()
      |> List.flatten()
      |> Enum.map(&act_fact(&1, lines))
      |> Enum.split_with(&current?/1)

    act_by = Enum.group_by(act_facts, & &1.category)
    past_by = Enum.group_by(act_past, & &1.category)

    placement =
      cond do
        position.placement ->
          [
            %{
              fact(position.placement.fact_id, :placement, lines)
              | label: placed_label(position.placement.parent),
                text: "the placement " <> placed_text(position.placement.parent)
            }
          ]

        parent ->
          [
            held(
              "tree-placement",
              :placement,
              placed_label(parent),
              "the placement " <> placed_text(parent)
            )
          ]

        true ->
          []
      end

    name_fact =
      cond do
        position.name ->
          n = position.name

          [
            %{
              fact(n.fact_id, :name, lines)
              | label: {:name, n.name, n.rank, n.authorship},
                text: "the name #{n.name}"
            }
          ]

        accepted ->
          [
            held(
              "tree-name",
              :name,
              {:name, accepted.name, taxon.rank, accepted.authorship},
              "the name #{accepted.name}"
            )
          ]

        true ->
          []
      end

    stated_synonyms = for f <- Map.get(act_by, :synonyms, []), do: f.name_key
    stated_common = for f <- Map.get(act_by, :common_names, []), do: f.name_key

    synonyms =
      Map.get(act_by, :synonyms, []) ++
        for s <- Taxa.list_synonyms(taxon_id),
            String.downcase(s.name) not in stated_synonyms,
            do:
              held(
                "tree-syn-#{s.id}",
                :synonym,
                {:synonym, s.name, taxon.rank, s.sensu},
                "the synonym #{s.name}"
              )

    common =
      Map.get(act_by, :common_names, []) ++
        for c <- Taxa.list_common_names(taxon_id),
            String.downcase(c.name) not in stated_common,
            do:
              held(
                "tree-cn-#{c.id}",
                :common_name,
                {:text, c.name},
                "the common name “#{c.name}”"
              )

    splits =
      for s <- Import.taxon_splits(taxon_id) do
        label =
          if s.taxon.taxon_id == taxon_id,
            do: "Split into " <> Enum.map_join(s.into, ", ", & &1.name),
            else: "Split from " <> (s.taxon.name || "?")

        %{fact(s.fact_id, :split, lines) | label: {:text, label}, text: String.downcase(label)}
      end

    lumps =
      for m <- Taxa.merged_into(taxon_id) do
        held(
          "lump-#{m.taxon_id}",
          :lump,
          {:text, "#{m.name || "A taxon"} merged into it"},
          "the lump of #{m.name || "a taxon"}",
          "Merged #{format_date(m.at, :short)}: recorded in the audit trail, not yet a Fact. A lump is a taxonomic act: under the Source that decides it."
        )
      end

    [
      taxon_category("placement", "Placement", placement, past_by[:placement],
        hint: "Where it sits in the tree, and on whose word."
      ),
      taxon_category("name", "Name", name_fact, past_by[:name],
        hint: "Its accepted name, with authorship."
      ),
      taxon_category("synonyms", "Synonyms", synonyms, past_by[:synonyms],
        add: %{kind: :synonym, what: "a synonym", label: "Add a synonym"},
        empty: "No synonyms."
      ),
      taxon_category("common_names", "Common names", common, past_by[:common_names],
        add: %{kind: :common_name, what: "a common name", label: "Add a common name"},
        empty: "No common names."
      ),
      taxon_category("splits", "Splits and lumps", splits ++ lumps, past_by[:splits],
        add: %{kind: :split, what: "a split", label: "Record a split"},
        hint:
          "A split or lump is a taxonomic act: it is made under the authority of the Source whose statement decides it. Gallformers may state one as an exception.",
        empty: "Never split or lumped."
      )
    ]
  end

  defp taxon_category(id, title, facts, past, opts) do
    %{
      id: id,
      title: title,
      facts: facts,
      past: past || [],
      subs: [],
      missing: [],
      add: opts[:add],
      hint: opts[:hint],
      empty: Keyword.get(opts, :empty, "Not stated.")
    }
  end

  # The taxonomic statements about `taxon_id` (placing it, naming it, a
  # synonym or common name of it, a split of it) of the Sources that speak
  # of its taxonomy, and of Gallformers' own.
  defp acts_about(taxon_id) do
    source_ids =
      for(s <- Catalog.species_sources(taxon_id, []), s.taxonomy, do: s.id) ++
        Sources.own_source_ids()

    for source_id <- Enum.uniq(source_ids),
        act <- Import.facts_for_source(source_id, gall_ids: []).taxonomy.acts,
        about?(act.value, taxon_id),
        do: act
  end

  defp about?(value, taxon_id) do
    Enum.any?([value[:taxon], value[:accepted]], &match?(%{taxon_id: ^taxon_id}, &1)) or
      Enum.any?(value[:into] || [], &match?(%{taxon_id: ^taxon_id}, &1))
  end

  defp act_fact(%{kind: kind, value: v} = act, lines) do
    {category, fact_kind, label, text, name_key} =
      case kind do
        :placement ->
          {:placement, :placement, placed_label(v[:parent]),
           "the placement " <> placed_text(v[:parent]), nil}

        :name ->
          name = v[:name] || (v[:taxon] && v.taxon.name) || "?"
          {:name, :name, {:name, name, v[:taxon] && v.taxon.rank, nil}, "the name #{name}", nil}

        :synonymy ->
          {:synonyms, :synonym, {:synonym, v.name, nil, nil}, "the synonym #{v.name}",
           String.downcase(v.name)}

        :common_name ->
          {:common_names, :common_name, {:text, v.common_name},
           "the common name “#{v.common_name}”", String.downcase(v.common_name)}

        :split ->
          label = "Split into " <> Enum.map_join(v[:into] || [], ", ", &(&1.name || "?"))
          {:splits, :split, {:text, label}, String.downcase(label), nil}
      end

    act.fact_id
    |> fact(fact_kind, lines)
    |> Map.merge(%{
      category: category,
      standing: act.standing,
      label: label,
      text: text,
      name_key: name_key
    })
    |> drop_same_words()
  end

  defp fact(fact_id, kind, lines),
    do: %{
      key: "f#{fact_id}",
      fact_id: fact_id,
      kind: kind,
      category: nil,
      standing: :current,
      lines: Map.get(lines, fact_id, []),
      held_note: nil,
      label: nil,
      text: nil,
      ref: nil,
      trait: nil,
      name_key: nil
    }

  # What the tree holds with no Source's statement.
  defp held(key, kind, label, text, note \\ nil),
    do: %{
      key: key,
      fact_id: nil,
      kind: kind,
      category: nil,
      standing: :current,
      lines: [],
      held_note:
        note ||
          "No Source states it: the tree holds it from the old site. Once the legacy data is the Gallformers Source's undated base, this is its statement there.",
      label: label,
      text: text,
      ref: nil,
      trait: nil,
      name_key: nil
    }

  defp placed_label(nil), do: {:text, "at the root"}
  defp placed_label(%{name: name} = parent), do: {:placed, name, parent[:rank]}

  defp placed_text(nil), do: "at the root"
  defp placed_text(%{name: name}), do: "under #{name}"

  @doc """
  Every Source's statement of each of `fact_ids`, by Fact ID, oldest
  first: `Gallformers.Import.FactsView.statements/1`, an undated
  statement's `date` "undated".
  """
  @spec statement_lines([integer()]) :: %{integer() => [map()]}
  def statement_lines(fact_ids) do
    Map.new(Import.fact_statements(fact_ids), fn {fact_id, lines} ->
      {fact_id, Enum.map(lines, &%{&1 | date: &1.date || "undated"})}
    end)
  end

  @doc "The key of the Fact a main-view `ref` stands for, or nil."
  @spec key_for([map()], tuple()) :: String.t() | nil
  def key_for(panel, ref), do: Enum.find_value(all_facts(panel), &(&1.ref == ref && &1.key))

  # -- components -------------------------------------------------------------------------

  @doc "The Mockup notice: what is real here and what isn't."
  attr :real, :string, required: true
  slot :inner_block

  def mockup_notice(assigns) do
    ~H"""
    <.notice kind={:warn} title="Mockup: does every Fact edit begin and end in the Facts panel?">
      <p>
        Matter d3b0. Real: {@real} Not real: every action. Forms, tray and Review and apply change only this page; nothing is written, your real tray is never called. The tray starts with examples; Discard empties it (or open with <code>?empty</code>).
      </p>
      <p :if={@inner_block != []} class="mt-1">{render_slot(@inner_block)}</p>
      <p class="mt-1">
        PROPOSED (in the page source): the Facts panel's Edit mode, its Source lines, "✎ in Facts", the tray grouped by authority. Mockups:
        <.link navigate="/dev/mockups/gall-facts/5076?edit">Gall</.link>
        · <.link navigate="/dev/mockups/species-facts/74560?edit">species</.link>
        · <.link navigate="/dev/mockups/genus-facts/Aphis?edit">genus</.link>
        (and <.link navigate="/dev/mockups/gall-facts/821?edit">821</.link>
        · <.link navigate="/dev/mockups/species-facts/74854?edit">its Inducer</.link>
        · <.link navigate="/dev/mockups/genus-facts/Callirhytis?edit">Callirhytis</.link>).
      </p>
    </.notice>
    """
  end

  @doc """
  "✎ in Facts": on the main view in Edit mode, focuses the Fact (or
  category) `to` in the panel and highlights it a moment.
  """
  attr :to, :string, default: nil, doc: "the DOM id in the panel; nil renders nothing"
  attr :label, :string, default: "in Facts"

  def fact_link(assigns) do
    ~H"""
    <!-- PROPOSED: fact_link -->
    <button
      :if={@to}
      type="button"
      data-part="fact-link"
      class="inline-flex items-baseline gap-0.5 whitespace-nowrap text-caption font-normal not-italic text-link hover:underline"
      title="Edit it in the Facts panel"
      aria-label="Edit it in the Facts panel"
      phx-click={
        JS.focus(to: "##{@to}")
        |> JS.transition("bg-sky-soft ring-2 ring-brand", to: "##{@to}", time: 1800)
      }
    >
      <.icon name="ph-pencil-simple" class="size-3 translate-y-0.5" />{@label}
    </button>
    """
  end

  @doc "A Fact's DOM id in the panel, from its key."
  @spec fact_dom(String.t() | nil) :: String.t() | nil
  def fact_dom(nil), do: nil
  def fact_dom(key), do: "pf-" <> dom(key)

  @doc "A category's DOM id in the panel."
  @spec category_dom(String.t()) :: String.t()
  def category_dom(id), do: "pc-" <> dom(id)

  @doc """
  The Facts panel in Edit mode: by category, each Fact with every Source's
  statement on its own line. On the Fact and "+ Add": a Gallformers
  change; on a line: a correction under that Source's authority.
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :categories, :list, required: true
  attr :edit, :map, default: nil
  attr :pick, :map, required: true
  attr :error, :string, default: nil
  attr :items, :list, default: []

  def facts_panel(assigns) do
    assigns = assign(assigns, in_tray: MapSet.new(assigns.items, & &1[:key]))

    ~H"""
    <!-- PROPOSED: facts_panel (facts_view's Edit mode) -->
    <section
      id={@id}
      tabindex="-1"
      class="gf-card scroll-mt-32 overflow-hidden focus:outline-none"
      data-role="facts-panel"
    >
      <header class="border-b border-line bg-surface-2 px-3 py-2">
        <h3 class="gf-facts-title text-ink">{@title}</h3>
        <p class="text-caption text-muted">
          On a Fact, and + Add: a <strong class="font-semibold text-ink-2">Gallformers change</strong>
          (withdraw, correct, add, note), Gallformers' own statement dated when applied. On a Source's line:
          <strong class="font-semibold text-ink-2">a correction under that Source's authority</strong>
          (what it says, read again), at its date, with a note of what was misread.
        </p>
      </header>
      <div class="divide-y divide-line">
        <div
          :for={c <- @categories}
          id={category_dom(c.id)}
          tabindex="-1"
          data-category={c.id}
          class="scroll-mt-32 px-3 py-2 transition-colors focus:outline-none"
        >
          <div class="flex flex-wrap items-baseline gap-x-3">
            <h4 class="gf-facts-category">
              {c.title}
              <span class="font-normal tabular-nums">
                {length(c.facts) + Enum.sum(Enum.map(c.subs, &length(&1.facts)))}
              </span>
            </h4>
            <.button
              :if={c.add}
              variant="ghost"
              size="sm"
              icon="ph-plus"
              class="ml-auto"
              phx-click="mock_add"
              phx-value-category={c.id}
              phx-value-kind={c.add.kind}
              phx-value-what={c.add.what}
            >
              {c.add.label}
            </.button>
          </div>
          <p :if={c.hint} class="text-caption text-muted">{c.hint}</p>
          <ul :if={c.facts != []} class="divide-y divide-line">
            <.panel_fact
              :for={f <- c.facts}
              fact={f}
              edit={@edit}
              pick={@pick}
              error={@error}
              in_tray={MapSet.member?(@in_tray, f.key)}
            />
          </ul>
          <div
            :for={s <- c.subs}
            class="flex flex-col gap-x-2 border-t border-line first-of-type:border-t-0 sm:flex-row"
            data-trait={s.trait}
          >
            <div class="flex items-baseline gap-2 pt-1 sm:w-32 sm:shrink-0 sm:flex-col sm:gap-0 sm:py-1">
              <span class="text-caption text-ink-2">{s.label}</span>
              <button
                type="button"
                class="text-caption text-link hover:underline"
                phx-click="mock_add"
                phx-value-category={c.id}
                phx-value-kind={s.add.kind}
                phx-value-trait={s.trait}
                phx-value-what={s.add.what}
              >
                + Add
              </button>
            </div>
            <div class="min-w-0 flex-1">
              <ul class="divide-y divide-line">
                <.panel_fact
                  :for={f <- s.facts}
                  fact={f}
                  edit={@edit}
                  pick={@pick}
                  error={@error}
                  in_tray={MapSet.member?(@in_tray, f.key)}
                />
              </ul>
              <.mock_editor
                :if={@edit && @edit.key == "add-#{c.id}-#{s.trait}"}
                edit={@edit}
                pick={@pick}
                error={@error}
              />
            </div>
          </div>
          <p
            :if={c.missing != []}
            class="mt-1 flex flex-wrap items-baseline gap-x-2 text-caption text-muted"
          >
            Not recorded:
            <button
              :for={t <- c.missing}
              type="button"
              class="text-link hover:underline"
              phx-click="mock_add"
              phx-value-category={c.id}
              phx-value-kind="trait"
              phx-value-trait={t}
              phx-value-what={"a #{trait_label(t)} value"}
            >
              + {String.downcase(trait_label(t))}
            </button>
          </p>
          <%= for t <- c.missing, @edit && @edit.key == "add-#{c.id}-#{t}" do %>
            <.mock_editor edit={@edit} pick={@pick} error={@error} />
          <% end %>
          <p
            :if={c.facts == [] and c.subs == [] and c.missing == []}
            class="text-caption italic text-muted"
          >
            {c.empty}
          </p>
          <.mock_editor
            :if={@edit && @edit.key == "add-#{c.id}"}
            edit={@edit}
            pick={@pick}
            error={@error}
          />
          <details :if={c.past != []} data-role="history" class="mt-1">
            <summary class="cursor-pointer text-meta text-link">
              History: {length(c.past)} not current
            </summary>
            <ul class="divide-y divide-line">
              <.panel_fact
                :for={f <- c.past}
                fact={f}
                edit={@edit}
                pick={@pick}
                error={@error}
                in_tray={MapSet.member?(@in_tray, f.key)}
              />
            </ul>
          </details>
        </div>
      </div>
    </section>
    """
  end

  attr :fact, :map, required: true
  attr :edit, :map, default: nil
  attr :pick, :map, required: true
  attr :error, :string, default: nil
  attr :in_tray, :boolean, default: false

  defp panel_fact(assigns) do
    ~H"""
    <li
      id={fact_dom(@fact.key)}
      tabindex="-1"
      data-standing={@fact.standing}
      class="scroll-mt-32 rounded-ctl py-1.5 text-meta transition-colors focus:outline-none"
    >
      <div class="flex flex-wrap items-baseline gap-x-2 gap-y-0.5">
        <span
          :if={@fact.standing not in [nil, :current]}
          class="gf-mark gf-mark-standing"
          title="This Fact's standing in Gallformers"
        >
          {@fact.standing}
        </span>
        <span class="inline-flex min-w-0 flex-wrap items-baseline gap-x-1 text-ui text-ink">
          <.fact_label label={@fact.label} />
        </span>
        <span :if={@in_tray} data-part="pending">
          <.chip variant={:info} size="sm">in your tray</.chip>
        </span>
        <span class="ml-auto flex flex-wrap items-center gap-x-1" data-part="gallformers-actions">
          <.button
            :for={{action, label} <- fact_actions(@fact)}
            variant="ghost"
            size="sm"
            phx-click="mock_open"
            phx-value-key={@fact.key}
            phx-value-action={action}
          >
            {label}
          </.button>
        </span>
      </div>
      <ul class="mt-0.5 grid gap-1 border-l-2 border-line pl-2 sm:ml-1" data-part="statements">
        <.statement_line :for={l <- @fact.lines} line={l} fact={@fact} />
        <li :if={@fact.lines == []} class="text-caption text-muted" data-part="held">
          {@fact.held_note || "No Source's statement."}
        </li>
      </ul>
      <.mock_editor :if={@edit && @edit.key == @fact.key} edit={@edit} pick={@pick} error={@error} />
    </li>
    """
  end

  # A lump is in the audit trail, not a Fact: nothing to edit on it here.
  defp fact_actions(%{kind: :lump}), do: []

  defp fact_actions(%{kind: kind}) when kind in [:name, :placement],
    do: [{"correct", "Correct…"}, {"note", "Note…"}]

  defp fact_actions(_fact),
    do: [{"withdraw", "Withdraw"}, {"correct", "Correct…"}, {"note", "Note…"}]

  @doc false
  attr :line, :map, required: true
  attr :fact, :map, required: true

  def statement_line(assigns) do
    assigns =
      assign(assigns, quotes_id: "#{fact_dom(assigns.fact.key)}-q-#{assigns.line.source_id}")

    ~H"""
    <!-- PROPOSED: statement_line -->
    <li data-source={@line.source_id} data-state={@line.state} class="text-caption">
      <div class="flex flex-wrap items-baseline gap-x-2 gap-y-0.5">
        <.link
          navigate={"/source/#{@line.source_id}"}
          class="font-semibold text-ink-2 hover:underline"
        >
          {@line.name}
        </.link>
        <span class="tabular-nums text-muted">{@line.date}</span>
        <span :if={@line.stance == :deny} class="font-semibold text-danger">denies it</span>
        <span :if={@line.words != []} class="text-muted" title="The Source's words">
          {Enum.map_join(@line.words, " · ", &"“#{&1}”")}
        </span>
        <span :if={@line.state == :counts} class="text-muted">· counts</span>
        <span
          :if={@line.state == :awaiting}
          class="gf-mark gf-mark-waiting"
          title="No curator has accepted this statement yet: until one does, it does not count"
        >
          awaiting a curator
        </span>
        <span :if={@line.state == :declined} class="gf-mark gf-mark-standing">declined</span>
        <span :if={@line.state == :declined and @line.reason} class="text-ink-2">
          {@line.reason}
        </span>
        <button
          :if={@line.quotes != []}
          type="button"
          class="text-brand hover:underline"
          phx-click={JS.toggle_class("hidden", to: "##{@quotes_id}")}
          aria-controls={@quotes_id}
        >
          {if length(@line.quotes) == 1, do: "Quote", else: "#{length(@line.quotes)} quotes"}
        </button>
        <button
          :if={@fact.kind != :lump}
          type="button"
          class="ml-auto text-link hover:underline"
          data-part="source-correct"
          phx-click="mock_open"
          phx-value-key={@fact.key}
          phx-value-action="source_correct"
          phx-value-source={@line.source_id}
        >
          Correct {@line.name}'s statement…
        </button>
      </div>
      <p :if={@line.statement} class="text-ink-2">The Source: {@line.statement}</p>
      <div :if={@line.quotes != []} id={@quotes_id} class="mt-0.5 grid hidden gap-0.5">
        <.source_quote :for={q <- @line.quotes} page={q.page && "p. #{q.page}"}>
          {q.quote}
        </.source_quote>
      </div>
    </li>
    """
  end

  attr :label, :any, required: true

  defp fact_label(assigns) do
    ~H"""
    <%= case @label do %>
      <% {:taxon, name, rank} -> %>
        <span :if={rank not in [nil, :species]} class="text-caption text-ink-2">{rank}</span>
        <span class="font-medium">
          <.taxon_name name={name} rank={to_string(rank || :species)} />
        </span>
      <% {:placed, name, rank} -> %>
        <span class="text-ink-2">under</span>
        <span :if={rank} class="text-caption text-ink-2">{rank}</span>
        <span class="font-medium"><.taxon_name name={name} rank={to_string(rank || :genus)} /></span>
      <% {:name, name, rank, authorship} -> %>
        <span class="font-medium">
          <.taxon_name name={name} rank={to_string(rank || :species)} />
        </span>
        <span :if={authorship} class="text-ink-2">{authorship}</span>
        <span :if={!authorship} class="text-caption text-muted">no authorship recorded</span>
      <% {:synonym, name, rank, sensu} -> %>
        <span class="font-medium">
          <.taxon_name name={name} rank={to_string(rank || :species)} />
        </span>
        <span :if={sensu} class="text-caption text-muted">sensu {sensu}</span>
      <% {:prefixed, prefix, text} -> %>
        <span class="text-ink-2">{prefix}</span> <span class="font-medium">{text}</span>
      <% {:clamp, text} -> %>
        <span class="line-clamp-2">{text}</span>
      <% {:text, text} -> %>
        <span class="font-medium">{text}</span>
    <% end %>
    """
  end

  attr :edit, :map, required: true
  attr :pick, :map, required: true
  attr :error, :string, default: nil

  # The open action's form: the real `fact_editor`, its events handled by
  # `handle/3`.
  defp mock_editor(assigns) do
    assigns = assign(assigns, form: form_for_edit(assigns.edit))

    ~H"""
    <div
      class="mt-1"
      data-authority={if @edit.action == "source_correct", do: "source", else: "gallformers"}
    >
      <.fact_editor
        id="mock-editor"
        title={@form.title}
        on_submit="mock_submit"
        pick={@pick}
        search_label={@form.search}
        values={@form.values}
        note_label={@form.note}
        error={@error}
        save_text={@form.save}
        save_variant={@form.variant}
      >
        <%= cond do %>
          <% @edit.action == "source_correct" -> %>
            <div role="radiogroup" aria-label={"What #{@edit.line.name} says"} class="grid gap-1.5">
              <.radio_card
                id="mock-choice-withdraw"
                name="choice"
                value="withdraw"
                checked={@edit.choice == "withdraw"}
                summary="Its statement goes. The Fact and the other Sources' statements of it stay."
                phx-click="mock_choice"
                phx-value-choice="withdraw"
              >
                <:label>It doesn't say this</:label>
              </.radio_card>
              <.radio_card
                id="mock-choice-change"
                name="choice"
                value="change"
                checked={@edit.choice == "change"}
                summary="Its statement moves to what it says, still at its date."
                phx-click="mock_choice"
                phx-value-choice="change"
              >
                <:label>It says something else</:label>
                <:follow>
                  <.value_input edit={@edit} pick={@pick} />
                </:follow>
              </.radio_card>
            </div>
          <% @form.input -> %>
            <.value_input edit={@edit} pick={@pick} />
          <% true -> %>
        <% end %>
      </.fact_editor>
    </div>
    """
  end

  attr :edit, :map, required: true
  attr :pick, :map, required: true

  # What it should be: a taxon search, a Trait's values, or words.
  defp value_input(%{edit: %{kind: kind}} = assigns) when kind in [:host, :inducer, :placement] do
    assigns = assign(assigns, label: search_label(kind))

    ~H"""
    <.typeahead
      id="mock-editor-follow-taxon"
      label={@label}
      placeholder="Type a name…"
      search_event="search_taxon"
      select_event="select_taxon"
      clear_event="clear_taxon"
      query={@pick.query}
      results={@pick.results}
      selected={@pick.selected}
      display_fn={& &1.name}
      group_key={:group}
    >
      <:result :let={result}>
        <span class="italic">{result.name}</span>
        <span :if={result.meta != ""} class="ml-1 text-caption text-muted">{result.meta}</span>
      </:result>
    </.typeahead>
    """
  end

  defp value_input(%{edit: %{kind: :trait, trait: trait}} = assigns) do
    assigns = assign(assigns, values: trait_values(trait))

    ~H"""
    <.review_value_list
      id="mock-editor-follow-values"
      type="checkbox"
      values={@values}
      selected={@pick.values}
      on_pick="toggle_value"
    />
    """
  end

  defp value_input(%{edit: %{kind: :range}} = assigns) do
    ~H"""
    <div class="flex flex-wrap items-end gap-2">
      <div class="grid gap-0.5">
        <label for="mock-editor-where" class="gf-label-sm">How</label>
        <select id="mock-editor-where" name="where" class="gf-select h-8 w-auto">
          <option value="not in">not in</option>
          <option value="only in">only in</option>
          <option value="recorded in">recorded in (found there)</option>
        </select>
      </div>
      <div class="grid min-w-0 flex-1 gap-0.5">
        <label for="mock-editor-text" class="gf-label-sm">The place</label>
        <input
          id="mock-editor-text"
          name="text"
          class="gf-input"
          placeholder="A state, province or country"
          autocomplete="off"
        />
      </div>
    </div>
    """
  end

  defp value_input(assigns) do
    assigns = assign(assigns, label: text_label(assigns.edit.kind))

    ~H"""
    <div class="grid gap-0.5">
      <label for="mock-editor-text" class="gf-label-sm">{@label}</label>
      <input id="mock-editor-text" name="text" class="gf-input" autocomplete="off" />
    </div>
    """
  end

  defp search_label(:host), do: "The plant: species and below, genera, sections"
  defp search_label(:inducer), do: "The Inducer"
  defp search_label(:placement), do: "The parent"

  defp text_label(:alias), do: "The common name"
  defp text_label(:common_name), do: "The common name"
  defp text_label(:synonym), do: "The synonym, as written"
  defp text_label(:name), do: "The name, with its authorship"
  defp text_label(:split), do: "Split into (the daughter taxa's names)"
  defp text_label(:description), do: "The description"
  defp text_label(_kind), do: "What it should be"

  defp trait_values(trait), do: Catalog.trait_definitions() |> Map.get(trait, %{}) |> Enum.sort()

  # The form an action opens.
  defp form_for_edit(%{action: "withdraw"}),
    do: %{
      title:
        "Withdraw, as a Gallformers change: Gallformers' statement that it isn't so, dated when you apply. Every Source's statement stays; the Fact's standing follows.",
      search: nil,
      values: nil,
      input: false,
      note: "Why (required)",
      save: "Add to tray",
      variant: "danger"
    }

  defp form_for_edit(%{action: "note"}),
    do: %{
      title:
        "A note on this Fact, as a Gallformers change: shown with it; it doesn't change what it says.",
      search: nil,
      values: nil,
      input: false,
      note: "Note (required)",
      save: "Add to tray",
      variant: "primary"
    }

  defp form_for_edit(%{action: "correct"} = edit),
    do:
      %{
        title:
          "Correct, as a Gallformers change: Gallformers states what it should be (and denies this), dated when you apply. The Sources' statements stay as they are.",
        search: nil,
        values: nil,
        input: true,
        note: "Why (optional: else asked once at Review and apply)",
        save: "Add to tray",
        variant: "primary"
      }
      |> with_value(edit)

  defp form_for_edit(%{action: "add", what: what} = edit),
    do:
      %{
        title:
          "Add #{what || "a Fact"}, as a Gallformers change: Gallformers' statement of it, dated when you apply.",
        search: nil,
        values: nil,
        input: true,
        note: "Why (optional: else asked once at Review and apply)",
        save: "Add to tray",
        variant: "primary"
      }
      |> with_value(edit)

  defp form_for_edit(%{action: "source_correct", line: line}),
    do: %{
      title:
        "Correct #{line.name}'s statement: what it says, read again. Made under #{line.name}'s authority, at its date (#{line.date}); you and the misreading are audited.",
      search: nil,
      values: nil,
      input: false,
      note: "What was misread (required)",
      save: "Add the correction to tray",
      variant: "primary"
    }

  # The real `fact_editor`'s own search and values, where they fit.
  defp with_value(form, %{kind: kind}) when kind in [:host, :inducer, :placement],
    do: %{form | search: search_label(kind), input: false}

  defp with_value(form, %{kind: :trait, trait: trait}),
    do: %{form | values: trait_values(trait), input: false}

  defp with_value(form, _edit), do: form

  @doc """
  The tray, pinned at the foot, its items grouped by authority: Gallformers'
  changes, the corrections to each Source, the editorial edits. Each Fact
  group applies as one package.
  """
  attr :items, :list, required: true
  attr :open, :any, default: :wide, doc: "true, false, or :wide (open on wide screens only)"

  def authority_tray(assigns) do
    assigns = assign(assigns, groups: groups(assigns.items))

    ~H"""
    <!-- PROPOSED: authority_tray (change_tray grouped by authority) -->
    <div
      :if={@items != []}
      id="mock-tray"
      class="fixed inset-x-0 bottom-0 z-40 border-t border-line bg-surface shadow-float"
    >
      <div class="mx-auto flex max-w-page flex-col gap-2 px-page-x py-2.5">
        <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
          <span data-part="count" class="font-semibold text-ink">
            {length(@items)} {if length(@items) == 1, do: "change", else: "changes"} in your tray
          </span>
          <span
            class="order-last flex w-full flex-wrap gap-1.5 md:order-none md:w-auto md:min-w-0 md:flex-1"
            data-part="groups"
          >
            <.chip :for={g <- @groups} variant={:neutral} size="sm">
              {g.short} · {length(g.items)}
            </.chip>
          </span>
          <span class="ml-auto flex flex-wrap items-center gap-2">
            <.button
              :if={@open != true}
              variant="ghost"
              size="sm"
              class={@open == :wide && "md:hidden"}
              phx-click="mock_tray_toggle"
              phx-value-open="true"
            >
              Show
            </.button>
            <.button
              :if={@open != false}
              variant="ghost"
              size="sm"
              class={@open == :wide && "hidden md:inline-flex"}
              phx-click="mock_tray_toggle"
              phx-value-open="false"
            >
              Hide
            </.button>
            <.button variant="ghost" size="sm" phx-click="tray_discard">Discard</.button>
            <.button variant="primary" size="sm" phx-click="tray_review">Review and apply</.button>
          </span>
        </div>
        <div
          :if={@open != false}
          class={[
            "max-h-40 gap-x-6 gap-y-3 overflow-y-auto border-t border-line pt-2 md:max-h-72 md:grid-cols-2 xl:grid-cols-3",
            if(@open == :wide, do: "hidden md:grid", else: "grid")
          ]}
        >
          <section :for={g <- @groups} data-authority={g.id} class="min-w-0">
            <h3 class="text-meta font-semibold text-ink">
              {g.title} <span class="font-normal tabular-nums text-muted">{length(g.items)}</span>
            </h3>
            <p class="text-caption text-muted">{g.applies}</p>
            <ul class="mt-1 divide-y divide-line">
              <li :for={item <- g.items} class="flex items-baseline gap-2 py-1 text-meta">
                <span class="min-w-0 flex-1 text-ink-2">{item.text}</span>
                <button
                  type="button"
                  phx-click="remove_item"
                  phx-value-id={item.id}
                  class="text-muted hover:text-danger"
                  aria-label={"Take out: #{item.text}"}
                >
                  <.icon name="ph-x" class="size-3.5" />
                </button>
              </li>
            </ul>
          </section>
        </div>
      </div>
    </div>
    """
  end

  @doc "Review and apply, one `review_apply` per authority."
  attr :show, :boolean, required: true
  attr :items, :list, required: true
  attr :evidence, :map, required: true
  attr :confirmed, :list, default: []
  attr :source, :map, default: nil
  attr :source_query, :string, default: ""
  attr :source_results, :list, default: []

  def review_dialog(assigns) do
    assigns = assign(assigns, groups: groups(assigns.items))

    ~H"""
    <.dialog
      :if={@show and @items != []}
      id="mock-review"
      title="Review and apply"
      size={:lg}
      show
      on_cancel={JS.push("mock_review_close")}
    >
      <div class="flex flex-col gap-section">
        <p class="text-ui text-ink-2">
          One package per group, all through the one ingestion path. Each group applies on its own.
        </p>
        <.section :for={g <- @groups} title={g.title} count={length(g.items)} level={3}>
          <p class="mb-2 text-meta text-muted">{g.applies}</p>
          <.review_apply
            id={"mock-review-#{g.id}"}
            items={g.items}
            evidence={@evidence}
            confirmed={@confirmed}
            source={@source}
            source_query={@source_query}
            source_results={@source_results}
          />
        </.section>
      </div>
    </.dialog>
    """
  end

  defp groups(items) do
    items
    |> Enum.group_by(& &1.group)
    |> Enum.map(fn {group, items} -> Map.put(group_words(group), :items, items) end)
    |> Enum.sort_by(& &1.order)
  end

  defp group_words(:gallformers),
    do: %{
      id: "gallformers",
      order: {0, ""},
      short: "Gallformers",
      title: "Gallformers",
      applies:
        "Applies as one Gallformers change: one package of the Gallformers Source, dated when you apply, audited as yours."
    }

  defp group_words({:source, id, name}),
    do: %{
      id: "source-#{id}",
      order: {1, name},
      short: "Corrections to #{name}",
      title: "Corrections to #{name}",
      applies:
        "Applies as one correction package of #{name}: under its authority, at its date; you and each misreading are audited."
    }

  defp group_words(:editorial),
    do: %{
      id: "editorial",
      order: {2, ""},
      short: "Editorial",
      title: "Editorial",
      applies: "Not Facts: applied to the record itself, not as a package of any Source."
    }

  defp dom(value), do: value |> to_string() |> String.replace(~r/[^A-Za-z0-9_-]+/, "-")

  defp humanize(nil), do: ""
  defp humanize(text), do: text |> to_string() |> String.replace("_", " ")
end
