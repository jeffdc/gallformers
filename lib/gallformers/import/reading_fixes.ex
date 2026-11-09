defmodule Gallformers.Import.ReadingFixes do
  @moduledoc """
  A Source's reading fixes (matter `87a1`): the packages of that Source
  that read it again (`source.reading_of`, `Gallformers.Import.submit_reading_fix/2`),
  for the admin Source page, in words. Each says who fixed it and when,
  their Why, and what changed: a Fact the Source doesn't say ("Host
  Rubus: it doesn't say this"), what it says in its place ("Host Rubus →
  Rubus frondosus", "Placement of Aphis rubifolii under Aphis → under
  Amphorophora"), or what it says too.
  """
  import Ecto.Query, only: [from: 2]

  alias Gallformers.Import.Batch
  alias Gallformers.Import.Package
  alias Gallformers.Places
  alias Gallformers.Repo

  @type fix :: %{
          package_id: integer(),
          at: DateTime.t(),
          author_name: String.t() | nil,
          why: String.t() | nil,
          changes: [String.t()]
        }

  @doc "Source `source_id`'s applied reading fixes, newest first."
  @spec list(integer()) :: [fix()]
  def list(source_id) when is_integer(source_id) do
    from(b in Batch,
      join: p in Package,
      on: p.id == b.package_id,
      where:
        p.source_id == ^source_id and b.status == :applied and
          fragment("? -> 'source' \\? 'reading_of'", b.content),
      order_by: [desc: b.applied_at, desc: b.id],
      select: {b, p.submitter_name}
    )
    |> Repo.all()
    |> Enum.map(fn {batch, author} ->
      %{
        package_id: batch.package_id,
        at: batch.applied_at,
        author_name: author,
        why: get_in(batch.content, ["source", "reading_of", "why"]),
        changes: changes(batch.content)
      }
    end)
  end

  # Each unstated Fact with what replaces it, then what it says besides.
  defp changes(content) do
    # Each taxon as read: the Source's words read as a plant (`name_reading`).
    taxa =
      Map.new(
        List.wrap(content["taxa"]),
        &{&1["ref"], &1["name_reading"] || &1["name_as_written"]}
      )

    facts = List.wrap(content["facts"]) ++ List.wrap(content["acts"])
    {unstated, stated} = Enum.split_with(facts, & &1["unstated"])

    for(
      u <- unstated,
      do: unstated_words(u, Enum.filter(stated, &(&1["replaces"] == u["id"])), taxa)
    ) ++
      for f <- stated, not Map.has_key?(f, "replaces"), do: "#{words(f, taxa)}: it says this too"
  end

  defp unstated_words(fact, [], taxa), do: "#{words(fact, taxa)}: it doesn't say this"

  defp unstated_words(fact, replacements, taxa),
    do: "#{words(fact, taxa)} → #{Enum.map_join(replacements, ", ", &value(&1, taxa))}"

  defp words(%{"kind" => "relationship", "type" => "host_of"} = f, taxa),
    do: "Host #{value(f, taxa)}"

  defp words(%{"kind" => "relationship", "type" => "inducer_of"} = f, taxa),
    do: "Inducer #{value(f, taxa)}"

  defp words(%{"kind" => "trait", "trait" => trait} = f, taxa),
    do: "#{trait |> String.replace("_", " ") |> String.capitalize()} #{value(f, taxa)}"

  defp words(%{"kind" => "alias"} = f, taxa), do: "Alias “#{value(f, taxa)}”"

  defp words(%{"kind" => "range", "adjustment" => "exclude"} = f, taxa),
    do: "Range: not in #{value(f, taxa)}"

  defp words(%{"kind" => "range"} = f, taxa), do: "Range: only in #{value(f, taxa)}"
  defp words(%{"kind" => "occurrence"} = f, taxa), do: "Recorded in #{value(f, taxa)}"

  defp words(%{"kind" => "placement"} = a, taxa),
    do: "Placement of #{taxa[a["taxon"]]} #{value(a, taxa)}"

  defp words(%{"kind" => "synonymy"} = a, taxa), do: "#{taxa[a["name"]]} #{value(a, taxa)}"
  defp words(%{"kind" => "name"} = a, taxa), do: "Name #{taxa[a["taxon"]]}"

  defp words(%{"kind" => "common_name"} = a, taxa),
    do: "Common name “#{a["common_name"]}” of #{taxa[a["taxon"]]}"

  defp words(%{"kind" => "split"} = a, taxa), do: "Split of #{taxa[a["taxon"]]}"
  defp words(f, _taxa), do: f["kind"]

  defp value(%{"kind" => "relationship", "subject" => ref}, taxa), do: taxa[ref] || ref
  defp value(%{"kind" => "trait", "value" => %{"value" => value}}, _taxa), do: value
  defp value(%{"kind" => "alias", "name" => name}, _taxa), do: name

  defp value(%{"place" => %{"value" => code} = place}, _taxa) do
    case Places.get_place_by_code(code) do
      %{name: name} -> name
      nil -> place["as_written"] || code
    end
  end

  defp value(%{"kind" => "placement", "parent" => ref}, taxa), do: "under #{taxa[ref]}"
  defp value(%{"kind" => "synonymy", "accepted" => ref}, taxa), do: "a synonym of #{taxa[ref]}"
  defp value(f, _taxa), do: f["id"]
end
