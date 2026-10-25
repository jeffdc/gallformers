defmodule Gallformers.Sources.MatchSourceTest do
  @moduledoc """
  Matching an import package's Source block to a Source
  (`Gallformers.Sources.match_source/1`): DOI, else citation, else title;
  anything unclear is ambiguous.
  """
  use Gallformers.DataCase, async: true

  alias Gallformers.Sources

  defp source!(title, citation, doi \\ nil) do
    {:ok, source} =
      Sources.create_source(%{
        title: title,
        author: "Weld, L. H.",
        pubyear: "1957",
        link: "https://example.com/#{System.unique_integer([:positive])}",
        citation: citation,
        license: "All Rights Reserved"
      })

    if doi do
      {:ok, source} = Sources.update_source_details(source, %{doi: doi})
      source
    else
      source
    end
  end

  defp unique, do: System.unique_integer([:positive])

  test "a DOI matches whatever its form" do
    n = unique()
    source = source!("Cynipid galls #{n}", "Weld 1957 #{n}.", "https://doi.org/10.1/ABC.#{n}")

    assert {:match, ^source} =
             Sources.match_source(%{doi: "10.1/abc.#{n}", citation: "other", title: "other"})
  end

  test "a citation matches ignoring case and spacing" do
    n = unique()
    source = source!("Cynipid galls #{n}", "Weld, L. H. 1957.  Cynipid galls #{n}.")

    assert {:match, ^source} =
             Sources.match_source(%{citation: "weld, l. h. 1957. cynipid galls #{n}."})
  end

  test "a citation match whose stored DOI differs is ambiguous" do
    n = unique()
    source!("Cynipid galls #{n}", "Weld 1957 #{n}.", "10.1/one.#{n}")

    assert {:ambiguous, [_]} =
             Sources.match_source(%{doi: "10.1/two.#{n}", citation: "Weld 1957 #{n}."})
  end

  test "a title held by a Source with another citation is ambiguous" do
    n = unique()
    source!("Cynipid galls #{n}", "Weld 1957 #{n}.")

    assert {:ambiguous, [_]} =
             Sources.match_source(%{citation: "Weld 1959 #{n}.", title: "Cynipid galls #{n}"})
  end

  test "nothing matching is new" do
    assert :none = Sources.match_source(%{citation: "Nobody #{unique()}.", title: "Nothing"})
  end
end
