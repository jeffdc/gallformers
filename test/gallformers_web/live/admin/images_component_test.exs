defmodule GallformersWeb.Admin.ImagesComponentTest do
  @moduledoc """
  The admin image component (`a856` Task 6,
  `GallformersWeb.Admin.ImagesComponent`): one owner's images (a Gall's or a
  taxon's) — upload, order, metadata with the attribution rules, copy
  metadata, delete, iNat import — hosted by a minimal LiveView.
  """
  use GallformersWeb.ConnCase, async: true

  import Ecto.Query
  import Gallformers.CatalogFixtures
  import Gallformers.DataCase, only: [test_actor: 0]
  import Phoenix.LiveViewTest

  alias Gallformers.Catalog
  alias Gallformers.Images
  alias Gallformers.Images.Image
  alias Gallformers.Licenses
  alias GallformersWeb.Admin.ImagesComponent
  alias GallformersWeb.Admin.InatImportComponent

  defmodule HostLive do
    use Phoenix.LiveView

    def mount(_params, session, socket),
      do: {:ok, Phoenix.Component.assign(socket, :owner, session["owner"])}

    def render(assigns) do
      ~H"""
      <div>
        <.live_component
          module={ImagesComponent}
          id="images"
          owner={@owner}
          uploader="Test Admin"
          name="Test owner"
        />
      </div>
      """
    end

    # Lets a test deliver a `send_update/2` from inside this LiveView, as a
    # background task's does.
    def handle_info({:send_update, module, attrs}, socket) do
      send_update(module, attrs)
      {:noreply, socket}
    end
  end

  defp mount_for(conn, owner), do: live_isolated(conn, HostLive, session: %{"owner" => owner})

  defp image!(owner, attrs \\ %{}) do
    {kind, id} = owner

    {:ok, image} =
      attrs
      |> Map.merge(Image.owner_attrs(owner))
      |> Map.put_new(:path, "#{kind}/#{id}/#{System.unique_integer([:positive])}_original.jpg")
      |> Images.create_image()

    image
  end

  defp attributed, do: %{license: "CC-BY", creator: "Jane Doe"}

  defp cite!(gall, source) do
    {:ok, 1} =
      Catalog.insert_legacy_citations(test_actor(), [
        %{gall_id: gall.id, source_id: source.id, description: "Cited.", useasdefault: false}
      ])

    :ok
  end

  defp hook(view), do: with_target(view, "#images")

  defp index_image_id(gall_id),
    do:
      Gallformers.Repo.one(
        from(r in "gall_index", where: r.gall_id == ^gall_id, select: r.image_id)
      )

  defp ids(owner), do: owner |> Images.list_images() |> Enum.map(& &1.id)

  # Returns once the LiveView has handled the messages in its mailbox and
  # those they send it in turn, `rounds` deep (each `:sys.get_state/1` is
  # answered after the messages already queued).
  defp settle(view, rounds), do: Enum.each(1..rounds, fn _ -> :sys.get_state(view.pid) end)

  describe "listing" do
    test "shows a Gall's images only, the first as the default", %{conn: conn} do
      gall = gall_fixture()
      other = gall_fixture()
      first = image!({:gall, gall.id}, attributed())
      second = image!({:gall, gall.id}, attributed())
      theirs = image!({:gall, other.id}, attributed())

      {:ok, view, _html} = mount_for(conn, {:gall, gall.id})

      assert has_element?(view, "#images [data-image-id='#{first.id}'] [data-default-image]")
      assert has_element?(view, "#images [data-image-id='#{second.id}']")
      refute has_element?(view, "#images [data-image-id='#{second.id}'] [data-default-image]")
      refute has_element?(view, "#images [data-image-id='#{theirs.id}']")
      assert render(view) =~ "Images (2)"
    end

    test "shows a taxon's images", %{conn: conn} do
      plant = plant_fixture()
      image = image!({:taxon, plant.id}, attributed())

      {:ok, view, _html} = mount_for(conn, {:taxon, plant.id})

      assert has_element?(view, "#images [data-image-id='#{image.id}']")
    end

    test "the table view lists the metadata", %{conn: conn} do
      gall = gall_fixture()
      image!({:gall, gall.id}, %{license: "CC-BY", creator: "Jane Doe", caption: "A bud gall"})

      {:ok, view, _html} = mount_for(conn, {:gall, gall.id})
      view |> element("#images button[phx-value-view=table]") |> render_click()

      assert has_element?(view, "#images table td", "Jane Doe")
      assert has_element?(view, "#images table td", "A bud gall")
    end
  end

  describe "the unattributed warning" do
    test "marks an image with no license, or a license needing a creator and none",
         %{conn: conn} do
      gall = gall_fixture()
      bare = image!({:gall, gall.id})
      no_creator = image!({:gall, gall.id}, %{license: "CC-BY"})
      cc0 = image!({:gall, gall.id}, %{license: "Public Domain / CC0"})
      credited = image!({:gall, gall.id}, attributed())

      {:ok, view, _html} = mount_for(conn, {:gall, gall.id})

      assert has_element?(view, "#images [data-unattributed-warning]")
      assert has_element?(view, "[data-image-id='#{bare.id}'] [data-unattributed]")
      assert has_element?(view, "[data-image-id='#{no_creator.id}'] [data-unattributed]")
      refute has_element?(view, "[data-image-id='#{cc0.id}'] [data-unattributed]")
      refute has_element?(view, "[data-image-id='#{credited.id}'] [data-unattributed]")
    end

    test "a licensed Source attributes an image", %{conn: conn} do
      gall = gall_fixture()
      source = source_fixture("Weld", "1959")
      image = image!({:gall, gall.id}, %{source_id: source.id})

      {:ok, view, _html} = mount_for(conn, {:gall, gall.id})

      refute has_element?(view, "[data-image-id='#{image.id}'] [data-unattributed]")
      refute has_element?(view, "#images [data-unattributed-warning]")
    end
  end

  describe "upload" do
    test "presigned URLs are for paths under the owner", %{conn: conn} do
      gall = gall_fixture()
      {:ok, view, _html} = mount_for(conn, {:gall, gall.id})

      view
      |> hook()
      |> render_hook("request_presigned_urls", %{
        "files" => [%{"name" => "a.jpg", "type" => "image/jpeg", "extension" => "jpg"}]
      })

      assert_push_event(view, "presigned_urls", %{
        urls: [%{path: path, content_type: "image/jpeg"}]
      })

      assert path =~ ~r{^gall/#{gall.id}/}
    end

    test "completed uploads become the owner's images, appended", %{conn: conn} do
      gall = gall_fixture()
      existing = image!({:gall, gall.id}, attributed())
      {:ok, view, _html} = mount_for(conn, {:gall, gall.id})

      view
      |> hook()
      |> render_hook("uploads_completed", %{
        "paths" => ["gall/#{gall.id}/a_original.jpg", "gall/#{gall.id}/b_original.jpg"]
      })

      assert [first, a, b] = Images.list_images({:gall, gall.id})
      assert first.id == existing.id

      assert {a.path, a.uploader, a.lastchangedby} ==
               {"gall/#{gall.id}/a_original.jpg", "Test Admin", "Test Admin"}

      assert b.path == "gall/#{gall.id}/b_original.jpg"
      assert has_element?(view, "#images [data-image-id='#{a.id}']")
      assert_push_event(view, "upload_complete", %{message: "2 image(s) uploaded successfully"})
    end

    test "a Gall's first image becomes its default in the ID tool's table", %{conn: conn} do
      gall = gall_fixture()
      {:ok, view, _html} = mount_for(conn, {:gall, gall.id})

      view |> hook() |> render_hook("uploads_completed", %{"paths" => ["gall/#{gall.id}/a.jpg"]})

      assert [%{id: id}] = Images.list_images({:gall, gall.id})
      assert index_image_id(gall.id) == id
    end

    test "a taxon's uploads are the taxon's", %{conn: conn} do
      plant = plant_fixture()
      {:ok, view, _html} = mount_for(conn, {:taxon, plant.id})

      view
      |> hook()
      |> render_hook("uploads_completed", %{"paths" => ["taxon/#{plant.id}/a_original.jpg"]})

      assert [%{taxon_id: taxon_id, gall_id: nil}] = Images.list_images({:taxon, plant.id})
      assert taxon_id == plant.id
    end
  end

  describe "reorder" do
    test "saves the new order and the Gall's new default", %{conn: conn} do
      gall = gall_fixture()
      a = image!({:gall, gall.id}, attributed())
      b = image!({:gall, gall.id}, attributed())
      {:ok, view, _html} = mount_for(conn, {:gall, gall.id})

      view |> hook() |> render_hook("reorder_images", %{"order" => [b.id, a.id]})

      assert ids({:gall, gall.id}) == [b.id, a.id]
      assert has_element?(view, "[data-image-id='#{b.id}'] [data-default-image]")
      assert index_image_id(gall.id) == b.id
      assert has_element?(view, "#images-flash-info", "Image order saved")
    end
  end

  describe "edit" do
    setup %{conn: conn} do
      gall = gall_fixture()
      image = image!({:gall, gall.id})
      {:ok, view, _html} = mount_for(conn, {:gall, gall.id})
      view |> element("[data-image-id='#{image.id}'] [data-action=edit]") |> render_click()

      %{gall: gall, image: image, view: view}
    end

    test "saves the metadata with the canonical link of a read-only license", %{
      view: view,
      image: image
    } do
      view
      |> element("#images-edit-form select[name=license]")
      |> render_change(%{license: "CC-BY"})

      view
      |> form("#images-edit-form", %{
        creator: "Jane Doe",
        licenselink: "https://example.com/not-the-license",
        caption: "A bud gall"
      })
      |> render_submit()

      saved = Images.get_image!(image.id)

      assert {saved.license, saved.licenselink, saved.creator, saved.caption, saved.lastchangedby} ==
               {"CC-BY", Licenses.url("CC-BY"), "Jane Doe", "A bud gall", "Test Admin"}

      refute has_element?(view, "#images-edit-modal")
      refute has_element?(view, "[data-image-id='#{image.id}'] [data-unattributed]")
    end

    test "refuses to leave the image unattributed", %{view: view, image: image} do
      view
      |> element("#images-edit-form select[name=license]")
      |> render_change(%{license: "CC-BY"})

      view |> form("#images-edit-form", %{caption: "Only a caption"}) |> render_submit()

      assert has_element?(view, "#images-edit-modal [data-attribution-error]")
      assert Images.get_image!(image.id).caption in [nil, ""]
    end

    test "a CC0 image needs no creator", %{view: view, image: image} do
      view
      |> element("#images-edit-form select[name=license]")
      |> render_change(%{license: "Public Domain / CC0"})

      view |> form("#images-edit-form", %{caption: "Public domain"}) |> render_submit()

      assert %{license: "Public Domain / CC0", caption: "Public domain"} =
               Images.get_image!(image.id)
    end

    test "picking one of the Gall's Sources fills license, link and creator", %{
      gall: gall,
      image: image,
      conn: conn
    } do
      source = source_fixture("Weld", "1959")
      _not_the_galls = source_fixture("Weld elsewhere", "1960")
      cite!(gall, source)

      {:ok, view, _html} = mount_for(conn, {:gall, gall.id})
      view |> element("[data-image-id='#{image.id}'] [data-action=edit]") |> render_click()

      view |> hook() |> render_hook("search_source", %{"value" => "Weld"})
      assert has_element?(view, "#images-edit-modal button[phx-value-id='#{source.id}']")
      assert view |> element("#images-edit-modal [data-typeahead-results]") |> render() =~ "Weld"

      refute view |> element("#images-edit-modal [data-typeahead-results]") |> render() =~
               "Weld elsewhere"

      view |> element("#images-edit-modal button[phx-value-id='#{source.id}']") |> render_click()
      view |> form("#images-edit-form", %{}) |> render_submit()

      saved = Images.get_image!(image.id)

      # The fixture's Source has no license link ("", stored on the image as nil).
      assert {saved.source_id, saved.license, saved.licenselink || "", saved.creator} ==
               {source.id, source.license, source.licenselink, source.author}
    end
  end

  describe "a taxon's Sources" do
    test "are searched among all Sources", %{conn: conn} do
      plant = plant_fixture()
      image = image!({:taxon, plant.id})
      source = source_fixture("Fernald", "1950")

      {:ok, view, _html} = mount_for(conn, {:taxon, plant.id})
      view |> element("[data-image-id='#{image.id}'] [data-action=edit]") |> render_click()
      view |> hook() |> render_hook("search_source", %{"value" => "Fernald"})

      assert has_element?(view, "#images-edit-modal button[phx-value-id='#{source.id}']")
    end
  end

  describe "copy metadata" do
    test "copies one image's metadata to the selected images", %{conn: conn} do
      gall = gall_fixture()

      from =
        image!({:gall, gall.id}, %{license: "CC-BY", creator: "Jane Doe", caption: "Shared"})

      to = image!({:gall, gall.id})
      untouched = image!({:gall, gall.id})

      {:ok, view, _html} = mount_for(conn, {:gall, gall.id})
      view |> element("#images button[phx-value-view=table]") |> render_click()

      view
      |> element("#images button[phx-click=start_copy][phx-value-id='#{from.id}']")
      |> render_click()

      view
      |> element("#images input[phx-click=toggle_copy_target][phx-value-id='#{to.id}']")
      |> render_click()

      view |> element("#images button[phx-click=confirm_copy]") |> render_click()
      view |> element("#images-copy-modal button[phx-click=execute_copy]") |> render_click()

      assert %{
               license: "CC-BY",
               creator: "Jane Doe",
               caption: "Shared",
               lastchangedby: "Test Admin"
             } =
               Images.get_image!(to.id)

      assert Images.get_image!(untouched.id).license == nil
      assert has_element?(view, "#images-flash-info", "Copied metadata to 1 image(s)")
    end
  end

  describe "delete" do
    test "deletes the image and refreshes the Gall's default", %{conn: conn} do
      gall = gall_fixture()
      first = image!({:gall, gall.id}, attributed())
      second = image!({:gall, gall.id}, attributed())
      {:ok, view, _html} = mount_for(conn, {:gall, gall.id})

      view |> element("[data-image-id='#{first.id}'] [data-action=delete]") |> render_click()
      view |> element("#images-delete-modal button[phx-click=delete_image]") |> render_click()

      assert Images.get_image(first.id) == nil
      refute has_element?(view, "[data-image-id='#{first.id}']")
      assert index_image_id(gall.id) == second.id
    end
  end

  describe "iNat import" do
    test "is offered for the owner", %{conn: conn} do
      gall = gall_fixture()
      {:ok, view, _html} = mount_for(conn, {:gall, gall.id})

      assert has_element?(view, "#images [data-role=inat-url-input]")
    end

    test "its completion refreshes the images", %{conn: conn} do
      gall = gall_fixture()
      {:ok, view, _html} = mount_for(conn, {:gall, gall.id})

      imported = image!({:gall, gall.id}, attributed())
      refute has_element?(view, "[data-image-id='#{imported.id}']")

      send(
        view.pid,
        {:send_update, InatImportComponent, [id: "images-inat", import_result: {:done, 1, []}]}
      )

      # This message, the iNat component's update, and its update of this
      # component.
      settle(view, 3)

      assert has_element?(view, "[data-image-id='#{imported.id}']")
      assert index_image_id(gall.id) == imported.id
    end
  end
end
