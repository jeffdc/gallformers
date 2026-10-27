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

  # The audit metadata recorded for the test's sandbox transaction: the first
  # audited operation in it names the transaction.
  defp audit_transaction do
    Repo.one(
      from t in Carbonite.Transaction, where: t.xact_id == fragment("pg_current_xact_id()")
    )
  end

  defp details(source, attrs), do: Sources.update_source_details(test_actor(), source, attrs)

  describe "update_source_details/3: one changeset for today's columns and the new fields" do
    test "edits both in one write, in an audit transaction naming the actor" do
      source = source_fixture("Before the edit")

      assert {:ok, updated} =
               details(source, %{
                 "title" => "  After the edit  ",
                 "author" => "Weld, L. H.",
                 "pubyear" => "1959",
                 "link" => "www.example.org/weld",
                 "citation" => "Weld, L. H. After the edit. 1959.",
                 "license" => "All Rights Reserved",
                 "licenselink" => "",
                 "datacomplete" => "true",
                 "kind" => "publication",
                 "authors" => ["Weld, L. H."],
                 "authored" => "1959-03",
                 "authored_as_written" => "March 1959",
                 "doi" => "10.1000/weld",
                 "url" => "https://example.org/weld",
                 "isbn" => "",
                 "license_as_written" => "© L. H. Weld"
               })

      assert %{
               title: "After the edit",
               link: "https://www.example.org/weld",
               pubyear: "1959",
               datacomplete: true,
               kind: :publication,
               authors: ["Weld, L. H."],
               authored_date: ~D[1959-03-01],
               authored_precision: :month,
               doi: "10.1000/weld",
               license_value: "All Rights Reserved",
               license_as_written: "© L. H. Weld"
             } = Sources.get_source!(updated.id)

      assert %{meta: %{"operation" => "sources.update_source_details", "actor" => actor}} =
               audit_transaction()

      assert actor["name"] == "test"
    end

    test "keeps today's rules for the citation fields" do
      source = source_fixture("Rules")

      assert {:error, changeset} =
               details(source, %{
                 title: "",
                 author: "",
                 pubyear: "59",
                 citation: "",
                 license: "",
                 link: "not a url"
               })

      errors = errors_on(changeset)
      assert errors.title == ["can't be blank"]
      assert errors.author == ["can't be blank"]
      assert errors.citation == ["can't be blank"]
      assert errors.license == ["can't be blank"]
      assert errors.pubyear == ["must be a valid 4-digit year"]
      assert errors.link == ["must be a valid URL starting with http:// or https://"]
    end

    test "titles stay unique" do
      taken = source_fixture("Taken title")
      source = source_fixture("Another title")

      assert {:error, changeset} = details(source, %{title: taken.title})
      assert %{title: ["a source with this title already exists"]} = errors_on(changeset)
    end

    test "a read-only license gets its canonical link; an editable one must be a URL" do
      source = source_fixture("Licensed")

      # Public Domain / CC0 keeps an editable link, which must then be a URL.
      assert {:error, changeset} =
               details(source, %{license: "Public Domain / CC0", licenselink: "not a url"})

      assert %{licenselink: [_]} = errors_on(changeset)

      {:ok, updated} =
        details(Sources.get_source!(source.id), %{
          license: "CC-BY-SA",
          licenselink: "https://example.com/my-own-link"
        })

      assert updated.licenselink == "https://creativecommons.org/licenses/by-sa/4.0/"
      assert updated.license_value == "CC-BY-SA"
    end

    test "a link may be left empty (an imported Source may name none)" do
      source = source_fixture("No link")

      assert {:ok, updated} = details(source, %{link: ""})
      assert updated.link == ""
    end

    test "the URL must be a URL" do
      source = source_fixture("Bad URL")

      assert {:error, changeset} = details(source, %{url: "example"})
      assert %{url: [_]} = errors_on(changeset)
    end

    test "a year-only authored date round-trips its precision" do
      source = source_fixture("Studies on some new and described Cynipidae")

      assert {:ok, _} =
               details(source, %{
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

      {:ok, _} = details(source, %{kind: "website", authored: "2022-05"})
      assert Source.authored(Sources.get_source!(source.id)) == "2022-05"

      {:ok, _} = details(Sources.get_source!(source.id), %{authored: "2022-05-14"})

      reloaded = Sources.get_source!(source.id)
      assert reloaded.authored_precision == :day
      assert Source.authored(reloaded) == "2022-05-14"
    end

    test "stores identifiers and the license as a value and as written" do
      source = source_fixture("Identified")

      {:ok, updated} =
        details(source, %{
          kind: "publication",
          doi: "10.1000/xyz123",
          url: "https://example.org/paper",
          isbn: "978-3-16-148410-0",
          license: "CC-BY",
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

      assert {:error, changeset} = details(source, %{kind: "rumour"})
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
        assert {:error, changeset} = details(source, %{authored: bad})
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

  describe "retract_source/4" do
    test "sets both fields and points at the retraction notice, audited" do
      retracted = source_fixture("A retracted paper")
      notice = source_fixture("Retraction notice")

      assert {:ok, updated} =
               Sources.retract_source(test_actor(), retracted, notice, ~D[2023-03-01])

      assert updated.retracted_by_id == notice.id
      assert updated.retracted_on == ~D[2023-03-01]

      reloaded = Repo.preload(Sources.get_source!(retracted.id), :retracted_by)
      assert reloaded.retracted_by.id == notice.id
      assert reloaded.retracted_on == ~D[2023-03-01]

      assert %{meta: %{"operation" => "sources.retract_source"}} = audit_transaction()
    end

    test "the notice must be an existing Source" do
      retracted = source_fixture("Retracted by nothing")

      assert {:error, changeset} =
               Sources.retract_source(test_actor(), retracted, %Source{id: -1}, ~D[2023-03-01])

      assert %{retracted_by_id: ["does not exist"]} = errors_on(changeset)
    end

    test "a Source cannot retract itself" do
      source = source_fixture("Self-retracting")

      assert {:error, changeset} =
               Sources.retract_source(test_actor(), source, source, ~D[2023-03-01])

      assert %{retracted_by_id: [_]} = errors_on(changeset)
    end

    test "retracted_source_ids/1 picks the retracted Sources out of a list" do
      retracted = source_fixture("Retracted among others")
      kept = source_fixture("Not retracted")
      notice = source_fixture("The notice")
      {:ok, _} = Sources.retract_source(test_actor(), retracted, notice, ~D[2023-03-01])

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

  describe "unretract_source/2" do
    test "clears the notice and the date, audited" do
      source = source_fixture("Retracted by mistake")
      notice = source_fixture("A mistaken notice")
      {:ok, retracted} = Sources.retract_source(test_actor(), source, notice, ~D[2023-03-01])

      assert {:ok, updated} = Sources.unretract_source(test_actor(), retracted)
      assert updated.retracted_by_id == nil
      assert updated.retracted_on == nil
      assert Sources.retracted_source_ids([source.id]) == []
    end

    test "a Source that is not retracted is refused" do
      source = source_fixture("Never retracted")

      assert {:error, changeset} = Sources.unretract_source(test_actor(), source)
      assert %{retracted_by_id: ["is not retracted"]} = errors_on(changeset)
    end
  end

  describe "the Gallformers Source" do
    test "only one Source can be Gallformers" do
      first = source_fixture("Gallformers one")
      second = source_fixture("Gallformers two")

      # The test database has no Source 58, so the migration marked nothing;
      # clear any Gallformers Source anyway so this test decides which one is.
      Repo.query!("UPDATE source SET kind = NULL WHERE kind = 'gallformers'")
      {:ok, _} = details(first, %{kind: "gallformers"})

      assert {:error, changeset} = details(second, %{kind: "gallformers"})
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
