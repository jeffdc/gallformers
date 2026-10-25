defmodule Gallformers.Sources.SourceTest do
  @moduledoc """
  The Source's new descriptive fields (`9449` §2): kind, authors, authored
  date with precision, identifiers, license, and retraction.
  """
  use Gallformers.DataCase, async: true

  alias Gallformers.Sources
  alias Gallformers.Sources.PartialDate
  alias Gallformers.Sources.Source

  defp source_fixture(title) do
    {:ok, source} =
      Sources.create_source(%{
        title: title,
        author: "Kinsey, A. C.",
        pubyear: "1922",
        link: "https://example.com/#{System.unique_integer([:positive])}",
        citation: "#{title}. 1922.",
        license: "Public Domain / Copyright Expired"
      })

    source
  end

  describe "update_source_details/2" do
    test "a year-only authored date round-trips its precision" do
      source = source_fixture("Studies on some new and described Cynipidae")

      assert {:ok, _} =
               Sources.update_source_details(source, %{
                 kind: "publication",
                 authors: ["Kinsey, A. C."],
                 authored: "1922",
                 authored_as_written: "1922"
               })

      reloaded = Sources.get_source!(source.id)
      assert reloaded.kind == :publication
      assert reloaded.authors == ["Kinsey, A. C."]
      assert reloaded.authored_date == ~D[1922-01-01]
      assert reloaded.authored_precision == :year
      assert reloaded.authored_as_written == "1922"
      assert Source.authored(reloaded) == "1922"
    end

    test "a month and a day keep their precision" do
      source = source_fixture("A website")

      {:ok, _} = Sources.update_source_details(source, %{kind: "website", authored: "2022-05"})
      assert Source.authored(Sources.get_source!(source.id)) == "2022-05"

      {:ok, _} =
        Sources.update_source_details(Sources.get_source!(source.id), %{authored: "2022-05-14"})

      reloaded = Sources.get_source!(source.id)
      assert reloaded.authored_precision == :day
      assert Source.authored(reloaded) == "2022-05-14"
    end

    test "stores identifiers and the license as given and as written" do
      source = source_fixture("Identified")

      {:ok, updated} =
        Sources.update_source_details(source, %{
          kind: "publication",
          doi: "10.1000/xyz123",
          url: "https://example.org/paper",
          isbn: "978-3-16-148410-0",
          license_value: "CC-BY",
          license_as_written: "CC BY 4.0"
        })

      assert %{
               doi: "10.1000/xyz123",
               url: "https://example.org/paper",
               isbn: "978-3-16-148410-0",
               license_value: "CC-BY",
               license_as_written: "CC BY 4.0"
             } = updated
    end

    test "an unknown kind is rejected" do
      source = source_fixture("Unknown kind")

      assert {:error, changeset} = Sources.update_source_details(source, %{kind: "rumour"})
      assert %{kind: ["is invalid"]} = errors_on(changeset)
    end

    test "the database rejects an unknown kind written around the schema" do
      source = source_fixture("Raw kind")

      assert_raise Postgrex.Error, ~r/source_kind_check/, fn ->
        Repo.query!("UPDATE source SET kind = 'rumour' WHERE id = $1", [source.id])
      end
    end

    test "a malformed authored date is rejected" do
      source = source_fixture("Bad date")

      for bad <- ["22", "1922-13", "1922-02-30", "May 1922"] do
        assert {:error, changeset} = Sources.update_source_details(source, %{authored: bad})
        assert %{authored: [_]} = errors_on(changeset)
      end
    end

    test "old code keeps creating Sources without the new fields" do
      source = source_fixture("Old style")

      assert source.kind == nil
      assert source.authors == []
      assert source.authored_date == nil
      assert source.retracted_by_id == nil
    end
  end

  describe "retract_source/3" do
    test "sets both fields and points at the retraction notice" do
      retracted = source_fixture("A retracted paper")
      notice = source_fixture("Retraction notice")

      assert {:ok, updated} = Sources.retract_source(retracted, notice, ~D[2023-03-01])
      assert updated.retracted_by_id == notice.id
      assert updated.retracted_on == ~D[2023-03-01]

      reloaded = Repo.preload(Sources.get_source!(retracted.id), :retracted_by)
      assert reloaded.retracted_by.id == notice.id
      assert reloaded.retracted_on == ~D[2023-03-01]
    end

    test "the notice must be an existing Source" do
      retracted = source_fixture("Retracted by nothing")

      assert {:error, changeset} =
               Sources.retract_source(retracted, %Source{id: -1}, ~D[2023-03-01])

      assert %{retracted_by_id: ["does not exist"]} = errors_on(changeset)
    end

    test "a Source cannot retract itself" do
      source = source_fixture("Self-retracting")

      assert {:error, changeset} = Sources.retract_source(source, source, ~D[2023-03-01])
      assert %{retracted_by_id: [_]} = errors_on(changeset)
    end

    test "retracted_source_ids/1 picks the retracted Sources out of a list" do
      retracted = source_fixture("Retracted among others")
      kept = source_fixture("Not retracted")
      notice = source_fixture("The notice")
      {:ok, _} = Sources.retract_source(retracted, notice, ~D[2023-03-01])

      assert Sources.retracted_source_ids([retracted.id, kept.id, notice.id]) == [retracted.id]
      assert Sources.retracted_source_ids([]) == []
    end

    test "the database keeps the notice and the date together" do
      source = source_fixture("Half retracted")

      assert_raise Postgrex.Error, ~r/source_retraction_complete/, fn ->
        Repo.query!("UPDATE source SET retracted_on = '2023-03-01' WHERE id = $1", [source.id])
      end
    end
  end

  describe "the Gallformers Source" do
    test "only one Source can be Gallformers" do
      first = source_fixture("Gallformers one")
      second = source_fixture("Gallformers two")

      # The test database has no Source 58, so the migration marked nothing;
      # clear any Gallformers Source anyway so this test decides which one is.
      Repo.query!("UPDATE source SET kind = NULL WHERE kind = 'gallformers'")
      {:ok, _} = Sources.update_source_details(first, %{kind: "gallformers"})

      assert {:error, changeset} = Sources.update_source_details(second, %{kind: "gallformers"})
      assert %{kind: ["there is already a Gallformers Source"]} = errors_on(changeset)
    end
  end

  describe "PartialDate" do
    test "parses each precision and formats it back" do
      assert PartialDate.parse("1897") == {:ok, {~D[1897-01-01], :year}}
      assert PartialDate.parse("1897-05") == {:ok, {~D[1897-05-01], :month}}
      assert PartialDate.parse("1897-05-14") == {:ok, {~D[1897-05-14], :day}}

      assert PartialDate.format(~D[1897-01-01], :year) == "1897"
      assert PartialDate.format(~D[1897-05-01], :month) == "1897-05"
      assert PartialDate.format(~D[1897-05-14], :day) == "1897-05-14"
    end

    test "rejects anything else" do
      for bad <- ["", "97", "1897-5", "1897-00", "1897-02-30", "1897/05"] do
        assert PartialDate.parse(bad) == :error
      end
    end
  end
end
