defmodule GallformersWeb.Admin.ReviewLive.RenamesTest do
  @moduledoc """
  The Gall rename proposals (`/admin/review/renames`, `6611` Task 8): the
  `:gall_rename` queue items, which belong to no package, in the rows of a
  Source's step page, each decided in place (the recommended rename, or
  keeping the name); a name another Gall
  already has is flagged, and accepting it is refused with the reason. The
  Sources list leads to the page while any is open.

  Not async: the Catalog vocabularies are loaded.
  """
  use GallformersWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [audit_test_metadata: 1, test_actor: 0]
  import Gallformers.TaxaFixtures
  import GallformersWeb.AdminLiveHelpers

  alias Gallformers.Catalog
  alias Gallformers.Catalog.Gall
  alias Gallformers.Import
  alias Gallformers.Import.QueueItem
  alias Gallformers.Repo
  alias Gallformers.Taxa

  # Signing in makes the admin the test's actor, so it comes first.
  setup %{conn: conn} do
    {conn, _user} = log_in_admin(conn, "Rita Reviewer")
    %{conn: conn}
  end

  setup :audit_test_metadata

  # A rename proposal the tree made: renaming the Inducer of a Gall named
  # after it.
  defp proposal! do
    load_vocab!()
    source = source_fixture("Renamewell", "1961")
    genus = taxon_fixture(rank: :genus, name: "Renameta", kingdom: "Animalia")
    species = taxon_fixture(name: "Renameta alba", parent: genus, kingdom: "Animalia")
    gall = gall_fixture(name: "Renameta alba (agamic)", generation: "agamic")

    {:ok, _} =
      Catalog.assert_relationship(
        test_actor(),
        %{type: "inducer_of", subject_taxon_id: species.id, object_gall_id: gall.id},
        confirm(source)
      )

    {:ok, _} = Taxa.rename(test_actor(), species, "Renameta nigra")
    [item] = Enum.filter(Import.list_gall_renames(), &(&1.subject["gall_id"] == gall.id))
    %{gall: gall, item: item}
  end

  defp rename_item!(gall, from, to, collision) do
    %QueueItem{}
    |> QueueItem.create_changeset(%{
      kind: :gall_rename,
      subject: %{"gall_id" => gall.id},
      proposal: %{"gall_id" => gall.id, "from" => from, "to" => to, "collision" => collision},
      reason: "#{from} was renamed."
    })
    |> Repo.insert!()
  end

  defp open_row(view, item), do: view |> element("#item-#{item.id}-row") |> render_click()

  # Opens the item and decides it with the option labelled `label`.
  defp decide(view, item, label) do
    open_row(view, item)

    view
    |> element("#item-#{item.id}-choice-#{choice_index(view, item, label)}")
    |> render_click()

    view |> element("#item-#{item.id}-decide") |> render_click()
  end

  describe "the Sources list" do
    test "has a row for the open rename proposals, leading to their page", %{conn: conn} do
      proposal!()
      open = length(Import.list_gall_renames())

      {:ok, view, _html} = live(conn, ~p"/admin/review")

      assert has_element?(view, "#gall-renames", "Gall rename proposals")
      assert has_element?(view, "#gall-renames [data-role=to-decide]", "#{open}")

      assert {:error, {:live_redirect, %{to: to}}} =
               view |> element("#gall-renames a", "Gall rename proposals") |> render_click()

      assert to == ~p"/admin/review/renames"
    end

    test "has no such row when none is open", %{conn: conn} do
      for item <- Import.list_gall_renames(), do: Repo.delete!(item)

      {:ok, view, _html} = live(conn, ~p"/admin/review?filter=all")
      refute has_element?(view, "#gall-renames")
    end
  end

  describe "the page" do
    test "lists each proposal with the Gall's name from and to", %{conn: conn} do
      %{item: item} = proposal!()

      {:ok, view, html} = live(conn, ~p"/admin/review/renames")

      assert html =~ "Gall rename proposals"
      assert has_element?(view, "#section-gall_rename #item-#{item.id}", "Renameta alba (agamic)")
      assert has_element?(view, "#item-#{item.id}", "Rename it to Renameta nigra (agamic)")
      assert has_element?(view, "#item-#{item.id}-row", "Recommended")
    end

    test "the recommended rename renames the Gall, and the proposal leaves the list",
         %{conn: conn} do
      %{item: item, gall: gall} = proposal!()
      {:ok, view, _html} = live(conn, ~p"/admin/review/renames")

      decide(view, item, "Rename it to")

      assert %QueueItem{status: :decided, decision: %{"accept" => true}} =
               decided = Import.get_queue_item!(item.id)

      assert decided.decided_by_name == "Rita Reviewer"
      assert Catalog.get_gall!(gall.id).name == "Renameta nigra (agamic)"
      assert render(view) =~ "Decision recorded."
      refute has_element?(view, "#item-#{item.id}")

      # Decided proposals are listed on request, with their answer.
      view |> element("#show-decided") |> render_click()
      assert has_element?(view, "#item-#{item.id}", "Rename it to Renameta nigra (agamic)")
    end

    test "keeping the name keeps the Gall's name, with a note", %{conn: conn} do
      %{item: item, gall: gall} = proposal!()
      {:ok, view, _html} = live(conn, ~p"/admin/review/renames")

      open_row(view, item)

      view
      |> form("#item-#{item.id}-note-form", %{"note" => "The old name is the one in use."})
      |> render_submit()

      view
      |> element("#item-#{item.id}-choice-#{choice_index(view, item, "Keep the name")}")
      |> render_click()

      view |> element("#item-#{item.id}-decide") |> render_click()

      assert %QueueItem{decision: decision} = decided = Import.get_queue_item!(item.id)
      assert decision == %{"reject" => true}
      assert [%{text: "The old name is the one in use."}] = Import.list_notes(decided)
      assert Gall.display_name(Catalog.get_gall!(gall.id)) == "Renameta alba (agamic)"
    end

    test "a colliding name is flagged, and accepting it is refused with the reason",
         %{conn: conn} do
      %{item: item, gall: gall} = proposal!()
      other = gall_fixture(name: "Renameta other")

      {:ok, _} =
        Catalog.update_name_parts(test_actor(), other, %{name_override: "Renameta nigra (agamic)"})

      flagged = rename_item!(gall_fixture(), "Some gall", "Renameta nigra (agamic)", true)

      {:ok, view, _html} = live(conn, ~p"/admin/review/renames")

      # The flagged one has no recommendation, and says why.
      refute has_element?(view, "#item-#{flagged.id}-row", "Recommended")
      assert has_element?(view, "#item-#{flagged.id}", "already another Gall's name")

      # The other was proposed before the name was taken: renaming it is refused.
      decide(view, item, "Rename it to")

      assert has_element?(view, "#item-#{item.id}-error", "another Gall")
      assert Import.get_queue_item!(item.id).status == :open
      assert Catalog.get_gall!(gall.id).name == "Renameta alba (agamic)"
    end

    test "says so when nothing is open", %{conn: conn} do
      for item <- Import.list_gall_renames(), do: Repo.delete!(item)

      {:ok, view, _html} = live(conn, ~p"/admin/review/renames")
      assert render(view) =~ "No Gall rename proposal is waiting."
    end
  end

  # The index of the choice labelled `label` in an open item's choices.
  defp choice_index(view, item, label) do
    view
    |> element("#item-#{item.id}-choices label", label)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("input")
    |> LazyHTML.attribute("value")
    |> List.first()
  end
end
