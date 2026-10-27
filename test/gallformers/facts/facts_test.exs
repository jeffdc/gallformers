defmodule Gallformers.FactsTest do
  @moduledoc """
  Facts, attributions and stored standings (`9449` §2): one attribution per
  Fact and Source, its evidence, names and Observations, and standings
  recomputed in the same transaction.

  Not async: some tests make the one Gallformers Source, which a unique index
  allows only once at a time across concurrent sandbox transactions.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.TaxaFixtures

  alias Gallformers.DoclingFixtures
  alias Gallformers.Facts
  alias Gallformers.Facts.Attribution
  alias Gallformers.Facts.Fact
  alias Gallformers.Facts.Standing.Conflict
  alias Gallformers.Sources
  alias Gallformers.Sources.QuoteLocator

  # -- fixtures ----------------------------------------------------------------

  defp source_fixture(title, authored) do
    {:ok, source} =
      Sources.create_source(%{
        title: title,
        author: "Kinsey, A. C.",
        pubyear: String.slice(authored, 0, 4),
        link: "https://example.com/#{System.unique_integer([:positive])}",
        citation: "#{title}.",
        license: "Public Domain / Copyright Expired"
      })

    {:ok, source} =
      Sources.update_source_details(source, %{kind: "publication", authored: authored})

    source
  end

  defp gallformers_source do
    {:ok, source} =
      Sources.create_source(%{
        title: "Gallformers Notes #{System.unique_integer([:positive])}",
        author: "Gallformers Contributors",
        pubyear: "2020",
        link: "https://gallformers.org",
        citation: "Gallformers.",
        license: "Public Domain / CC0"
      })

    Repo.query!("UPDATE source SET kind = NULL WHERE kind = 'gallformers'")
    {:ok, source} = Sources.update_source_details(source, %{kind: "gallformers"})
    source
  end

  defp fact_fixture(attrs \\ %{}) do
    {:ok, fact} = Facts.create_fact(test_actor(), Map.merge(%{kind: "trait"}, attrs))
    fact
  end

  defp attribute!(fact, source, attrs) do
    {:ok, result} =
      Facts.attribute(test_actor(), Map.merge(%{fact_id: fact.id, source_id: source.id}, attrs))

    result
  end

  defp standing(fact), do: Facts.get_fact!(fact.id).standing

  defp changes_for(table) do
    Repo.all(from c in test_audit_changes(), where: c.table_name == ^table, order_by: c.id)
  end

  defp stored_item(ref) do
    source = source_fixture("Documented #{System.unique_integer([:positive])}", "1957")
    {:ok, doc} = Sources.store_document(test_actor(), source, DoclingFixtures.document_json())
    {source, Sources.get_document_item(doc, ref)}
  end

  # -- facts -----------------------------------------------------------------

  describe "create_fact/2" do
    test "a new Fact is unsupported until something attributes it" do
      assert {:ok, %Fact{kind: "trait", slot: "gall:1:detachable", standing: :unsupported}} =
               Facts.create_fact(test_actor(), %{kind: "trait", slot: "gall:1:detachable"})
    end

    test "needs a kind" do
      assert {:error, changeset} = Facts.create_fact(test_actor(), %{})
      assert %{kind: ["can't be blank"]} = errors_on(changeset)
    end

    test "is audited" do
      fact = fact_fixture()
      assert [%{op: :insert, table_pk: [pk]}] = changes_for("facts")
      assert pk == to_string(fact.id)
    end
  end

  # -- attribute -----------------------------------------------------------

  describe "attribute/2" do
    test "a confirmation makes the Fact current" do
      fact = fact_fixture()
      source = source_fixture("Host records", "1923")

      assert %{attribution: %Attribution{stance: :confirm}, conflicts: []} =
               attribute!(fact, source, %{stance: :confirm})

      assert standing(fact) == :current
    end

    test "the attribution is dated by its Source's authored date unless a date is given" do
      fact = fact_fixture()
      source = source_fixture("Dated", "1897-05")

      %{attribution: by_source} = attribute!(fact, source, %{stance: :confirm})
      assert {by_source.stated_on, by_source.stated_precision} == {~D[1897-05-01], :month}

      %{attribution: given} = attribute!(fact, source, %{stance: :confirm, stated: "1901"})
      assert {given.stated_on, given.stated_precision} == {~D[1901-01-01], :year}

      %{attribution: undated} = attribute!(fact, source, %{stance: :confirm, stated: nil})
      assert {undated.stated_on, undated.stated_precision} == {nil, nil}
    end

    test "one attribution per Fact and Source: attributing again updates it" do
      fact = fact_fixture()
      source = source_fixture("Corrected later", "1923")

      %{attribution: first} = attribute!(fact, source, %{stance: :confirm, value_as_written: "x"})
      %{attribution: second} = attribute!(fact, source, %{stance: :deny, value_as_written: "y"})

      assert second.id == first.id
      assert [%Attribution{stance: :deny, value_as_written: "y"}] = Facts.list_attributions(fact)
      assert standing(fact) == :withdrawn
    end

    test "a newer Gallformers statement replaces Gallformers' attribution, and audit keeps the old one" do
      fact = fact_fixture()
      gallformers = gallformers_source()

      attribute!(fact, gallformers, %{
        stance: :confirm,
        stated: "2024-03-01",
        statement_text: "Detachable, per iNat 123."
      })

      attribute!(fact, gallformers, %{
        stance: :deny,
        stated: "2026-10-24",
        statement_text: "Not detachable; the earlier note misread the photo."
      })

      assert [%Attribution{stance: :deny, stated_on: ~D[2026-10-24]}] =
               Facts.list_attributions(fact)

      assert [_insert, update] = changes_for("attributions")
      assert update.op == :update

      assert %{
               "stance" => "confirm",
               "stated_on" => "2024-03-01",
               "statement_text" => "Detachable, per iNat 123."
             } = update.changed_from
    end

    test "a Gallformers attribution needs its statement text" do
      fact = fact_fixture()
      gallformers = gallformers_source()

      assert {:error, changeset} =
               Facts.attribute(test_actor(), %{
                 fact_id: fact.id,
                 source_id: gallformers.id,
                 stance: :confirm,
                 stated: "2026-10-24"
               })

      assert %{statement_text: ["can't be blank"]} = errors_on(changeset)
    end

    test "attributing the same content again writes nothing" do
      fact = fact_fixture()
      {source, item} = stored_item("#/texts/2")
      lobata = taxon_fixture(name: "Quercus lobata")

      attrs = %{
        stance: :confirm,
        evidence: [%{document_item_id: item.id, quote: "Common on Q. lobata"}],
        names: [%{taxon_id: lobata.id, name_as_written: "Q. lobata", role: "host"}],
        observations: [%{provider: :inaturalist, external_id: "123"}]
      }

      attribute!(fact, source, attrs)
      before = Repo.aggregate(test_audit_changes(), :count)

      attribute!(fact, source, attrs)
      assert Repo.aggregate(test_audit_changes(), :count) == before
    end

    test "a same-date disagreement is returned as a conflict and the Fact keeps its standing" do
      fact = fact_fixture()
      attribute!(fact, source_fixture("Confirms", "1897"), %{stance: :confirm})
      assert standing(fact) == :current

      %{conflicts: [conflict]} =
        attribute!(fact, source_fixture("Denies", "1897-05"), %{stance: :deny})

      assert %Conflict{type: :same_date, fact_ids: [id]} = conflict
      assert id == fact.id
      assert length(conflict.attributions) == 2
      assert standing(fact) == :current
    end

    test "in a slot, the newer current Fact supersedes the older" do
      older = fact_fixture(%{slot: "gall:9:detachable"})
      newer = fact_fixture(%{slot: "gall:9:detachable"})
      elsewhere = fact_fixture(%{slot: "gall:10:detachable"})

      attribute!(older, source_fixture("Old view", "1900"), %{stance: :confirm})
      attribute!(elsewhere, source_fixture("Other gall", "1890"), %{stance: :confirm})
      assert standing(older) == :current

      attribute!(newer, source_fixture("New view", "1950"), %{stance: :confirm})

      assert standing(newer) == :current
      assert standing(older) == :superseded
      assert standing(elsewhere) == :current
    end
  end

  describe "list_attributions_for_facts/1" do
    test "the attributions of several Facts, by Fact ID, each oldest first" do
      one = fact_fixture()
      two = fact_fixture()
      none = fact_fixture()
      older = source_fixture("Older", "1923")
      newer = source_fixture("Newer", "1950")

      attribute!(one, older, %{stance: :confirm})
      attribute!(one, newer, %{stance: :deny})
      attribute!(two, newer, %{stance: :confirm})

      assert %{} = by_fact = Facts.list_attributions_for_facts([one.id, two.id, none.id])
      assert Map.keys(by_fact) |> Enum.sort() == [one.id, two.id]

      assert Enum.map(by_fact[one.id], &{&1.source_id, &1.stance}) == [
               {older.id, :confirm},
               {newer.id, :deny}
             ]

      assert [%Attribution{evidence: [], names: [], observations: []}] = by_fact[two.id]
      assert Facts.list_attributions_for_facts([]) == %{}
    end
  end

  describe "attribute/2 evidence" do
    test "a quote's span in its item is stored" do
      fact = fact_fixture()
      {source, item} = stored_item("#/texts/1")

      %{attribution: attribution} =
        attribute!(fact, source, %{
          stance: :confirm,
          evidence: [
            %{
              document_item_id: item.id,
              quote: "globular and pale tan",
              page: "58",
              cites_as_written: "Kinsey 1923"
            }
          ]
        })

      assert [evidence] = attribution.evidence

      assert QuoteLocator.slice(item.text, {evidence.span_start, evidence.span_length}) ==
               "glob-\nular and pale tan"

      assert evidence.page == "58"
      assert evidence.cites_as_written == "Kinsey 1923"
      assert evidence.whole_item == false
    end

    test "a quote that is not in its item is rejected and nothing is written" do
      fact = fact_fixture()
      {source, item} = stored_item("#/texts/1")

      assert {:error, changeset} =
               Facts.attribute(test_actor(), %{
                 fact_id: fact.id,
                 source_id: source.id,
                 stance: :confirm,
                 evidence: [%{document_item_id: item.id, quote: "spherical and red"}]
               })

      assert %{evidence: [%{quote: ["is not in its document item"]}]} = errors_on(changeset)
      assert Facts.list_attributions(fact) == []
      assert standing(fact) == :unsupported
    end

    test "a whole item is evidence without a quote or span" do
      fact = fact_fixture()
      {source, item} = stored_item("#/texts/3")

      %{attribution: %{evidence: [evidence]}} =
        attribute!(fact, source, %{
          stance: :confirm,
          evidence: [%{document_item_id: item.id, whole_item: true}]
        })

      assert %{whole_item: true, quote: nil, span_start: nil, span_length: nil} = evidence
    end

    test "a whole item cannot also carry a quote" do
      fact = fact_fixture()
      {source, item} = stored_item("#/texts/3")

      assert {:error, changeset} =
               Facts.attribute(test_actor(), %{
                 fact_id: fact.id,
                 source_id: source.id,
                 stance: :confirm,
                 evidence: [%{document_item_id: item.id, whole_item: true, quote: "Torymus"}]
               })

      assert %{evidence: [%{quote: [_]}]} = errors_on(changeset)
    end

    test "a quote from a Source with no stored document is kept without a span" do
      fact = fact_fixture()
      source = source_fixture("A website", "2015")

      %{attribution: %{evidence: [evidence]}} =
        attribute!(fact, source, %{
          stance: :confirm,
          evidence: [%{quote: "galls on Q. alba", url: "https://example.com/q-alba"}]
        })

      assert %{quote: "galls on Q. alba", span_start: nil, document_item_id: nil} = evidence
    end

    test "evidence, names and Observations are replaced when the attribution is updated" do
      fact = fact_fixture()
      {source, item} = stored_item("#/texts/2")
      lobata = taxon_fixture(name: "Quercus lobata")
      douglasii = taxon_fixture(name: "Quercus douglasii")

      attribute!(fact, source, %{
        stance: :confirm,
        evidence: [%{document_item_id: item.id, quote: "Common on Q. lobata"}],
        names: [%{taxon_id: lobata.id, name_as_written: "Q. lobata", role: "host"}],
        observations: [%{provider: :inaturalist, external_id: "123"}]
      })

      %{attribution: updated} =
        attribute!(fact, source, %{
          stance: :confirm,
          evidence: [%{document_item_id: item.id, quote: "throughout the hills"}],
          names: [
            %{
              taxon_id: douglasii.id,
              name_as_written: "Q. douglasii",
              name_reading: "Quercus douglasii",
              role: "host"
            }
          ],
          observations: [
            %{provider: :bugguide, external_id: "9", url: "https://bugguide.net/node/view/9"}
          ]
        })

      assert [%{quote: "throughout the hills"}] = updated.evidence
      assert [%{taxon_id: taxon_id, name_reading: "Quercus douglasii"}] = updated.names
      assert taxon_id == douglasii.id
      assert [%{provider: :bugguide, external_id: "9"}] = updated.observations

      assert [%Attribution{evidence: [_], names: [_], observations: [_]}] =
               Facts.list_attributions(fact)
    end

    test "a name must resolve to an existing taxon" do
      fact = fact_fixture()
      source = source_fixture("Names a ghost", "1923")

      assert {:error, changeset} =
               Facts.attribute(test_actor(), %{
                 fact_id: fact.id,
                 source_id: source.id,
                 stance: :confirm,
                 names: [%{taxon_id: -1, name_as_written: "Q. nulla", role: "host"}]
               })

      assert %{names: [%{taxon_id: ["does not exist"]}]} = errors_on(changeset)
      assert Facts.list_attributions(fact) == []
    end
  end

  # -- remove and recompute ----------------------------------------------------

  describe "remove_attribution/3" do
    test "removing the last attribution makes the Fact unsupported" do
      fact = fact_fixture()
      source = source_fixture("Dropped on re-import", "1923")

      attribute!(fact, source, %{
        stance: :confirm,
        observations: [%{provider: :other, external_id: "a"}]
      })

      assert {:ok, []} = Facts.remove_attribution(test_actor(), fact.id, source.id)
      assert Facts.list_attributions(fact) == []
      assert standing(fact) == :unsupported
    end

    test "removing one of several leaves the others deciding" do
      fact = fact_fixture()
      keeps = source_fixture("Confirms early", "1900")
      dropped = source_fixture("Denies later", "1950")
      attribute!(fact, keeps, %{stance: :confirm})
      attribute!(fact, dropped, %{stance: :deny})
      assert standing(fact) == :withdrawn

      assert {:ok, []} = Facts.remove_attribution(test_actor(), fact.id, dropped.id)
      assert standing(fact) == :current
    end

    test "an attribution that is not there is not found" do
      fact = fact_fixture()
      source = source_fixture("Never attributed", "1923")

      assert Facts.remove_attribution(test_actor(), fact.id, source.id) == {:error, :not_found}
    end
  end

  describe "recompute_for_source/2" do
    test "retracting a Source and recomputing flips its Facts" do
      only_retracted = fact_fixture()
      also_confirmed = fact_fixture()
      untouched = fact_fixture()

      retracted = source_fixture("Fabricated results", "2019")
      other = source_fixture("Independent record", "1950")
      notice = source_fixture("Retraction notice", "2021")

      attribute!(only_retracted, retracted, %{stance: :confirm})
      attribute!(also_confirmed, retracted, %{stance: :deny})
      attribute!(also_confirmed, other, %{stance: :confirm})
      attribute!(untouched, other, %{stance: :confirm})
      assert standing(also_confirmed) == :withdrawn

      {:ok, _} = Sources.retract_source(retracted, notice, ~D[2021-06-01])
      assert {:ok, []} = Facts.recompute_for_source(test_actor(), retracted.id)

      assert standing(only_retracted) == :retracted
      assert standing(also_confirmed) == :current
      assert standing(untouched) == :current
    end
  end
end
