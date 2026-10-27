defmodule Gallformers.Import.ReviewTest do
  @moduledoc """
  The Import back-end of the review screens (matter a856, Task 2): packages
  and open queue items across packages, paged; denying a package or a batch;
  and Gallformers' own statement fragments submitted from a form.

  Not async: packages create Sources (unique titles), the Gallformers Source
  is unique, and the Catalog vocabularies are loaded.
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.ImportFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Catalog
  alias Gallformers.Catalog.Facts.RangeFact
  alias Gallformers.Facts
  alias Gallformers.Import
  alias Gallformers.Import.Batch
  alias Gallformers.Import.Package
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.Replay
  alias Gallformers.Taxa

  setup :audit_test_metadata

  defp register!(key \\ "pkg-#{System.unique_integer([:positive])}") do
    {:ok, package} = Import.register_package(test_actor(), key)
    package
  end

  # A delivered package awaiting review, with an open :unresolved_host item
  # ("Q. lobata" names no plant here).
  defp awaiting!(opts \\ []) do
    package(Keyword.merge([gall: unique_batch_id(batch())], opts))
    |> with_review()
    |> deliver!()
  end

  defp gall_rename_item!(gall_id) do
    %QueueItem{}
    |> QueueItem.create_changeset(%{
      kind: :gall_rename,
      subject: %{"gall_id" => gall_id},
      proposal: %{"gall_id" => gall_id, "from" => "A", "to" => "B", "collision" => false},
      reason: "A was renamed B."
    })
    |> Repo.insert!()
  end

  defp replay_entries(kind),
    do: Enum.filter(Import.list_replay_entries(), &(&1.kind == kind))

  defp audited?(table, id, status) do
    from(c in test_audit_changes(), where: c.table_name == ^table and c.table_pk == ^["#{id}"])
    |> Repo.all()
    |> Enum.any?(&(&1.data["status"] == status))
  end

  describe "list_packages/1" do
    test "lists packages newest first, filtered by status and paged" do
      first = register!()
      second = register!()
      third = register!()
      {:ok, _} = Import.deny_package(test_actor(), second, "Not a gall paper.")

      assert %{entries: entries, total: 3} = Import.list_packages()
      assert Enum.map(entries, & &1.id) == [third.id, second.id, first.id]

      assert %{entries: [%Package{id: id}], total: 1} = Import.list_packages(status: :denied)
      assert id == second.id

      assert %{entries: received, total: 2} = Import.list_packages(status: [:received])
      assert Enum.map(received, & &1.id) == [third.id, first.id]

      assert %{entries: [%Package{id: page_id}], total: 3} =
               Import.list_packages(limit: 1, offset: 1)

      assert page_id == second.id
    end
  end

  describe "list_open_queue_items/1" do
    test "lists open items across packages, oldest first, with their package and batch" do
      one = awaiting!()
      two = awaiting!()
      rename = gall_rename_item!(gall_fixture().id)

      assert %{entries: entries, total: total} = Import.list_open_queue_items()
      assert total == length(entries)

      package_ids = entries |> Enum.map(& &1.package_id) |> Enum.uniq()
      assert package_ids == [one.id, two.id, nil]
      assert List.last(entries).id == rename.id
      assert entries == Enum.sort_by(entries, & &1.id)

      [item | _] = entries
      assert %Package{id: package_id} = item.package
      assert package_id == one.id
      assert %Batch{file: "gall.json"} = item.batch
      assert %QueueItem{package: nil, batch: nil} = List.last(entries)
    end

    test "filters by kind, includes rename proposals, and pages" do
      package = awaiting!()
      rename = gall_rename_item!(gall_fixture().id)
      hosts = Import.list_queue_items(package, kind: :unresolved_host)
      assert hosts != []

      assert %{entries: [%QueueItem{id: id}], total: 1} =
               Import.list_open_queue_items(kind: :gall_rename)

      assert id == rename.id

      assert %{entries: entries} = Import.list_open_queue_items(kind: :unresolved_host)
      assert Enum.map(entries, & &1.id) == Enum.map(hosts, & &1.id)

      %{total: total} = Import.list_open_queue_items()

      assert %{entries: [second], total: ^total} =
               Import.list_open_queue_items(limit: 1, offset: 1)

      assert second.id == Enum.at(Import.list_open_queue_items().entries, 1).id
    end

    test "leaves out decided items" do
      rename = gall_rename_item!(gall_fixture().id)

      rename
      |> QueueItem.decide_changeset(%{"reject" => true}, test_actor())
      |> Repo.update!()

      assert %{entries: [], total: 0} = Import.list_open_queue_items(kind: :gall_rename)
    end

    test "counts open items by kind" do
      awaiting!()
      gall_rename_item!(gall_fixture().id)

      counts = Import.count_open_queue_items()
      assert counts[:gall_rename] == 1
      assert counts[:unresolved_host] >= 1
      refute Map.has_key?(counts, :dispute)
    end
  end

  describe "deny_package/3" do
    test "denies the package and its batches, drops its open items, audited and logged" do
      package = awaiting!()
      assert Import.list_queue_items(package) != []

      assert {:ok, %Package{status: :denied, denied_reason: "Duplicate delivery."} = denied} =
               Import.deny_package(test_actor(), package, " Duplicate delivery. ")

      assert [%Batch{status: :denied, denied_reason: "Duplicate delivery."}] =
               Import.list_batches(denied)

      assert Import.list_queue_items(denied) == []
      refute Enum.any?(Import.list_open_queue_items().entries, &(&1.package_id == package.id))
      assert audited?("import_packages", package.id, "denied")

      assert [entry] = replay_entries(:package_denied)
      assert entry.key == %{"package" => package.key}
      assert entry.payload == %{"reason" => "Duplicate delivery."}

      assert {:error, :not_approvable} = Import.approve_package(test_actor(), denied)
    end

    test "needs a reason" do
      package = register!()

      assert {:error, changeset} = Import.deny_package(test_actor(), package, "  ")
      assert "can't be blank" in errors_on(changeset).denied_reason
      assert Import.get_package!(package.id).status == :received
    end

    test "is refused for a denied package" do
      package = register!()
      {:ok, denied} = Import.deny_package(test_actor(), package, "No.")

      assert {:error, :not_deniable} = Import.deny_package(test_actor(), denied, "Again.")
    end

    test "is refused once the package is applied" do
      package = applied_package!()

      assert {:error, :not_deniable} = Import.deny_package(test_actor(), package, "Too late.")
      assert [%Batch{status: :applied} = batch] = Import.list_batches(package)
      assert {:error, :not_deniable} = Import.deny_batch(test_actor(), batch, "Too late.")
      assert replay_entries(:package_denied) == []
    end

    test "replays by the package's key" do
      package = awaiting!()

      assert {:ok, 1} =
               Replay.run(
                 [
                   %{
                     "kind" => "package_denied",
                     "key" => %{"package" => package.key},
                     "payload" => %{"reason" => "Replayed."}
                   }
                 ],
                 actor: test_actor()
               )

      assert %Package{status: :denied, denied_reason: "Replayed."} =
               Import.get_package!(package.id)

      # Already denied: skipped.
      assert {:ok, 1} = Replay.run(replay_entries(:package_denied), actor: test_actor())
      assert [_] = replay_entries(:package_denied)
    end
  end

  describe "deny_batch/3" do
    setup do
      taxonomy = taxonomy_batch() |> unique_batch_id()
      package = awaiting!(taxonomy: taxonomy)
      batches = Map.new(Import.list_batches(package), &{&1.batch_type, &1})
      %{package: package, gall: batches.gall, taxonomy: batches.taxonomy}
    end

    test "denies one batch and drops its open items; the package waits on", ctx do
      assert Import.list_queue_items(ctx.package) |> Enum.any?(&(&1.batch_id == ctx.gall.id))

      assert {:ok, %Batch{status: :denied, denied_reason: "Wrong Source."}} =
               Import.deny_batch(test_actor(), ctx.gall, "Wrong Source.")

      refute Import.list_queue_items(ctx.package) |> Enum.any?(&(&1.batch_id == ctx.gall.id))
      assert Import.get_package!(ctx.package.id).status == :awaiting_review
      assert Import.get_batch!(ctx.taxonomy.id).status != :denied
      assert audited?("import_batches", ctx.gall.id, "denied")

      assert [entry] = replay_entries(:batch_denied)

      assert entry.key == %{
               "package" => ctx.package.key,
               "batch_id" => ctx.gall.producer_batch_id
             }

      # Resolving again leaves the denied batch as it is.
      {:ok, _} = Import.resolve_package(test_actor(), ctx.package)
      assert Import.get_batch!(ctx.gall.id).status == :denied
      refute Import.list_queue_items(ctx.package) |> Enum.any?(&(&1.batch_id == ctx.gall.id))
    end

    test "denying the last batch denies the package", ctx do
      {:ok, _} = Import.deny_batch(test_actor(), ctx.gall, "Wrong Source.")
      {:ok, _} = Import.deny_batch(test_actor(), ctx.taxonomy, "Not needed.")

      assert %Package{status: :denied, denied_reason: "Not needed."} =
               Import.get_package!(ctx.package.id)

      assert Import.list_queue_items(ctx.package) == []
    end

    test "is refused for a denied batch", ctx do
      {:ok, denied} = Import.deny_batch(test_actor(), ctx.gall, "Wrong Source.")
      assert {:error, :not_deniable} = Import.deny_batch(test_actor(), denied, "Again.")
    end

    test "needs a reason", ctx do
      assert {:error, changeset} = Import.deny_batch(test_actor(), ctx.gall, nil)
      assert "can't be blank" in errors_on(changeset).denied_reason
    end

    test "a denied taxonomy batch no longer names new taxa for the gall batch" do
      taxonomy =
        taxonomy_batch()
        |> unique_batch_id()
        |> put_in(["taxa", Access.at(0)], %{
          "ref" => "t1",
          "name_as_written" => "Andricus novus",
          "rank" => "species",
          "new" => %{"status" => "sp. nov."}
        })

      gall =
        batch()
        |> unique_batch_id()
        |> put_in(["taxa", Access.at(0), "name_as_written"], "Andricus novus")

      package = awaiting!(taxonomy: taxonomy, gall: gall)
      batches = Map.new(Import.list_batches(package), &{&1.batch_type, &1})
      inducer = fn -> Enum.find(Import.list_statements(batches.gall), &(&1.ref == "t1")) end

      assert inducer.().resolution == :new

      {:ok, _} = Import.deny_batch(test_actor(), batches.taxonomy, "Not this revision.")
      {:ok, _} = Import.resolve_package(test_actor(), package)

      assert inducer.().resolution != :new
    end

    test "replays by the package's key and the producer's batch_id", ctx do
      entry = %{
        kind: :batch_denied,
        key: %{"package" => ctx.package.key, "batch_id" => ctx.gall.producer_batch_id},
        payload: %{"reason" => "Replayed."}
      }

      assert {:ok, 1} = Replay.run([entry], actor: test_actor())
      assert %Batch{status: :denied, denied_reason: "Replayed."} = Import.get_batch!(ctx.gall.id)
    end
  end

  # A Gall-only package applied through the worker (inline in tests).
  defp applied_package! do
    load_vocab!()
    plant_fixture(name: "Quercus lobata")
    taxon_fixture(name: "Andricus quercuscalifornicus", kingdom: "Animalia")
    taxon_fixture(name: "Torymus", rank: :genus, kingdom: "Animalia")

    gall =
      batch()
      |> unique_batch_id()
      |> put_in(["taxa", Access.at(1), "name_as_written"], "Quercus lobata")
      |> put_in(["galls", Access.at(0), "new"], true)

    package = package(gall: gall) |> with_review() |> deliver!()
    {:ok, %Package{status: :approved}} = Import.approve_package(test_actor(), package)
    package = Import.get_package!(package.id)
    assert [%Batch{status: :applied}] = Import.list_batches(package)
    package
  end

  describe "submit_gallformers_fragment/2" do
    setup do
      load_vocab!()
      gallformers = gallformers_source()
      andricus = Taxa.get_by_legacy_id(:taxonomy, 33)
      wasp = taxon_fixture(name: "Andricus quercuscalifornicus", parent: andricus)
      legacy = source_fixture("Legacy", "1990")
      gall = gall_fixture(name: "Andricus quercuscalifornicus (agamic)", generation: "agamic")

      {:ok, _} =
        Catalog.assert_relationship(
          test_actor(),
          %{type: "inducer_of", subject_taxon_id: wasp.id, object_gall_id: gall.id},
          confirm(legacy)
        )

      %{gallformers: gallformers, gall: gall}
    end

    # A curator's range exclusion of `gall` from California, as the Gall
    # page's form writes it (no batch_id: each submission gets its own).
    defp exclusion(gall) do
      %{
        "format" => "gallformers-import",
        "format_version" => 3,
        "vocabulary_version" => "2026-10-11",
        "batch_type" => "gall",
        "mode" => "add",
        "produced_at" => "2026-10-27T12:00:00Z",
        "producer" => %{"name" => "gallformers-admin", "version" => "1"},
        "source" => %{"gallformers" => true},
        "taxa" => [
          %{
            "ref" => "t1",
            "name_as_written" => "Andricus quercuscalifornicus",
            "rank" => "species"
          }
        ],
        "galls" => [
          %{
            "ref" => "g1",
            "name_as_written" => gall.name,
            "gallformers_gall_id" => gall.id,
            "identified_by" => %{
              "inducer" => "t1",
              "generation" => %{"value" => "agamic", "as_written" => "agamic"}
            }
          }
        ],
        "facts" => [
          %{
            "id" => "f1",
            "stance" => "confirm",
            "kind" => "range",
            "gall" => "g1",
            "adjustment" => "exclude",
            "place" => %{"value" => "US-CA", "as_written" => "California"},
            "evidence" => [
              %{
                "statement" => %{
                  "text" => "No gall has been recorded in California.",
                  "stated_on" => "2026-10-27"
                }
              }
            ]
          }
        ]
      }
    end

    defp fact_id(package, ref) do
      [batch] = Import.list_batches(package)

      Enum.find_value(
        Import.list_statements(batch),
        &(&1.kind == :fact && &1.ref == ref && &1.fact_id)
      )
    end

    test "a range exclusion is applied end to end as a Gallformers statement", ctx do
      assert {:ok, %Package{status: :approved} = package} =
               Import.submit_gallformers_fragment(test_actor(), %{
                 "gall.json" => exclusion(ctx.gall)
               })

      assert package.source_id == ctx.gallformers.id
      assert [%Batch{status: :applied, mode: :add} = batch] = Import.list_batches(package)
      assert batch.producer_batch_id =~ ~r/\A[0-9a-f-]{36}\z/

      fact_id = fact_id(package, "f1")

      assert %RangeFact{adjustment: :exclude, gall_id: gall_id, place_id: place_id} =
               Repo.get_by!(RangeFact, fact_id: fact_id)

      assert gall_id == ctx.gall.id
      assert place_id == place_id("US-CA")

      assert [attribution] = Facts.list_attributions(fact_id)
      assert attribution.source_id == ctx.gallformers.id
      assert attribution.statement_text == "No gall has been recorded in California."
      assert attribution.stated_on == ~D[2026-10-27]

      assert %{entries: [_]} = Import.list_packages(status: :approved)
    end

    test "each fragment gets its own batch_id and package", ctx do
      {:ok, first} =
        Import.submit_gallformers_fragment(test_actor(), %{"gall.json" => exclusion(ctx.gall)})

      {:ok, second} =
        Import.submit_gallformers_fragment(test_actor(), %{"gall.json" => exclusion(ctx.gall)})

      assert first.key != second.key
      assert second.status == :approved
      [one] = Import.list_batches(first)
      [two] = Import.list_batches(second)
      assert one.producer_batch_id != two.producer_batch_id
    end

    test "a fragment that needs a decision stays awaiting review", ctx do
      fragment =
        ctx.gall
        |> exclusion()
        |> Map.update!(
          "taxa",
          &(&1 ++
              [%{"ref" => "t2", "name_as_written" => "Nonexistus plantus", "rank" => "species"}])
        )
        |> Map.update!("facts", fn facts ->
          facts ++
            [
              %{
                "id" => "f2",
                "stance" => "confirm",
                "kind" => "relationship",
                "type" => "host_of",
                "subject" => "t2",
                "object" => "g1",
                "evidence" => [
                  %{"statement" => %{"text" => "Seen on it.", "stated_on" => "2026-10-27"}}
                ]
              }
            ]
        end)

      assert {:ok, %Package{status: :awaiting_review} = package} =
               Import.submit_gallformers_fragment(test_actor(), %{"gall.json" => fragment})

      assert [%QueueItem{kind: :unresolved_host}] = Import.list_queue_items(package)
      assert [%Batch{status: :blocked}] = Import.list_batches(package)
      assert Repo.all(from(r in RangeFact, where: r.gall_id == ^ctx.gall.id)) == []
    end

    test "only Gallformers' own batches are taken", ctx do
      publication = Map.put(exclusion(ctx.gall), "source", batch()["source"])

      assert {:error, :not_gallformers} =
               Import.submit_gallformers_fragment(test_actor(), %{"gall.json" => publication})

      assert {:error, :not_gallformers} = Import.submit_gallformers_fragment(test_actor(), %{})

      assert {:error, :not_gallformers} =
               Import.submit_gallformers_fragment(test_actor(), %{
                 "document.json" => exclusion(ctx.gall)
               })

      assert %{total: 0} = Import.list_packages()
    end
  end
end
