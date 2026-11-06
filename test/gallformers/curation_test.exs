defmodule Gallformers.CurationTest do
  @moduledoc """
  The curation tray (`Gallformers.Curation`, matter `ec2c` "Change-set
  interface"): a curator's change set of Fact items, notes and editorial
  edits, saved with their account, previewed against current data and
  applied item by item — Fact items as one Gallformers package through the
  import, the rest at once.

  Not async: the tests load the vocabularies and make the Gallformers
  Source (one per database).
  """
  use Gallformers.DataCase, async: false

  import Gallformers.CatalogFixtures
  import Gallformers.TaxaFixtures

  alias Gallformers.Accounts
  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog
  alias Gallformers.Curation
  alias Gallformers.Curation.ChangeSet
  alias Gallformers.Curation.Item
  alias Gallformers.Curation.PackageListener
  alias Gallformers.Curation.Wording
  alias Gallformers.Facts
  alias Gallformers.Import
  alias Gallformers.Import.Package
  alias Gallformers.Sources
  alias Gallformers.Taxa

  defp user!(name) do
    {:ok, user} =
      Accounts.create_user(%{
        auth0_id: "auth0|curation-#{System.unique_integer([:positive])}",
        display_name: name
      })

    Actor.user(user.id, name)
  end

  setup do
    ada = user!("Ada")
    :ok = put_test_actor(ada)
    load_vocab!()
    gallformers = gallformers_source()
    weld = source_fixture("Weld", "1959")
    wasp = taxon_fixture(name: "Andricus curatus", kingdom: "Animalia")
    oak = plant_fixture(name: "Quercus curata")
    gall = gall_fixture(name: "Andricus curatus gall")

    {:ok, %{fact: host}} =
      Catalog.assert_relationship(
        ada,
        %{type: "host_of", subject_taxon_id: oak.id, object_gall_id: gall.id},
        confirm(weld)
      )

    {:ok, _} =
      Catalog.assert_relationship(
        ada,
        %{type: "inducer_of", subject_taxon_id: wasp.id, object_gall_id: gall.id},
        confirm(weld)
      )

    {:ok, %{fact: spring}} =
      Catalog.assert_trait(
        ada,
        %{gall_id: gall.id, trait: "season", value: "Spring"},
        confirm(weld, %{value_as_written: "spring"})
      )

    %{
      ada: ada,
      gallformers: gallformers,
      weld: weld,
      wasp: wasp,
      oak: oak,
      gall: gall,
      host: host,
      spring: spring
    }
  end

  # Gallformers' own confirming statement of `fact`, citing one observation.
  defp gallformers_states!(ctx, fact, observation_id) do
    {:ok, _} =
      Facts.attribute(
        ctx.ada,
        confirm(ctx.gallformers, %{
          fact_id: fact.id,
          statement_text: "Seen on iNaturalist.",
          stated_on: ~D[2025-06-01],
          observations: [%{provider: :inaturalist, external_id: observation_id}]
        })
      )
  end

  defp add!(actor, spec) do
    {:ok, item} = Curation.add_item(actor, spec)
    item
  end

  defp new_host!(ctx) do
    rubra = plant_fixture(name: "Quercus rubricurata")

    {rubra,
     add!(ctx.ada, %{kind: :fact, gall_id: ctx.gall.id, action: :add, key: {:host, rubra.id}})}
  end

  defp flags(actor, item_id) do
    actor
    |> Curation.preview()
    |> Enum.find(&(&1.id == item_id))
    |> Map.fetch!(:flags)
  end

  defp kinds(flags), do: Enum.map(flags, & &1.kind)

  # A curator's change in the audit trail, as Carbonite records it, after
  # the tray's items were added: a test runs in one database transaction,
  # so another curator's change is written there directly.
  defp others_change!(who_id, who, table, op, data, changed \\ []) do
    id = System.unique_integer([:positive]) + 2_000_000_000_000
    at = NaiveDateTime.utc_now() |> NaiveDateTime.add(60)

    Repo.query!(
      "INSERT INTO carbonite_default.transactions (id, xact_id, meta, inserted_at) VALUES ($1, $2::xid8, $3, $4)",
      [
        id,
        id,
        %{actor: %{type: "user", id: who_id, name: who}, operation: "test.change"},
        at
      ]
    )

    Repo.query!(
      """
      INSERT INTO carbonite_default.changes
        (transaction_id, transaction_xact_id, op, table_prefix, table_name, data, changed)
      VALUES ($1, $2::xid8, $3::text::carbonite_default.change_op, 'public', $4, $5, $6)
      """,
      [id, id, op, table, data, changed]
    )

    at
  end

  describe "the set and its items" do
    test "a curator has no set until they add an item", ctx do
      assert Curation.open_set(ctx.ada) == nil
      {rubra, item} = new_host!(ctx)

      assert %Item{id: id, kind: :fact, key: {:host, rubra_id}, state: :in_tray} = item
      assert rubra_id == rubra.id
      assert item.subject == {:gall, ctx.gall.id}
      assert item.text == "Add host: Quercus rubricurata"
      assert item.subject_name == "Andricus curatus gall"

      assert %ChangeSet{items: [%Item{id: ^id}]} = Curation.open_set(ctx.ada)
    end

    test "a set is its author's own", ctx do
      new_host!(ctx)
      assert Curation.open_set(user!("Bea")) == nil
    end

    test "one item per Fact key: another edit of it replaces the first", ctx do
      {rubra, item} = new_host!(ctx)
      key = {:host, rubra.id}

      {:ok, again} =
        Curation.add_item(ctx.ada, %{
          kind: :fact,
          gall_id: ctx.gall.id,
          action: :withdraw,
          key: key
        })

      assert again.id == item.id
      assert again.spec.action == :withdraw
      assert again.text == "Withdraw host: Quercus rubricurata"
      assert [_one] = Curation.open_set(ctx.ada).items

      # A note on the same Fact is an item of its own.
      {:ok, note} =
        Curation.add_item(ctx.ada, %{
          kind: :note,
          gall_id: ctx.gall.id,
          key: {:host, ctx.oak.id},
          text: "Young trees only."
        })

      assert note.text == "Note on host: Quercus curata"
    end

    test "a correction names the old and the new", ctx do
      item =
        add!(ctx.ada, %{
          kind: :fact,
          gall_id: ctx.gall.id,
          action: :correct,
          key: {:trait, "season", "Spring"},
          to: {:trait, "season", "Summer"}
        })

      assert item.text == "Correct season: Spring → Summer"
    end

    test "what cannot be an item is refused", ctx do
      fact = %{kind: :fact, gall_id: ctx.gall.id, action: :add}

      assert Curation.add_item(
               ctx.ada,
               %{fact | gall_id: 999_999_999} |> Map.put(:key, {:host, ctx.oak.id})
             ) ==
               {:error, :no_such_gall}

      assert {:error, :invalid_key} =
               Curation.add_item(ctx.ada, Map.put(fact, :key, {:trait, "color", "plaid"}))

      assert {:error, :invalid_key} =
               Curation.add_item(ctx.ada, Map.put(fact, :key, {:host, ctx.wasp.id}))

      assert {:error, :invalid_key} =
               Curation.add_item(ctx.ada, Map.put(fact, :key, {:colour, 1}))

      assert {:error, :no_such_place} =
               Curation.add_item(ctx.ada, Map.put(fact, :key, {:occurrence, 999_999_999}))

      assert {:error, :invalid_spec} =
               Curation.add_item(
                 ctx.ada,
                 %{fact | action: :correct} |> Map.put(:key, {:host, ctx.oak.id})
               )

      assert {:error, :no_fact} =
               Curation.add_item(ctx.ada, %{
                 kind: :note,
                 gall_id: ctx.gall.id,
                 key: {:alias, "oak apple"},
                 text: "x"
               })

      assert {:error, :unknown_field} =
               Curation.add_item(ctx.ada, %{
                 kind: :editorial,
                 subject: {:gall, ctx.gall.id},
                 field: :colour,
                 value: "red"
               })

      assert {:error, :no_such_plant} =
               Curation.add_item(ctx.ada, %{
                 kind: :editorial,
                 subject: {:plant, ctx.wasp.id},
                 field: :name,
                 value: "Quercus nova"
               })

      assert Curation.open_set(ctx.ada) == nil
    end

    test "remove_item/2 and discard/1", ctx do
      {_rubra, item} = new_host!(ctx)

      other =
        add!(ctx.ada, %{
          kind: :editorial,
          subject: {:gall, ctx.gall.id},
          field: :abundance,
          value: 1
        })

      assert :ok = Curation.remove_item(ctx.ada, item.id)
      assert [%Item{id: id}] = Curation.open_set(ctx.ada).items
      assert id == other.id
      assert {:error, :not_found} = Curation.remove_item(user!("Bea"), other.id)

      assert :ok = Curation.discard(ctx.ada)
      assert Curation.open_set(ctx.ada) == nil
    end

    test "evidence for the set, and an item's own", ctx do
      {_rubra, item} = new_host!(ctx)

      assert {:ok, %ChangeSet{evidence: evidence}} =
               Curation.set_evidence(ctx.ada, %{
                 text: "Seen it.",
                 observations: [%{provider: "inaturalist", id: 123}],
                 source_id: nil
               })

      assert evidence == %{
               text: "Seen it.",
               observations: [%{provider: "inaturalist", id: "123"}],
               source_id: nil
             }

      assert {:ok, %Item{evidence: %{source_id: weld_id}}} =
               Curation.set_item_evidence(ctx.ada, item.id, %{text: "", source_id: ctx.weld.id})

      assert weld_id == ctx.weld.id
      assert {:ok, %Item{evidence: nil}} = Curation.set_item_evidence(ctx.ada, item.id, nil)

      assert {:error, :invalid_evidence} =
               Curation.set_evidence(ctx.ada, %{observations: [%{provider: "flickr", id: "1"}]})

      assert {:error, :invalid_evidence} =
               Curation.set_evidence(ctx.ada, %{source_id: 999_999_999})
    end

    test "pending_for/2, others_pending/2 and summary/1", ctx do
      {rubra, _item} = new_host!(ctx)
      bea = user!("Bea")
      add!(bea, %{kind: :editorial, subject: {:gall, ctx.gall.id}, field: :abundance, value: 2})

      key = {:host, rubra.id}
      assert %{^key => [%Item{}]} = Curation.pending_for(ctx.ada, {:gall, ctx.gall.id})
      assert Curation.pending_for(ctx.ada, {:plant, ctx.oak.id}) == %{}

      assert [%{user: %{id: bea_id, name: "Bea"}, count: 1, since: %DateTime{}}] =
               Curation.others_pending({:gall, ctx.gall.id}, ctx.ada)

      assert bea_id == bea.id
      assert length(Curation.others_pending({:gall, ctx.gall.id})) == 2

      assert %{count: 1, lines: [line], oldest_at: %DateTime{}} = Curation.summary(ctx.ada)
      assert line == "Andricus curatus gall: Add host: Quercus rubricurata"
      assert Curation.summary(user!("Cy")) == %{count: 0, lines: [], oldest_at: nil}
    end

    test "changes are broadcast to the curator and to the subject's page", ctx do
      %Actor{id: ada_id} = ctx.ada
      Curation.subscribe(ctx.ada)
      Curation.subscribe_subject({:gall, ctx.gall.id})

      {_rubra, item} = new_host!(ctx)
      assert_received {:change_set, :changed}
      assert_received {:change_set, :others_changed}

      :ok = Curation.remove_item(ctx.ada, item.id)
      assert_received {:change_set, :changed}
      assert_received {:change_set, :others_changed}
      assert is_integer(ada_id)
    end
  end

  describe "preview/1" do
    test "a Fact Gallformers holds already is held; a new one is new", ctx do
      held =
        add!(ctx.ada, %{kind: :fact, gall_id: ctx.gall.id, action: :add, key: {:host, ctx.oak.id}})

      {_rubra, new} = new_host!(ctx)

      assert [%{kind: :held, flag: {:held, [%{id: weld_id}]}, text: text} | _] =
               flags(ctx.ada, held.id)

      assert weld_id == ctx.weld.id
      assert text =~ "Already held: Weld 1959"
      assert [%{kind: :held}, %{kind: :adds_statement}] = flags(ctx.ada, held.id)
      assert [%{kind: :new, text: "New"}] = flags(ctx.ada, new.id)
    end

    test "withdrawing a Source's Fact supersedes its statement, and needs a reason", ctx do
      item =
        add!(ctx.ada, %{
          kind: :fact,
          gall_id: ctx.gall.id,
          action: :withdraw,
          key: {:trait, "season", "Spring"}
        })

      flags = flags(ctx.ada, item.id)
      assert kinds(flags) == [:supersedes, :needs_reason]

      [%{flag: {:supersedes, [statement]}, text: text} | _] = flags
      assert statement.source_id == ctx.weld.id
      assert statement.words == "spring"
      assert statement.stated_on == ~D[1959-01-01]
      assert text == "Supersedes Weld 1959's 'spring'"

      {:ok, _} = Curation.set_evidence(ctx.ada, %{text: "Galls form in summer here."})
      assert kinds(flags(ctx.ada, item.id)) == [:supersedes]
    end

    test "withdrawing a Fact only Gallformers states needs no reason", ctx do
      ash = plant_fixture(name: "Fraxinus curata")
      legacy = Sources.get_legacy_data_source()

      {:ok, _} =
        Catalog.assert_relationship(
          ctx.ada,
          %{type: "host_of", subject_taxon_id: ash.id, object_gall_id: ctx.gall.id},
          confirm(legacy)
        )

      {:ok, _} =
        Catalog.assert_relationship(
          ctx.ada,
          %{type: "host_of", subject_taxon_id: ash.id, object_gall_id: ctx.gall.id},
          confirm(ctx.gallformers, %{statement_text: "On ash.", stated_on: ~D[2024-05-01]})
        )

      item =
        add!(ctx.ada, %{
          kind: :fact,
          gall_id: ctx.gall.id,
          action: :withdraw,
          key: {:host, ash.id}
        })

      assert kinds(flags(ctx.ada, item.id)) == [:supersedes]
    end

    test "a Source whose name ends in s takes an apostrophe alone" do
      assert Wording.flag_text({:supersedes, [%{source: "Gallformers", words: nil}]}) ==
               "Supersedes Gallformers' statement"

      assert Wording.flag_text({:supersedes, [%{source: "Gallformers", words: "spring"}]}) ==
               "Supersedes Gallformers' 'spring'"
    end

    test "a correction in a single-valued slot supersedes the value held", ctx do
      {:ok, _} =
        Catalog.assert_trait(
          ctx.ada,
          %{gall_id: ctx.gall.id, trait: "detachable", value: "integral"},
          confirm(ctx.weld)
        )

      item =
        add!(ctx.ada, %{
          kind: :fact,
          gall_id: ctx.gall.id,
          action: :add,
          key: {:trait, "detachable", "detachable"}
        })

      assert [%{kind: :supersedes}, %{kind: :needs_reason}] = flags(ctx.ada, item.id)
    end

    test "editorial items need no evidence; a code change needs confirmation", ctx do
      abundance =
        add!(ctx.ada, %{
          kind: :editorial,
          subject: {:gall, ctx.gall.id},
          field: :abundance,
          value: 1
        })

      code =
        add!(ctx.ada, %{
          kind: :editorial,
          subject: {:gall, ctx.gall.id},
          field: :code,
          value: "ACUR"
        })

      note =
        add!(ctx.ada, %{
          kind: :note,
          gall_id: ctx.gall.id,
          key: {:host, ctx.oak.id},
          text: "Young."
        })

      assert kinds(flags(ctx.ada, abundance.id)) == [:editorial]
      assert kinds(flags(ctx.ada, code.id)) == [:editorial, :needs_confirmation]
      assert kinds(flags(ctx.ada, note.id)) == [:editorial]
      assert abundance.text == "Abundance: common"
      assert code.text == "Gallformers code: ACUR"
    end

    test "a check that fails blocks the item", ctx do
      gall_fixture(gallformers_code: "TAKEN")

      code =
        add!(ctx.ada, %{
          kind: :editorial,
          subject: {:gall, ctx.gall.id},
          field: :code,
          value: "TAKEN"
        })

      assert [%{kind: :editorial}, %{kind: :needs_confirmation}, %{kind: :blocked, text: text}] =
               flags(ctx.ada, code.id)

      assert text =~ "Can't apply"
    end

    test "another curator's change since the item was added is flagged", ctx do
      item =
        add!(ctx.ada, %{
          kind: :fact,
          gall_id: ctx.gall.id,
          action: :withdraw,
          key: {:host, ctx.oak.id}
        })

      abundance =
        add!(ctx.ada, %{
          kind: :editorial,
          subject: {:gall, ctx.gall.id},
          field: :abundance,
          value: 1
        })

      at =
        others_change!(99, "Adam", "attributions", "update", %{
          id: 1,
          fact_id: ctx.host.id
        })

      assert %{flag: {:changed_since, %{id: 99, name: "Adam"}, ^at}, text: text} =
               Enum.find(flags(ctx.ada, item.id), &(&1.kind == :changed_since))

      assert text =~ "Adam changed this since you added it"
      refute Enum.any?(flags(ctx.ada, abundance.id), &(&1.kind == :changed_since))

      others_change!(99, "Adam", "galls", "update", %{id: ctx.gall.id}, ["abundance_id"])
      assert :changed_since in kinds(flags(ctx.ada, abundance.id))

      # The curator's own changes are not flagged.
      %Actor{id: ada_id} = ctx.ada
      others_change!(ada_id, "Ada", "galls", "update", %{id: ctx.gall.id}, ["gallformers_code"])

      code =
        add!(ctx.ada, %{
          kind: :editorial,
          subject: {:gall, ctx.gall.id},
          field: :code,
          value: "Q1"
        })

      refute Enum.any?(flags(ctx.ada, code.id), &(&1.kind == :changed_since))
    end
  end

  describe "apply/2" do
    test "an editorial item applies at once and leaves the tray", ctx do
      item =
        add!(ctx.ada, %{
          kind: :editorial,
          subject: {:gall, ctx.gall.id},
          field: :abundance,
          value: 3
        })

      assert {:ok, %{applied: [id], submitted: [], held: []}} = Curation.apply(ctx.ada)
      assert id == item.id
      assert Catalog.get_gall!(ctx.gall.id).abundance_id == 3
      assert Curation.open_set(ctx.ada) == nil
    end

    test "a code change applies only when confirmed", ctx do
      item =
        add!(ctx.ada, %{
          kind: :editorial,
          subject: {:gall, ctx.gall.id},
          field: :code,
          value: "ACUR"
        })

      assert {:ok, %{applied: [], held: [{id, reason}]}} = Curation.apply(ctx.ada)
      assert id == item.id
      assert reason =~ "confirmation"
      assert Catalog.get_gall!(ctx.gall.id).gallformers_code == nil

      assert {:ok, %{applied: [^id]}} = Curation.apply(ctx.ada, confirm: [id])
      assert Catalog.get_gall!(ctx.gall.id).gallformers_code == "ACUR"
    end

    test "Fact items become a Gallformers package the import applies", ctx do
      Curation.subscribe(ctx.ada)
      {rubra, item} = new_host!(ctx)

      {:ok, _} =
        Curation.set_evidence(ctx.ada, %{
          text: "On red oak in Virginia.",
          observations: [%{provider: "inaturalist", id: "555"}]
        })

      assert {:ok, %{applied: [], submitted: [id], held: []}} = Curation.apply(ctx.ada)
      assert id == item.id
      assert_received {:change_set, {:outcome, ^id, :applied}}

      assert {:ok, fact_id} = Catalog.find_gall_fact(ctx.gall.id, {:host, rubra.id})
      assert Facts.get_fact!(fact_id).standing == :current
      assert [attribution] = Facts.list_attributions(fact_id)
      assert attribution.source_id == ctx.gallformers.id
      assert attribution.statement_text == "On red oak in Virginia."
      assert attribution.stated_on == Date.utc_today()
      assert [%{provider: :inaturalist, external_id: "555"}] = attribution.observations

      assert %{entries: [%Package{submitter_user_id: user_id}]} = Import.list_packages()
      assert user_id == ctx.ada.id
      assert Curation.open_set(ctx.ada) == nil
    end

    test "a recorded occurrence carries when it was seen", ctx do
      california = place_id("US-CA")

      item =
        add!(ctx.ada, %{
          kind: :fact,
          gall_id: ctx.gall.id,
          action: :add,
          key: {:occurrence, california},
          when: "2025-07-14"
        })

      assert item.spec.when == "2025-07-14"
      assert item.text == "Add recorded in California (2025-07-14)"

      {:ok, _} =
        Curation.set_item_evidence(ctx.ada, item.id, %{
          observations: [%{provider: "inaturalist", id: "4242"}]
        })

      assert {:ok, %{submitted: [_]}} = Curation.apply(ctx.ada)
      assert {:ok, fact_id} = Catalog.find_gall_fact(ctx.gall.id, {:occurrence, california})
      assert [attribution] = Facts.list_attributions(fact_id)
      assert attribution.when_as_written == "2025-07-14"
    end

    test "only a recorded occurrence added takes a when", ctx do
      assert {:error, :invalid_spec} =
               Curation.add_item(ctx.ada, %{
                 kind: :fact,
                 gall_id: ctx.gall.id,
                 action: :add,
                 key: {:host, ctx.oak.id},
                 when: "2025-07-14"
               })

      assert {:error, :invalid_spec} =
               Curation.add_item(ctx.ada, %{
                 kind: :fact,
                 gall_id: ctx.gall.id,
                 action: :add,
                 key: {:occurrence, place_id("US-CA")},
                 when: ""
               })
    end

    test "a Source as evidence is cited by Gallformers' statement", ctx do
      item =
        add!(ctx.ada, %{
          kind: :fact,
          gall_id: ctx.gall.id,
          action: :correct,
          key: {:trait, "season", "Spring"},
          to: {:trait, "season", "Summer"}
        })

      {:ok, _} = Curation.set_item_evidence(ctx.ada, item.id, %{source_id: ctx.weld.id})
      assert {:ok, %{submitted: [_]}} = Curation.apply(ctx.ada)

      assert Facts.get_fact!(ctx.spring.id).standing == :withdrawn
      {:ok, summer} = Catalog.find_gall_fact(ctx.gall.id, {:trait, "season", "Summer"})
      assert Facts.get_fact!(summer).standing == :current

      gallformers =
        Enum.find(Facts.list_attributions(summer), &(&1.source_id == ctx.gallformers.id))

      assert gallformers.cited_source_id == ctx.weld.id
      assert gallformers.cites_as_written == "Weld 1959"
    end

    test "an item that supersedes a Source without a reason is held", ctx do
      item =
        add!(ctx.ada, %{
          kind: :fact,
          gall_id: ctx.gall.id,
          action: :withdraw,
          key: {:host, ctx.oak.id}
        })

      assert {:ok, %{submitted: [], held: [{id, reason}]}} = Curation.apply(ctx.ada)
      assert id == item.id
      assert reason =~ "reason"
      assert Facts.get_fact!(ctx.host.id).standing == :current
      assert [%Item{id: ^id, state: :in_tray}] = Curation.open_set(ctx.ada).items
    end

    test "a Fact a Source holds gains Gallformers' statement, so it survives a retraction", ctx do
      item =
        add!(ctx.ada, %{kind: :fact, gall_id: ctx.gall.id, action: :add, key: {:host, ctx.oak.id}})

      {:ok, _} =
        Curation.set_evidence(ctx.ada, %{observations: [%{provider: "inaturalist", id: "601"}]})

      assert {:ok, %{submitted: [id]}} = Curation.apply(ctx.ada)
      assert id == item.id

      gallformers =
        Enum.find(Facts.list_attributions(ctx.host.id), &(&1.source_id == ctx.gallformers.id))

      assert [%{external_id: "601"}] = gallformers.observations
    end

    test "a repeat observation adds to Gallformers' statement and keeps the earlier ones", ctx do
      gallformers_states!(ctx, ctx.host, "601")

      item =
        add!(ctx.ada, %{kind: :fact, gall_id: ctx.gall.id, action: :add, key: {:host, ctx.oak.id}})

      {:ok, _} =
        Curation.set_evidence(ctx.ada, %{observations: [%{provider: "inaturalist", id: "602"}]})

      assert [%{kind: :held}, %{kind: :adds_statement}] = flags(ctx.ada, item.id)
      assert {:ok, %{submitted: [_]}} = Curation.apply(ctx.ada)

      gallformers =
        Enum.find(Facts.list_attributions(ctx.host.id), &(&1.source_id == ctx.gallformers.id))

      assert gallformers.observations |> Enum.map(& &1.external_id) |> Enum.sort() ==
               ["601", "602"]
    end

    test "what Gallformers already states with the same evidence is a no-op", ctx do
      gallformers_states!(ctx, ctx.host, "601")

      item =
        add!(ctx.ada, %{kind: :fact, gall_id: ctx.gall.id, action: :add, key: {:host, ctx.oak.id}})

      {:ok, _} =
        Curation.set_evidence(ctx.ada, %{observations: [%{provider: "inaturalist", id: "601"}]})

      assert [%{kind: :held}] = flags(ctx.ada, item.id)
      assert {:ok, %{applied: [id], submitted: []}} = Curation.apply(ctx.ada)
      assert id == item.id
      assert %{total: 0} = Import.list_packages()
    end

    test "a note is recorded on its Fact and replay-logged", ctx do
      add!(ctx.ada, %{kind: :note, gall_id: ctx.gall.id, key: {:host, ctx.oak.id}, text: "Young."})

      assert {:ok, %{applied: [_]}} = Curation.apply(ctx.ada)
      assert %{} = notes = Catalog.list_fact_notes([ctx.host.id])
      assert [%{text: "Young.", author_name: "Ada"}] = notes[ctx.host.id]
      assert :fact_note in Enum.map(Import.list_replay_entries(), & &1.kind)
    end

    test "apply_item/3 applies only that item", ctx do
      {_rubra, fact} = new_host!(ctx)

      abundance =
        add!(ctx.ada, %{
          kind: :editorial,
          subject: {:gall, ctx.gall.id},
          field: :abundance,
          value: 2
        })

      assert {:ok, %{applied: [id], submitted: [], held: []}} =
               Curation.apply_item(ctx.ada, abundance.id)

      assert id == abundance.id
      assert [%Item{id: fact_id}] = Curation.open_set(ctx.ada).items
      assert fact_id == fact.id
      assert {:error, :not_found} = Curation.apply_item(ctx.ada, 999_999_999)
    end

    test "a plant's edits apply through the taxonomy admin's functions, with a based-on note",
         ctx do
      plant = plant_fixture(name: "Quercus editanda")
      {:ok, _} = Taxa.add_synonym(ctx.ada, plant, "Quercus vetus")

      add!(ctx.ada, %{
        kind: :editorial,
        subject: {:plant, plant.id},
        field: :synonyms,
        value: [%{name: "Quercus novus"}],
        based_on: "per Flora of North America"
      })

      name =
        add!(ctx.ada, %{
          kind: :editorial,
          subject: {:plant, plant.id},
          field: :name,
          value: "Quercus edita"
        })

      assert name.text == "Name: Quercus edita"
      assert {:ok, %{applied: [_, _], held: []}} = Curation.apply(ctx.ada)

      assert Taxa.accepted_name(plant.id) == "Quercus edita"
      synonyms = plant.id |> Taxa.list_synonyms() |> Enum.map(& &1.name) |> Enum.sort()
      assert "Quercus novus" in synonyms
      refute "Quercus vetus" in synonyms

      assert [%{about: "synonyms", text: "per Flora of North America"}] =
               Taxa.list_taxon_notes(plant.id)
    end
  end

  describe "the import job's outcomes" do
    test "a package waiting for review leaves its items waiting, with its link", ctx do
      Curation.subscribe(ctx.ada)
      {_rubra, item} = new_host!(ctx)

      package =
        Repo.insert!(%Package{
          key: "curation-#{System.unique_integer([:positive])}",
          s3_prefix: "import/x/",
          submitter_name: "Ada",
          status: :awaiting_review
        })

      :ok = Curation.put_submitted(item.id, package.id, ["f1"])
      :ok = PackageListener.package_advanced(package)

      package_id = package.id
      id = item.id
      assert_received {:change_set, {:outcome, ^id, {:waiting_review, ^package_id}}}
      assert [%Item{state: :waiting, status: :in_review}] = Curation.open_set(ctx.ada).items
    end

    test "a package refused holds its items with the reason", ctx do
      {_rubra, item} = new_host!(ctx)

      package =
        Repo.insert!(%Package{
          key: "curation-#{System.unique_integer([:positive])}",
          s3_prefix: "import/x/",
          submitter_name: "Ada",
          status: :invalid,
          problems: [%{"level" => "error", "message" => "bad batch"}]
        })

      :ok = Curation.put_submitted(item.id, package.id, ["f1"])
      :ok = PackageListener.package_advanced(package)

      assert [%Item{state: :in_tray, outcome: {:held, reason}}] = Curation.open_set(ctx.ada).items
      assert reason =~ "bad batch"
    end
  end
end
