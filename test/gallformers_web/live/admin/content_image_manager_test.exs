defmodule GallformersWeb.Admin.ContentImageManagerTest do
  @moduledoc """
  Tests for the ContentImageManager LiveComponent.
  Uses live_isolated with a test wrapper LiveView.
  """
  use GallformersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Gallformers.ContentImages

  # Test wrapper LiveView that hosts the component
  defmodule TestLive do
    use Phoenix.LiveView

    def mount(_params, session, socket) do
      {:ok,
       assign(socket,
         owner_type: session["owner_type"],
         owner_id: session["owner_id"],
         messages: []
       )}
    end

    def render(assigns) do
      ~H"""
      <div>
        <.live_component
          module={GallformersWeb.Admin.ContentImageManager}
          id="test-content-images"
          owner_type={@owner_type}
          owner_id={@owner_id}
          current_user={%{display_name: "tester"}}
        />
        <div id="messages">{inspect(@messages)}</div>
      </div>
      """
    end

    def handle_info({:image_uploaded, image}, socket) do
      {:noreply, update(socket, :messages, &[{:uploaded, image.id} | &1])}
    end

    def handle_info({:image_deleted, id}, socket) do
      {:noreply, update(socket, :messages, &[{:deleted, id} | &1])}
    end

    def handle_info(_msg, socket), do: {:noreply, socket}
  end

  setup do
    {:ok, article} =
      Gallformers.Articles.create_article(%{
        title: "Image Test Article",
        content: "Content",
        author: "tester"
      })

    {:ok, key} =
      Gallformers.Keys.create_key(%{
        title: "Image Test Key",
        slug: "image-test-key",
        version: "1.0",
        couplets: %{"1" => %{"lead" => "test"}}
      })

    %{article: article, key: key}
  end

  describe "rendering for article owner" do
    test "shows upload dropzone", %{conn: conn, article: article} do
      {:ok, view, html} =
        live_isolated(conn, TestLive,
          session: %{"owner_type" => :article, "owner_id" => article.id}
        )

      assert html =~ "data-content-image-manager"
      assert html =~ "data-dropzone"
      assert has_element?(view, "[data-content-image-manager]")
    end

    test "shows empty state when no images", %{conn: conn, article: article} do
      {:ok, _view, html} =
        live_isolated(conn, TestLive,
          session: %{"owner_type" => :article, "owner_id" => article.id}
        )

      assert html =~ "No images"
    end

    test "shows image grid when images exist", %{conn: conn, article: article} do
      {:ok, _img} =
        ContentImages.finalize_upload(
          "articles/#{article.id}/test.jpg",
          :article,
          article.id,
          "tester",
          %{creator: "Jane Doe", license: "CC-BY"}
        )

      {:ok, view, _html} =
        live_isolated(conn, TestLive,
          session: %{"owner_type" => :article, "owner_id" => article.id}
        )

      assert has_element?(view, "[data-image-id]")
    end

    test "shows attribution warning for unattributed image", %{conn: conn, article: article} do
      {:ok, _img} =
        ContentImages.finalize_upload(
          "articles/#{article.id}/noattr.jpg",
          :article,
          article.id,
          "tester"
        )

      {:ok, view, _html} =
        live_isolated(conn, TestLive,
          session: %{"owner_type" => :article, "owner_id" => article.id}
        )

      assert has_element?(view, "[data-attribution-warning]")
    end

    test "no attribution warning for properly attributed image", %{conn: conn, article: article} do
      {:ok, _img} =
        ContentImages.finalize_upload(
          "articles/#{article.id}/attr.jpg",
          :article,
          article.id,
          "tester",
          %{creator: "Jane", license: "CC-BY"}
        )

      {:ok, view, _html} =
        live_isolated(conn, TestLive,
          session: %{"owner_type" => :article, "owner_id" => article.id}
        )

      refute has_element?(view, "[data-attribution-warning]")
    end
  end

  describe "rendering for key owner" do
    test "shows upload dropzone", %{conn: conn, key: key} do
      {:ok, _view, html} =
        live_isolated(conn, TestLive, session: %{"owner_type" => :key, "owner_id" => key.id})

      assert html =~ "data-content-image-manager"
    end
  end

  describe "edit metadata" do
    test "opens edit modal", %{conn: conn, article: article} do
      {:ok, img} =
        ContentImages.finalize_upload(
          "articles/#{article.id}/edit.jpg",
          :article,
          article.id,
          "tester"
        )

      {:ok, view, _html} =
        live_isolated(conn, TestLive,
          session: %{"owner_type" => :article, "owner_id" => article.id}
        )

      # Click edit
      view
      |> element("[data-image-id='#{img.id}'] [data-action='edit']")
      |> render_click()

      assert has_element?(view, "#content-image-edit-modal")
    end

    test "saves metadata changes", %{conn: conn, article: article} do
      {:ok, img} =
        ContentImages.finalize_upload(
          "articles/#{article.id}/save.jpg",
          :article,
          article.id,
          "tester"
        )

      {:ok, view, _html} =
        live_isolated(conn, TestLive,
          session: %{"owner_type" => :article, "owner_id" => article.id}
        )

      # Open edit
      view
      |> element("[data-image-id='#{img.id}'] [data-action='edit']")
      |> render_click()

      # Submit metadata
      view
      |> form("#content-image-edit-form", %{
        "creator" => "Updated Creator",
        "license" => "CC-BY-SA"
      })
      |> render_submit()

      # Verify in DB
      updated = ContentImages.get_image!(img.id)
      assert updated.creator == "Updated Creator"
      assert updated.license == "CC-BY-SA"
    end
  end

  # The ContentImageUpload and SortableImages hooks push these events to their
  # own elements, so they reach this component rather than the parent LiveView.
  describe "hook events sent to the component" do
    test "uploads_completed from the uploader saves the images and notifies parent", %{
      conn: conn,
      article: article
    } do
      {:ok, view, _html} =
        live_isolated(conn, TestLive,
          session: %{"owner_type" => :article, "owner_id" => article.id}
        )

      path = "articles/#{article.id}/hook-upload.jpg"

      view
      |> element("#test-content-images-uploader")
      |> render_hook("uploads_completed", %{"paths" => [path]})

      assert [%{id: id, path: ^path}] = ContentImages.list_images_for_article(article.id)
      assert_push_event(view, "upload_complete", %{message: "1 image(s) uploaded successfully"})
      assert has_element?(view, "[data-image-id='#{id}']")
      assert render(view) =~ "uploaded"
    end

    test "reorder_images from the grid saves the new order", %{conn: conn, article: article} do
      {:ok, first} =
        ContentImages.finalize_upload("articles/#{article.id}/1.jpg", :article, article.id, "t")

      {:ok, second} =
        ContentImages.finalize_upload("articles/#{article.id}/2.jpg", :article, article.id, "t")

      {:ok, view, _html} =
        live_isolated(conn, TestLive,
          session: %{"owner_type" => :article, "owner_id" => article.id}
        )

      view
      |> element("#test-content-images-grid")
      |> render_hook("reorder_images", %{"order" => [second.id, first.id]})

      assert Enum.map(ContentImages.list_images_for_article(article.id), & &1.id) ==
               [second.id, first.id]
    end
  end

  describe "delete" do
    test "deletes image and notifies parent", %{conn: conn, article: article} do
      {:ok, img} =
        ContentImages.finalize_upload(
          "articles/#{article.id}/delete.jpg",
          :article,
          article.id,
          "tester"
        )

      {:ok, view, _html} =
        live_isolated(conn, TestLive,
          session: %{"owner_type" => :article, "owner_id" => article.id}
        )

      # Click delete
      view
      |> element("[data-image-id='#{img.id}'] [data-action='delete']")
      |> render_click()

      # Confirm delete
      view
      |> element("#confirm-delete-content-image")
      |> render_click()

      # Image should be gone
      assert ContentImages.get_image(img.id) == nil

      # Parent should have received notification
      assert render(view) =~ "deleted"
    end
  end
end
