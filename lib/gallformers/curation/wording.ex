defmodule Gallformers.Curation.Wording do
  @moduledoc """
  The tray in words (matter `ec2c`, "Wording"): each item's display text
  and each preview flag's, so the tray reads like the changes page. A Fact
  is worded by the change log itself (`Gallformers.Audit.ChangeLog.fact_words/1`):
  "host: Quercus alba", "inducer: …", "season: Spring", "range exclude:
  Europe", "recorded in Virginia", "also known as …"; the item says what
  it does to it ("Add host: Quercus alba", "Deny …" (Gallformers says it isn't so), "Correct season:
  Spring → Summer", "Note on …"). The flags, the editorial fields and a
  correction's "old → new" are the tray's own: the change log has no
  words for them.
  """
  alias Gallformers.Audit.ChangeLog
  alias Gallformers.Catalog
  alias Gallformers.Catalog.Gall
  alias Gallformers.Places
  alias Gallformers.Sources
  alias Gallformers.Sources.Source
  alias Gallformers.Taxa

  @doc """
  What a Fact key says, in the change log's words
  (`Gallformers.Audit.ChangeLog.fact_words/1`), its ids looked up.
  """
  @spec what(term()) :: String.t()
  def what(key), do: key |> fact() |> ChangeLog.fact_words()

  defp fact({:inducer, taxon_id}), do: {:relationship, "inducer_of", taxon_name(taxon_id)}
  defp fact({:host, taxon_id}), do: {:relationship, "host_of", taxon_name(taxon_id)}
  defp fact({:trait, trait, value}), do: {:trait, trait, value}
  defp fact({:alias, name}), do: {:alias, name}

  defp fact({:range, adjustment, place_id}),
    do: {:range, to_string(adjustment), place_name(place_id)}

  defp fact({:occurrence, place_id}), do: {:occurrence, place_name(place_id)}

  @doc "An item's display text, from its decoded spec."
  @spec item_text(map()) :: String.t()
  def item_text(%{kind: :fact, action: :add, key: key, when: seen}) when is_binary(seen),
    do: "Add #{what(key)} (#{seen})"

  def item_text(%{kind: :fact, action: :add, key: key}), do: "Add " <> what(key)
  def item_text(%{kind: :fact, action: :withdraw, key: key}), do: "Deny " <> what(key)

  def item_text(%{kind: :fact, action: :correct, key: key, to: to}),
    do: "Correct #{label(key)}: #{value(key)} → #{value(to)}"

  def item_text(%{kind: :note, key: key}), do: "Note on " <> what(key)

  def item_text(%{kind: :photo, observation_id: observation_id, photo_id: photo_id}),
    do: "Add photo #{photo_id} of iNaturalist observation #{observation_id}"

  def item_text(%{kind: :editorial, field: field, value: value}),
    do: "#{field_label(field)}: #{field_value(field, value)}"

  defp label({:trait, trait, _value}), do: String.replace(trait, "_", " ")
  defp label({:range, adjustment, _place}), do: "range #{adjustment}"
  defp label({:alias, _name}), do: "also known as"
  defp label({:occurrence, _place}), do: "recorded in"
  defp label({role, _id}), do: Atom.to_string(role)

  @doc """
  An authority's group in the tray, in words: its `title` (Review's
  section), `short` (the tray's chip) and what applying it does (`applies`).
  """
  @spec authority_words(Gallformers.Curation.authority()) :: %{
          title: String.t(),
          short: String.t(),
          applies: String.t()
        }
  def authority_words(:gallformers),
    do: %{
      title: "Gallformers",
      short: "Gallformers",
      applies:
        "Applies as one Gallformers change: one package of the Gallformers Source, dated when you apply, audited as yours."
    }

  def authority_words(:editorial),
    do: %{
      title: "Editorial",
      short: "Editorial",
      applies: "Not Facts: applied to the record itself, not as a package of any Source."
    }

  @doc "What a key's Fact is, in words: a plant's or a place's name, a Trait value, a name."
  @spec value(Gallformers.Curation.Key.t()) :: String.t()
  def value({:trait, _trait, value}), do: value
  def value({:range, _adjustment, place_id}), do: place_name(place_id)
  def value({:alias, name}), do: name
  def value({:occurrence, place_id}), do: place_name(place_id)
  def value({_role, taxon_id}), do: taxon_name(taxon_id)

  defp field_label(:completeness), do: "Completeness"
  defp field_label(:abundance), do: "Abundance"
  defp field_label(:code), do: "Gallformers code"
  defp field_label(:name_parts), do: "Name parts"
  defp field_label(:default_source_id), do: "Default Source"
  defp field_label(:name), do: "Name"
  defp field_label(:authorship), do: "Authorship"
  defp field_label(:synonyms), do: "Synonyms"
  defp field_label(:range), do: "Range"

  defp field_value(:completeness, true), do: "complete"
  defp field_value(:completeness, false), do: "not complete"
  defp field_value(_field, nil), do: "none"

  defp field_value(:abundance, id) do
    Enum.find_value(Catalog.list_abundances(), "unknown", &(&1.id == id && &1.abundance))
  end

  defp field_value(:default_source_id, id) do
    case Sources.get_source(id) do
      nil -> "unknown"
      source -> source_name(source)
    end
  end

  defp field_value(:name_parts, parts) do
    parts
    |> Enum.sort()
    |> Enum.map_join(", ", fn
      {:host_qualifier_taxon_id, nil} -> "no host qualifier"
      {:host_qualifier_taxon_id, id} -> "host qualifier " <> taxon_name(id)
      {part, nil} -> "no #{String.replace(Atom.to_string(part), "_", " ")}"
      {part, text} -> "#{String.replace(Atom.to_string(part), "_", " ")} '#{text}'"
    end)
  end

  defp field_value(:synonyms, []), do: "none"

  defp field_value(:synonyms, synonyms) do
    Enum.map_join(synonyms, ", ", fn
      %{name: name, sensu: nil} -> name
      %{name: name, sensu: sensu} -> "#{name} sensu #{sensu}"
    end)
  end

  defp field_value(:range, entries), do: "#{length(entries)} places"
  defp field_value(_field, value), do: to_string(value)

  @doc "The name of an item's subject."
  @spec subject_name({:gall | :plant, integer()}) :: String.t()
  def subject_name({:gall, id}) do
    case Catalog.get_gall(id) do
      nil -> "Gall #{id}"
      gall -> Gall.display_name(gall)
    end
  end

  def subject_name({:plant, id}), do: taxon_name(id)

  @doc "What a Source is called on the review pages (\"Weld 1959\"), or its title."
  @spec source_name(Source.t()) :: String.t()
  def source_name(%Source{} = source), do: Sources.short_name(source) || source.title

  @doc "A preview flag in words."
  @spec flag_text(term()) :: String.t()
  def flag_text(:new), do: "New"

  def flag_text({:held, sources}),
    do: "Already held: " <> Enum.map_join(sources, ", ", & &1.name)

  def flag_text({:supersedes, statements}),
    do: "Supersedes " <> Enum.map_join(statements, "; ", &statement_words/1)

  def flag_text({:changed_since, %{name: name}, at}),
    do:
      "#{name} changed this since you added it (#{Calendar.strftime(at, "%b %-d, %H:%M")} UTC): review again"

  def flag_text(:needs_confirmation),
    do: "Needs confirmation: it changes how the Gall is named or linked from outside"

  def flag_text(:adds_statement),
    do:
      "Adds Gallformers' statement, so the Fact keeps Gallformers' support if a Source is retracted"

  def flag_text(:editorial), do: "Editorial: no evidence needed"

  def flag_text(:needs_reason),
    do:
      "A reason is needed: it supersedes another Source's statement (give text, an Observation or a Source)"

  def flag_text({:blocked, reason}), do: "Can't apply: " <> reason

  defp statement_words(%{source: source, words: nil}), do: "#{possessive(source)} statement"
  defp statement_words(%{source: source, words: words}), do: "#{possessive(source)} '#{words}'"

  defp possessive(name) do
    if String.ends_with?(name, "s"), do: name <> "'", else: name <> "'s"
  end

  defp taxon_name(id) do
    case Taxa.get_taxon(id) do
      nil -> "taxon #{id}"
      taxon -> Taxa.accepted_name(taxon)
    end
  end

  defp place_name(id) do
    case Places.get_place(id) do
      nil -> "place #{id}"
      place -> place.name
    end
  end
end
