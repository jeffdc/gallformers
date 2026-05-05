defmodule GallformersWeb.Admin.ContentImageManager do
  @moduledoc """
  Shared LiveComponent for managing content images (articles and keys).

  Provides image grid, upload via presigned URLs, metadata editing,
  drag-drop reordering, and delete with confirmation.

  ## Usage

      <.live_component
        module={GallformersWeb.Admin.ContentImageManager}
        id="article-images"
        owner_type={:article}
        owner_id={@article.id}
        current_user={@current_user}
      />

  ## Parent Messages

  Sends the following messages to the parent LiveView via `send/2`:
  - `{:image_uploaded, %ContentImage{}}` — after successful upload
  - `{:image_deleted, image_id}` — after successful delete
  - `{:images_reordered, ordered_ids}` — after reorder
  """

  use GallformersWeb, :live_component

  alias Gallformers.Accounts
  alias Gallformers.ContentImages
  alias Gallformers.Images.Attribution
  alias Gallformers.Licenses
  alias Gallformers.Storage.Images, as: ImageStorage

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:images, [])
     |> assign(:editing_image, nil)
     |> assign(:original_image, nil)
     |> assign(:form_dirty, false)
     |> assign(:deleting_image, nil)
     |> assign(:show_edit_modal, false)
     |> assign(:show_delete_modal, false)}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(:owner_type, assigns.owner_type)
      |> assign(:owner_id, assigns.owner_id)
      |> assign(:current_user, assigns.current_user)
      |> assign(:id, assigns.id)

    images = load_images(assigns.owner_type, assigns.owner_id)
    socket = assign(socket, :images, images)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} data-content-image-manager class="space-y-4">
      <%!-- Image Grid --%>
      <div
        :if={@images != []}
        id={"#{@id}-grid"}
        phx-hook="SortableImages"
        phx-target={@myself}
        class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3"
      >
        <div
          :for={image <- @images}
          data-image-id={image.id}
          class={[
            "relative group rounded-lg border overflow-hidden",
            if(Attribution.image_attributed?(image),
              do: "border-gray-200",
              else: "border-amber-400 ring-1 ring-amber-400"
            )
          ]}
        >
          <img
            src={ImageStorage.public_url(image.path)}
            alt={image.caption || "Content image"}
            class="w-full h-24 object-cover"
            loading="lazy"
          />

          <%!-- Attribution warning badge --%>
          <div
            :if={not Attribution.image_attributed?(image)}
            data-attribution-warning
            class="absolute top-1 left-1 bg-amber-500 text-white text-xs px-1.5 py-0.5 rounded-full"
          >
            !
          </div>

          <%!-- Hover actions --%>
          <div class="absolute inset-0 bg-black/50 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center gap-2">
            <button
              type="button"
              phx-click="edit_image"
              phx-value-id={image.id}
              phx-target={@myself}
              data-action="edit"
              class="p-1.5 bg-white rounded-full text-gray-700 hover:text-gf-maroon"
              title="Edit metadata"
            >
              <.icon name="ph-pencil-simple" class="w-4 h-4" />
            </button>
            <button
              type="button"
              phx-click="confirm_delete"
              phx-value-id={image.id}
              phx-target={@myself}
              data-action="delete"
              class="p-1.5 bg-white rounded-full text-gray-700 hover:text-red-600"
              title="Delete"
            >
              <.icon name="ph-trash" class="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>

      <%!-- Empty State --%>
      <div :if={@images == []} class="text-center py-6 text-gray-500 text-sm">
        No images yet. Upload images below.
      </div>

      <%!-- Upload Area --%>
      <div
        id={"#{@id}-uploader"}
        phx-hook="ContentImageUpload"
        phx-target={@myself}
        phx-update="ignore"
        data-owner-type={@owner_type}
        data-owner-id={@owner_id}
        data-max-files="10"
        data-accepted-types="image/jpeg,image/png,image/jpg"
      >
        <div
          data-dropzone
          class="border-2 border-dashed border-gray-300 rounded-lg p-6 text-center cursor-pointer hover:border-gf-maroon hover:bg-gf-sky-blue/10 transition-colors"
        >
          <.icon name="ph-upload-simple" class="w-8 h-8 mx-auto text-gray-400 mb-2" />
          <p class="text-sm text-gray-600">
            Drop images here or <span class="text-gf-maroon font-medium">click to browse</span>
          </p>
          <p class="text-xs text-gray-400 mt-1">JPG or PNG, up to 10 files</p>
          <input data-file-input type="file" multiple hidden accept="image/jpeg,image/png" />
        </div>

        <div data-preview-container class="flex flex-wrap gap-3 mt-3"></div>
        <div data-progress-container class="hidden mt-3"></div>

        <button
          data-upload-button
          type="button"
          disabled
          class="mt-3 px-4 py-2 bg-gf-maroon text-white rounded-lg text-sm font-medium disabled:opacity-50 disabled:cursor-not-allowed hover:bg-gf-maroon/90"
        >
          Upload Images
        </button>
      </div>

      <%!-- Edit Modal --%>
      <.modal
        :if={@show_edit_modal && @editing_image}
        id="content-image-edit-modal"
        show
        on_cancel={JS.push("close_edit", target: @myself)}
      >
        <:header>Edit Image Metadata</:header>
        <:body>
          <div class="flex gap-4">
            <img
              src={ImageStorage.public_url(@editing_image.path)}
              alt="Editing"
              class="w-32 h-32 object-cover rounded"
            />
            <form
              id="content-image-edit-form"
              phx-submit="save_image"
              phx-change="form_change"
              phx-target={@myself}
              class="flex-1 space-y-3"
            >
              <.input
                type="select"
                name="license"
                label="License"
                value={@editing_image.license}
                options={[{"Select license...", ""} | Licenses.options()]}
              />
              <.input
                type="text"
                name="creator"
                label="Creator / Photographer"
                value={@editing_image.creator}
              />
              <.input
                type="text"
                name="licenselink"
                label="License URL"
                value={@editing_image.licenselink}
              />
              <.input
                type="text"
                name="sourcelink"
                label="Source Link"
                value={@editing_image.sourcelink}
              />
              <.input
                type="textarea"
                name="attribution"
                label="Attribution Notes"
                value={@editing_image.attribution}
              />
              <.input
                type="textarea"
                name="caption"
                label="Caption"
                value={@editing_image.caption}
              />
              <div class="flex justify-end gap-2 pt-2">
                <.button
                  type="button"
                  phx-click="close_edit"
                  phx-target={@myself}
                  variant="secondary"
                >
                  Cancel
                </.button>
                <.button type="submit" variant="primary" disabled={not @form_dirty}>
                  Save
                </.button>
              </div>
            </form>
          </div>
        </:body>
      </.modal>

      <%!-- Delete Confirmation Modal --%>
      <.modal
        :if={@show_delete_modal && @deleting_image}
        id="content-image-delete-modal"
        show
        on_cancel={JS.push("close_delete", target: @myself)}
      >
        <:header>Delete Image</:header>
        <:body>
          <div class="space-y-4">
            <img
              src={ImageStorage.public_url(@deleting_image.path)}
              alt="Deleting"
              class="w-32 h-32 object-cover rounded mx-auto"
            />
            <p class="text-sm text-gray-600 text-center">
              This will permanently delete this image. This cannot be undone.
            </p>
            <div class="flex justify-end gap-2">
              <.button
                type="button"
                phx-click="close_delete"
                phx-target={@myself}
                variant="secondary"
              >
                Cancel
              </.button>
              <.button
                type="button"
                id="confirm-delete-content-image"
                phx-click="delete_image"
                phx-target={@myself}
                variant="danger"
              >
                Delete
              </.button>
            </div>
          </div>
        </:body>
      </.modal>
    </div>
    """
  end

  # =============================================================================
  # Event Handlers
  # =============================================================================

  @impl true
  def handle_event("request_presigned_urls", %{"files" => files}, socket) do
    owner_type = socket.assigns.owner_type
    owner_id = socket.assigns.owner_id
    has_variants = owner_type == :key

    urls =
      Enum.map(files, fn file ->
        path =
          ImageStorage.generate_content_image_path(
            prefix_for(owner_type),
            owner_id,
            file["extension"],
            has_variants: has_variants
          )

        case ImageStorage.presigned_upload_url(path, file["type"]) do
          {:ok, presigned_url} ->
            %{path: path, presigned_url: presigned_url, content_type: file["type"]}

          {:error, _reason} ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:noreply, push_event(socket, "presigned_urls", %{urls: urls})}
  end

  def handle_event("uploads_completed", %{"paths" => paths}, socket) do
    owner_type = socket.assigns.owner_type
    owner_id = socket.assigns.owner_id
    uploader = Accounts.current_user_display_name(socket.assigns.current_user)

    images =
      Enum.map(paths, fn path ->
        case ContentImages.finalize_upload(path, owner_type, owner_id, uploader) do
          {:ok, image} ->
            send(self(), {:image_uploaded, image})
            image

          {:error, _reason} ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    socket =
      socket
      |> assign(:images, load_images(owner_type, owner_id))
      |> push_event("upload_complete", %{
        message: "#{length(images)} image(s) uploaded successfully"
      })

    {:noreply, socket}
  end

  def handle_event("refresh_images", _params, socket) do
    images = load_images(socket.assigns.owner_type, socket.assigns.owner_id)
    {:noreply, assign(socket, :images, images)}
  end

  def handle_event("edit_image", %{"id" => id}, socket) do
    image = ContentImages.get_image!(String.to_integer(id))

    {:noreply,
     socket
     |> assign(:editing_image, image)
     |> assign(:original_image, image)
     |> assign(:form_dirty, false)
     |> assign(:show_edit_modal, true)}
  end

  def handle_event("form_change", params, socket) do
    changed = metadata_changed?(params, socket.assigns.original_image)
    {:noreply, assign(socket, :form_dirty, changed)}
  end

  def handle_event("save_image", params, socket) do
    image = socket.assigns.editing_image
    uploader = Accounts.current_user_display_name(socket.assigns.current_user)

    attrs = %{
      creator: params["creator"],
      license: params["license"],
      licenselink: params["licenselink"],
      sourcelink: params["sourcelink"],
      attribution: params["attribution"],
      caption: params["caption"],
      lastchangedby: uploader
    }

    case ContentImages.update_image(image, attrs) do
      {:ok, _updated} ->
        images = load_images(socket.assigns.owner_type, socket.assigns.owner_id)

        {:noreply,
         socket
         |> assign(:images, images)
         |> assign(:show_edit_modal, false)
         |> assign(:editing_image, nil)}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  def handle_event("close_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_edit_modal, false)
     |> assign(:editing_image, nil)}
  end

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    image = ContentImages.get_image!(String.to_integer(id))

    {:noreply,
     socket
     |> assign(:deleting_image, image)
     |> assign(:show_delete_modal, true)}
  end

  def handle_event("delete_image", _params, socket) do
    image = socket.assigns.deleting_image

    case ContentImages.delete_image(image) do
      {:ok, _} ->
        send(self(), {:image_deleted, image.id})
        images = load_images(socket.assigns.owner_type, socket.assigns.owner_id)

        {:noreply,
         socket
         |> assign(:images, images)
         |> assign(:show_delete_modal, false)
         |> assign(:deleting_image, nil)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  def handle_event("close_delete", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_delete_modal, false)
     |> assign(:deleting_image, nil)}
  end

  def handle_event("reorder_images", %{"order" => order}, socket) do
    owner_type = socket.assigns.owner_type
    owner_id = socket.assigns.owner_id

    case ContentImages.reorder_images(owner_type, owner_id, order) do
      :ok ->
        send(self(), {:images_reordered, order})
        images = load_images(owner_type, owner_id)
        {:noreply, assign(socket, :images, images)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp load_images(:article, owner_id), do: ContentImages.list_images_for_article(owner_id)
  defp load_images(:key, owner_id), do: ContentImages.list_images_for_key(owner_id)

  defp prefix_for(:article), do: "articles"
  defp prefix_for(:key), do: "keys"

  @metadata_fields ~w(creator license licenselink sourcelink attribution caption)

  defp metadata_changed?(params, original) do
    Enum.any?(@metadata_fields, fn field ->
      params[field] != (Map.get(original, String.to_existing_atom(field)) || "")
    end)
  end
end
