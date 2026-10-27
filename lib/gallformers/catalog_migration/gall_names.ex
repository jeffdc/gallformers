defmodule Gallformers.CatalogMigration.GallNames do
  @moduledoc """
  Gall names from today's gall rows (`86e7` §4, Task 3): each Gall's name
  parts read from its name, its name derived from them
  (`Gallformers.Catalog.GallName`), and today's name kept as the override
  only where the derived name differs — so every name shown stays as it is,
  with as few overrides as possible.

  The parts:

    * **generation** — the Gall's generation, as the name-suffix mapping
      gives it (`Gallformers.CatalogMigration.NameSuffixes`);
    * **form label** — a gall-form or plant-part row's parenthetical
      (`NameSuffixes.qualifiers/3`), e.g. "(australis)", "(leaf snap)";
    * **Host qualifier** — a host-scoped row's "(on X)", X resolved to a
      plant taxon by name (accepted or synonym, `Gallformers.Taxa.resolve_name/2`
      in Plantae); a name matching no plant, or several, is not resolved;
    * **descriptor** — for a Gall whose Inducer is above species, or which
      has none: the name's stem after its base — after the genus
      ("Belonocnema q-brandegeei-midrib-gall") or after the "Unknown
      (Family)" prefix ("Unknown (Cynipidae) q-havardii-cup-gall").

  Where a name has several form labels or Host qualifiers, the first of
  each is the part and the override keeps the name. Parentheticals the
  mapping does not read as name parts (authorship, a pathovar, an unknown
  token) are left to the override too. A Gall whose parts give no name
  (no Inducer and no descriptor, …) keeps today's name as its stored name,
  with no override.

  The report reconciles the Galls (derived + overridden + not derivable)
  and the `"gall_names"` worksheet lists every Gall with an override or no
  derivation, its derived name and why.
  """

  alias Gallformers.Catalog.GallName
  alias Gallformers.CatalogMigration.NameSuffixes
  alias Gallformers.CatalogMigration.Report
  alias Gallformers.Taxa

  @type result :: %{
          gall_id: integer(),
          name: String.t(),
          derived: String.t() | nil,
          stored_name: String.t(),
          name_override: String.t() | nil,
          form_label: String.t() | nil,
          host_qualifier: String.t() | nil,
          host_qualifier_taxon_id: integer() | nil,
          descriptor: String.t() | nil,
          category: String.t() | nil,
          reason: String.t() | nil
        }

  @typedoc "The Gall's generation as the migration knows it: its value's ID and name qualifier."
  @type generation :: %{id: integer(), qualifier: String.t() | nil} | nil

  @unknown_prefix ~r/^Unknown \((?:[^()]|\([^()]*\))*\) (.+)$/u

  @columns ~w(gall_id name derived name_override category reason form_label host_qualifier descriptor)

  @doc """
  Reads gall row `row`'s (`id`, `name`) name parts and derives its name,
  with its Inducer `inducer_id` at `level` (`:species`, `:genus`, `:family`
  or nil for none) and its `generation`.
  """
  @spec read(NameSuffixes.t(), map(), integer() | nil, atom() | nil, generation()) :: result()
  def read(suffixes, row, inducer_id, level, generation) do
    # Today's name exactly (trimmed), so an override keeps it as it is.
    name = String.trim(row.name)
    {stem, qualifiers} = NameSuffixes.qualifiers(suffixes, row.id, name)

    forms = for {:form, text} <- qualifiers, do: text
    hosts = for {:host, text} <- qualifiers, do: text
    {host_id, host_issue} = resolve_host(List.first(hosts))

    parts = %{
      inducer_taxon_id: inducer_id,
      generation_value_id: generation && generation.id,
      form_label: List.first(forms),
      host_qualifier_taxon_id: host_id,
      descriptor: descriptor(stem, level)
    }

    issues =
      [
        unread_issue(qualifiers),
        host_issue,
        several_issue(forms, hosts),
        generation_issue(qualifiers, generation)
      ]
      |> Enum.reject(&is_nil/1)

    %{
      gall_id: row.id,
      name: name,
      form_label: parts.form_label,
      host_qualifier: List.first(hosts),
      host_qualifier_taxon_id: host_id,
      descriptor: parts.descriptor
    }
    |> Map.merge(outcome(GallName.derive(parts), name, issues))
  end

  # The derived name and override, or today's name when there is none.
  defp outcome({:ok, name}, name, _issues),
    do: %{derived: name, stored_name: name, name_override: nil, category: nil, reason: nil}

  defp outcome({:ok, derived}, name, issues) do
    {category, reason} =
      case issues do
        [] -> {"other difference", "differs from the derived name (order or base)"}
        [{category, _} | _] -> {category, Enum.map_join(issues, "; ", &elem(&1, 1))}
      end

    %{
      derived: derived,
      stored_name: derived,
      name_override: name,
      category: category,
      reason: reason
    }
  end

  defp outcome({:error, why}, name, issues) do
    reason = Enum.map_join([{nil, "no derived name (#{why})"} | issues], "; ", &elem(&1, 1))

    %{
      derived: nil,
      stored_name: name,
      name_override: nil,
      category: "not derivable",
      reason: reason
    }
  end

  # An undescribed Gall's descriptor: its stem after its base.
  defp descriptor(_stem, :species), do: nil

  defp descriptor(stem, level) do
    case Regex.run(@unknown_prefix, stem) do
      [_all, rest] ->
        rest

      nil when level == :genus ->
        case String.split(stem, " ", parts: 2) do
          [_genus, rest] -> rest
          [_genus] -> nil
        end

      nil ->
        nil
    end
  end

  defp resolve_host(nil), do: {nil, nil}

  defp resolve_host(text) do
    case Taxa.resolve_name(text, kingdom: "Plantae") do
      {:ok, taxon} ->
        {taxon.id, nil}

      :none ->
        {nil, {"Host qualifier not resolved", "(on #{text}) names no plant"}}

      {:ambiguous, taxa} ->
        {nil,
         {"Host qualifier not resolved",
          "(on #{text}) names several plants (#{Enum.map_join(taxa, ", ", & &1.id)})"}}
    end
  end

  defp unread_issue(qualifiers) do
    case for({:unread, text} <- qualifiers, do: "(#{text})") do
      [] ->
        nil

      unread ->
        {"parenthetical not read as a name part", "not a name part: #{Enum.join(unread, " ")}"}
    end
  end

  defp several_issue(forms, hosts) when length(forms) > 1 or length(hosts) > 1,
    do:
      {"several form labels or Host qualifiers",
       "only the first form label and Host qualifier are parts: " <>
         Enum.map_join(forms ++ Enum.map(hosts, &"on #{&1}"), " ", &"(#{&1})")}

  defp several_issue(_forms, _hosts), do: nil

  defp generation_issue(_qualifiers, nil), do: nil

  defp generation_issue(_qualifiers, %{qualifier: nil}), do: nil

  defp generation_issue(qualifiers, %{qualifier: qualifier}) do
    case for({:generation, text} <- qualifiers, do: text) do
      [] ->
        {"generation written otherwise", "generation (#{qualifier}) not written in the name"}

      written ->
        case Enum.reject(written, &(String.downcase(&1) == qualifier)) do
          [] ->
            nil

          [text | _] ->
            {"generation written otherwise",
             "generation written (#{text}), derived (#{qualifier})"}
        end
    end
  end

  # -- report ----------------------------------------------------------------------

  @doc """
  Adds the Gall names to `report`: the reconciliation (derived, overridden,
  not derivable), counts of parts and of override reasons, and the
  `"gall_names"` worksheet of every Gall with an override or no derivation.
  """
  @spec report(Report.t(), [result()]) :: Report.t()
  def report(report, results) do
    {derived, rest} = Enum.split_with(results, &(&1.category == nil))
    {not_derivable, overridden} = Enum.split_with(rest, &(&1.category == "not derivable"))

    by_category =
      overridden
      |> Enum.frequencies_by(& &1.category)
      |> Enum.sort()
      |> Enum.map(fn {category, n} -> {"Gall name overrides: #{category}", n} end)

    rows =
      for r <- Enum.sort_by(rest, & &1.gall_id) do
        %{
          "gall_id" => r.gall_id,
          "name" => r.name,
          "derived" => r.derived,
          "name_override" => r.name_override,
          "category" => r.category,
          "reason" => r.reason,
          "form_label" => r.form_label,
          "host_qualifier" => r.host_qualifier,
          "descriptor" => r.descriptor
        }
      end

    report
    |> Report.reconcile("Gall names (today's names shown)", length(results), length(derived), [
      {"kept as an override (the derived name differs)", length(overridden)},
      {"not derivable (today's name stored)", length(not_derivable)}
    ])
    |> Report.count("Galls with a form label", Enum.count(results, & &1.form_label))
    |> Report.count(
      "Galls with a Host qualifier",
      Enum.count(results, & &1.host_qualifier_taxon_id)
    )
    |> Report.count("Galls with a descriptor", Enum.count(results, & &1.descriptor))
    |> then(fn report ->
      Enum.reduce(by_category, report, fn {label, n}, acc -> Report.count(acc, label, n) end)
    end)
    |> Report.curation("gall_names", @columns, rows)
  end
end
