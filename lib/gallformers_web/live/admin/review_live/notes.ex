defmodule GallformersWeb.Admin.ReviewLive.Notes do
  @moduledoc """
  The Gallformers notes on their Source's review page (`6611` Task 7, after
  screen 4 of the approved design): which group a note falls in by what it
  holds, what it adds (one chip per kind of Fact), and what it set aside.
  Pure functions over a note's Gall, text and gall batch; the page's data
  comes from `GallformersWeb.Admin.ReviewLive.Loader.notes_page/1`.

  The groups:

    * `:undescribed` — the note of an undescribed Gall (no current
      species-rank Inducer, as `Gallformers.Import.NotePackage` and the
      Gall page decide it), most often its only description.
    * `:observations` — a note linking to iNaturalist Observations or
      BugGuide (or whose Facts cite Observations): Hosts and sightings.
    * `:other` — the rest: identification tips, taxonomy, rulings.
  """

  alias Gallformers.Import.QueueItem

  @type group :: :undescribed | :observations | :other

  @groups [
    %{
      id: :undescribed,
      title: "Undescribed Galls",
      explanation:
        "Most often the note is the Gall's only description: its Traits, Hosts and where it " <>
          "was seen."
    },
    %{
      id: :observations,
      title: "Hosts and sightings from Observations",
      explanation:
        "Hosts added from iNat or BugGuide Observations, and where and when the Gall was " <>
          "seen. The Observation is the evidence."
    },
    %{
      id: :other,
      title: "Taxonomy, rulings and other notes",
      explanation:
        "Notes with no Observation: identification tips, the state of the taxonomy, rulings " <>
          "between Sources. Few Facts; rulings and placeholders are set aside, not applied."
    }
  ]

  @observation_link ~r{inaturalist\.org/observations|bugguide\.net}i

  # Hosts named one by one up to this many; more are counted.
  @named_hosts 2
  # Places named one by one up to this many; more are counted.
  @named_places 3

  @doc "The groups, in the design's order: `%{id, title, explanation}`."
  @spec groups() :: [%{id: group(), title: String.t(), explanation: String.t()}]
  def groups, do: @groups

  @doc """
  The group of a note: `undescribed` (its Gall has no current species-rank
  Inducer), `text` (the note's text, nil when not known) and
  `observations` (whether its Facts' evidence cites Observations).
  """
  @spec group(%{undescribed: boolean(), text: String.t() | nil, observations: boolean()}) ::
          group()
  def group(%{undescribed: true}), do: :undescribed
  def group(%{observations: true}), do: :observations

  def group(%{text: text}) when is_binary(text),
    do: if(Regex.match?(@observation_link, text), do: :observations, else: :other)

  def group(_note), do: :other

  @doc "Whether any Fact of a gall batch's `content` cites an Observation in its evidence."
  @spec observations?(map() | nil) :: boolean()
  def observations?(content) do
    content
    |> facts()
    |> Enum.flat_map(&List.wrap(&1["evidence"]))
    |> Enum.any?(&(is_map(&1) and List.wrap(&1["observations"]) != []))
  end

  @doc """
  What a note's gall batch (`content`) adds, as chips: its description, its
  Hosts (named when there are two at most), its Inducer, each Trait (with
  how many values), the places it was seen (named by `places`, a map of
  place code to name, else as written), then other Facts by what they are.
  Denials add nothing.
  """
  @spec adds(map() | nil, %{String.t() => String.t()}) :: [String.t()]
  def adds(content, places) do
    facts = content |> facts() |> Enum.reject(&(&1["stance"] == "deny"))
    taxa = for t <- List.wrap((content || %{})["taxa"]), is_map(t), into: %{}, do: {t["ref"], t}

    Enum.concat([
      if(Enum.any?(facts, &(&1["kind"] == "description")), do: ["description"], else: []),
      hosts(facts, taxa),
      if(Enum.any?(facts, &relationship?(&1, "inducer_of")), do: ["Inducer"], else: []),
      traits(facts),
      seen(facts, places),
      others(facts)
    ])
  end

  defp facts(content) when is_map(content),
    do: content |> Map.get("facts") |> List.wrap() |> Enum.filter(&is_map/1)

  defp facts(_content), do: []

  defp relationship?(fact, type), do: fact["kind"] == "relationship" and fact["type"] == type

  defp hosts(facts, taxa) do
    names =
      for f <- facts, relationship?(f, "host_of"), uniq: true do
        get_in(taxa, [f["subject"], "name_as_written"]) || f["subject"]
      end

    if length(names) <= @named_hosts,
      do: Enum.map(names, &"Host #{&1}"),
      else: ["#{length(names)} Hosts"]
  end

  defp traits(facts) do
    facts
    |> Enum.filter(&(&1["kind"] == "trait" and is_binary(&1["trait"])))
    |> group_in_order(& &1["trait"])
    |> Enum.map(fn {trait, values} -> counted(length(values), humanize(trait)) end)
  end

  defp seen(facts, places) do
    names =
      for f <- facts, f["kind"] == "occurrence", is_map(f["place"]), uniq: true do
        code = f["place"]["value"]
        Map.get(places, code) || f["place"]["as_written"] || code
      end

    if length(names) <= @named_places,
      do: Enum.map(names, &"seen in #{&1}"),
      else: ["seen in #{length(names)} places"]
  end

  defp others(facts) do
    facts
    |> Enum.flat_map(fn
      %{"kind" => "relationship", "type" => type} when type not in ["host_of", "inducer_of"] ->
        [humanize(type)]

      %{"kind" => "alias"} ->
        ["common name"]

      %{"kind" => "range"} ->
        ["range"]

      _fact ->
        []
    end)
    |> group_in_order(& &1)
    |> Enum.map(fn {label, all} -> counted(length(all), label) end)
  end

  # Groups `list` by `key`, the groups in the order their first member comes.
  defp group_in_order(list, key) do
    groups = Enum.group_by(list, key)
    list |> Enum.map(key) |> Enum.uniq() |> Enum.map(&{&1, Map.fetch!(groups, &1)})
  end

  defp counted(1, label), do: label
  defp counted(n, label), do: "#{n} #{plural(label)}"

  defp plural(label) do
    if String.ends_with?(label, "s"), do: label, else: label <> "s"
  end

  defp humanize(text), do: String.replace(text, "_", " ")

  @doc """
  What a note set aside, as muted chips: its terms and statements set
  aside (`:set_aside_term` and `:set_aside_statement` queue items, and
  questions about its Trait terms, `:trait_term`) still open or kept as
  they are; one mapped to a value or stated is no longer set aside.
  """
  @spec set_aside([QueueItem.t()]) :: [String.t()]
  def set_aside(items) do
    aside = Enum.filter(items, &still_aside?/1)

    [{[:set_aside_term, :trait_term], "term"}, {[:set_aside_statement], "statement"}]
    |> Enum.flat_map(fn {kinds, noun} ->
      case Enum.count(aside, &(&1.kind in kinds)) do
        0 -> []
        1 -> ["1 #{noun} set aside"]
        n -> ["#{n} #{plural(noun)} set aside"]
      end
    end)
  end

  defp still_aside?(%QueueItem{kind: kind} = item)
       when kind in [:set_aside_term, :set_aside_statement, :trait_term],
       do: item.status == :open or match?(%{"keep" => true}, item.decision)

  defp still_aside?(_item), do: false
end
