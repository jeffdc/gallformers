defmodule GallformersWeb.Admin.ImagesComponent do
  @moduledoc """
  Admin LiveComponent for one owner's images (`a856` Design 5): a Gall's or
  a taxon's (`t:Gallformers.Images.Image.owner/0`). Mounted on the Gall page
  and the taxon page; ported from the old species image screen.

    * a grid (drag to reorder, `SortableImages`; the first image is the
      default) or a table of the metadata;
    * presigned multi-upload straight to S3 (`ImageUpload`), appended to the
      owner's images;
    * metadata editing with the attribution rules
      (`Gallformers.Images.Attribution`): a save must leave the image
      attributed — a license, and a creator unless it is Public Domain / CC0
      or comes from a licensed Source. Picking a Source fills the license,
      its link and the creator; a license with a canonical, read-only link
      (`Gallformers.Licenses.url_readonly?/1`) gets that link. A Gall's
      Sources are its own (`Gallformers.Catalog.gall_sources/1`); a taxon,
      which has no Source list of its own, searches all Sources;
    * copying one image's metadata to selected images (table view);
    * delete (S3 variants first, `Gallformers.Images.delete_image/1`);
    * iNaturalist import (`GallformersWeb.Admin.InatImportComponent`);
    * a warning on each unattributed image.

  ## Usage

      <.live_component
        module={GallformersWeb.Admin.ImagesComponent}
        id="gall-images"
        owner={{:gall, @gall.id}}
        uploader={@actor.name}
        name={@gall.name}
      />

  `uploader` is the signed-in user's name, recorded as the uploader and
  last changer; `name` (optional) heads the full-size view.

  It reports through its own flash messages (a LiveComponent's flash reaches
  the page only on navigation) and sends the parent nothing. A change
  to a Gall's images has its row in the ID tool's table refreshed (it holds
  the default image, `Gallformers.Catalog.gall_images_changed/1`).
  """

  use GallformersWeb, :live_component

  require Logger

  alias Gallformers.Catalog
  alias Gallformers.Images
  alias Gallformers.Images.Attribution
  alias Gallformers.Images.Image
  alias Gallformers.Licenses
  alias Gallformers.Sources
  alias Gallformers.Storage.Images, as: ImageStorage
  alias Gallformers.TextMatch
  alias GallformersWeb.Admin.InatImportComponent

  @attribution_error "An image needs a license, and a creator unless it is Public Domain / CC0 or comes from a Source with a license."

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:owner, nil)
     |> assign(:images, [])
     |> assign(:images_version, 0)
     |> assign(:view_mode, :grid)
     # Copy mode: nil or %{source_id: id, selected_ids: MapSet.t()}
     |> assign(:copy_mode, nil)
     |> assign(:show_copy_confirm, false)
     |> assign(:viewing_image, nil)
     |> assign(:delete_image, nil)
     |> reset_edit()}
  end

  @impl true
  def update(%{inat_import_complete: _owner}, socket) do
    {:ok, socket |> reload() |> images_changed()}
  end

  def update(assigns, socket) do
    owner_changed? = socket.assigns.owner != assigns.owner

    socket =
      socket
      |> assign(:id, assigns.id)
      |> assign(:owner, assigns.owner)
      |> assign(:uploader, assigns.uploader)
      |> assign(:name, Map.get(assigns, :name) || "Image")

    {:ok, if(owner_changed?, do: reload(socket), else: socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="space-y-6">
      <%!-- A component's flash stays its own (LiveView copies it to the page only on navigation) --%>
      <.flash
        id={"#{@id}-flash-info"}
        kind={:info}
        flash={@flash}
        auto_dismiss={5000}
        phx-target={@myself}
      />
      <.flash id={"#{@id}-flash-error"} kind={:error} flash={@flash} phx-target={@myself} />

      <%!-- Image Grid --%>
      <div class="bg-white rounded-lg border border-gray-200 p-6">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-lg font-medium text-gray-900">
            Images ({length(@images)})
          </h2>
          <div class="flex items-center gap-4">
            <p :if={@images != [] && @view_mode == :grid} class="text-sm text-gray-500">
              Drag to reorder. First image is the default.
            </p>
            <%!-- View Toggle --%>
            <div class="flex border border-gray-300 rounded-md overflow-hidden">
              <button
                type="button"
                phx-click="toggle_view"
                phx-value-view="grid"
                phx-target={@myself}
                disabled={@copy_mode != nil}
                class={[
                  "px-3 py-1.5 text-sm",
                  @view_mode == :grid && "bg-gf-maroon text-white",
                  @view_mode != :grid && !@copy_mode && "bg-white text-gray-600 hover:bg-gray-50",
                  @copy_mode && @view_mode != :grid && "bg-gray-100 text-gray-400 cursor-not-allowed"
                ]}
                title="Grid view"
              >
                <.icon name="ph-squares-four" class="h-4 w-4" />
              </button>
              <button
                type="button"
                phx-click="toggle_view"
                phx-value-view="table"
                phx-target={@myself}
                disabled={@copy_mode != nil}
                class={[
                  "px-3 py-1.5 text-sm border-l border-gray-300",
                  @view_mode == :table && "bg-gf-maroon text-white",
                  @view_mode != :table && !@copy_mode && "bg-white text-gray-600 hover:bg-gray-50",
                  @copy_mode && @view_mode != :table &&
                    "bg-gray-100 text-gray-400 cursor-not-allowed"
                ]}
                title="Table view"
              >
                <.icon name="ph-list" class="h-4 w-4" />
              </button>
            </div>
          </div>
        </div>

        <div :if={@images == []} class="text-center py-8 text-gray-500">
          No images uploaded yet.
        </div>

        <%!-- Warning banner for unattributed images --%>
        <div
          :if={Enum.any?(@images, &unattributed?/1)}
          data-unattributed-warning
          class="mb-4 p-3 bg-orange-50 border border-orange-200 rounded-lg flex items-start gap-3"
        >
          <.icon name="ph-warning" class="h-5 w-5 text-orange-500 flex-shrink-0 mt-0.5" />
          <div class="text-sm text-orange-800">
            <p class="font-medium">Some images are not attributed</p>
            <p class="mt-1">
              Images marked with an orange border need a license, and a creator unless they are
              Public Domain / CC0 or come from a Source with a license. Hover over the image and
              click the edit button, or switch to the table view, to add this information.
            </p>
          </div>
        </div>

        <div :if={@images != []} id={"#{@id}-version-#{@images_version}"}>
          <%!-- Grid View --%>
          <div :if={@view_mode == :grid}>
            <div
              id={"#{@id}-sortable"}
              phx-hook="SortableImages"
              phx-target={@myself}
              class="flex flex-wrap gap-6"
            >
              <div
                :for={{image, index} <- Enum.with_index(@images)}
                data-image-id={image.id}
                class={[
                  "relative group cursor-move",
                  index == 0 && "ring-2 ring-gf-maroon ring-offset-2",
                  unattributed?(image) && "ring-2 ring-orange-400 ring-offset-2"
                ]}
              >
                <img
                  src={Image.sized_url(image.path, :original)}
                  alt={image.caption || "Image"}
                  class="w-48 h-48 object-cover rounded"
                />
                <div
                  :if={index == 0}
                  data-default-image
                  class="absolute top-2 left-2 bg-gf-maroon text-white text-sm px-2 py-1 rounded"
                >
                  Default
                </div>
                <%!-- Warning badge for unattributed images --%>
                <div
                  :if={unattributed?(image)}
                  data-unattributed
                  class="absolute top-2 right-2 bg-orange-500 text-white w-7 h-7 rounded-full flex items-center justify-center"
                  title="Not attributed"
                >
                  <.icon name="ph-warning" class="w-4 h-4" />
                </div>
                <%!-- Hover overlay with all actions --%>
                <div class="absolute inset-0 bg-black/50 opacity-0 group-hover:opacity-100 transition-opacity rounded flex items-center justify-center gap-4">
                  <button
                    type="button"
                    phx-click="view_image"
                    phx-value-id={image.id}
                    phx-target={@myself}
                    data-action="view"
                    class="p-2 bg-white rounded text-gray-700 hover:text-gf-maroon"
                    aria-label="View image"
                  >
                    <.icon name="ph-eye" class="h-6 w-6" />
                  </button>
                  <button
                    type="button"
                    phx-click="edit_image"
                    phx-value-id={image.id}
                    phx-target={@myself}
                    data-action="edit"
                    class="p-2 bg-white rounded text-gray-700 hover:text-gf-maroon"
                    aria-label="Edit image"
                  >
                    <.icon name="ph-pencil" class="h-6 w-6" />
                  </button>
                  <button
                    type="button"
                    phx-click="confirm_delete"
                    phx-value-id={image.id}
                    phx-target={@myself}
                    data-action="delete"
                    class="p-2 bg-white rounded text-gray-700 hover:text-red-600"
                    aria-label="Delete image"
                  >
                    <.icon name="ph-trash" class="h-6 w-6" />
                  </button>
                </div>
              </div>
            </div>
          </div>

          <%!-- Table View --%>
          <div
            :if={@view_mode == :table}
            class="overflow-x-auto"
            phx-window-keydown={@copy_mode && "cancel_copy"}
            phx-key={@copy_mode && "Escape"}
            phx-target={@myself}
          >
            <table class="min-w-full divide-y divide-gray-200">
              <thead class="bg-gray-50">
                <tr>
                  <th :if={@copy_mode} class="px-3 py-3 text-center w-[50px]">
                    <input
                      type="checkbox"
                      phx-click="select_all_targets"
                      phx-target={@myself}
                      checked={all_targets_selected?(@copy_mode, @images)}
                      class="rounded border-gray-300 text-gf-maroon focus:ring-gf-maroon"
                    />
                  </th>
                  <th class="px-3 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider w-[120px]">
                    Image
                  </th>
                  <th class="px-3 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider w-[60px]">
                    Def
                  </th>
                  <th class="px-3 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Creator
                  </th>
                  <th class="px-3 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    License
                  </th>
                  <th class="px-3 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Source
                  </th>
                  <th class="px-3 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Source Link
                  </th>
                  <th class="px-3 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    License Link
                  </th>
                  <th class="px-3 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Attribution
                  </th>
                  <th class="px-3 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Caption
                  </th>
                  <th class="px-3 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider w-[100px]">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="bg-white divide-y divide-gray-200">
                <tr
                  :for={{image, index} <- Enum.with_index(@images)}
                  data-image-id={image.id}
                  class={[
                    "hover:bg-gray-50",
                    unattributed?(image) && "bg-orange-50",
                    @copy_mode && image.id == @copy_mode.source_id && "bg-canary",
                    @copy_mode && MapSet.member?(@copy_mode.selected_ids, image.id) && "bg-blue-50"
                  ]}
                >
                  <%!-- Checkbox column (copy mode only) --%>
                  <td :if={@copy_mode} class="px-3 py-2 text-center">
                    <%= if image.id == @copy_mode.source_id do %>
                      <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-gf-maroon text-white">
                        SRC
                      </span>
                    <% else %>
                      <input
                        type="checkbox"
                        phx-click="toggle_copy_target"
                        phx-value-id={image.id}
                        phx-target={@myself}
                        checked={MapSet.member?(@copy_mode.selected_ids, image.id)}
                        class="rounded border-gray-300 text-gf-maroon focus:ring-gf-maroon"
                      />
                    <% end %>
                  </td>
                  <td class="px-3 py-2">
                    <div class="relative w-20">
                      <img
                        src={Image.sized_url(image.path, :small)}
                        onerror={"this.onerror=null; this.src='#{Image.sized_url(image.path, :original)}'"}
                        alt={image.caption || "Image"}
                        class="w-20 h-20 object-cover rounded"
                      />
                      <div
                        :if={unattributed?(image)}
                        data-unattributed
                        class="absolute top-1 right-1 bg-orange-500 text-white w-5 h-5 rounded-full flex items-center justify-center"
                        title="Not attributed"
                      >
                        <.icon name="ph-warning" class="w-3 h-3" />
                      </div>
                    </div>
                  </td>
                  <td class="px-3 py-2 text-center">
                    <span :if={index == 0} data-default-image class="text-gf-maroon">
                      <.icon name="ph-check-circle-fill" class="h-5 w-5" />
                    </span>
                  </td>
                  <td class="px-3 py-2 text-sm text-gray-900">
                    <%= if present?(image.creator) do %>
                      {image.creator}
                    <% else %>
                      <span class="text-gray-400">—</span>
                    <% end %>
                  </td>
                  <td class="px-3 py-2 text-sm text-gray-900">
                    <%= if present?(image.license) do %>
                      {image.license}
                    <% else %>
                      <span class="text-gray-400">—</span>
                    <% end %>
                  </td>
                  <td class="px-3 py-2 text-sm text-gray-900">
                    <%= if image.source do %>
                      <.link
                        navigate={~p"/source/#{image.source.id}"}
                        class="text-gf-maroon hover:underline"
                      >
                        {truncate(image.source.title, 30)}
                      </.link>
                    <% else %>
                      <span class="text-gray-400">—</span>
                    <% end %>
                  </td>
                  <td class="px-3 py-2 text-sm">
                    <%= if present?(image.sourcelink) do %>
                      <a
                        href={image.sourcelink}
                        target="_blank"
                        rel="noopener"
                        class="text-gf-maroon hover:underline"
                        title={image.sourcelink}
                      >
                        {URI.parse(image.sourcelink).host || String.slice(image.sourcelink, 0, 20)}
                      </a>
                    <% else %>
                      <span class="text-gray-400">—</span>
                    <% end %>
                  </td>
                  <td class="px-3 py-2 text-sm">
                    <%= if valid_url?(image.licenselink) do %>
                      <a
                        href={image.licenselink}
                        target="_blank"
                        rel="noopener"
                        class="text-gf-maroon hover:underline"
                        title={image.licenselink}
                      >
                        {URI.parse(image.licenselink).host || String.slice(image.licenselink, 0, 20)}
                      </a>
                    <% else %>
                      <span class="text-gray-400">—</span>
                    <% end %>
                  </td>
                  <td
                    class="px-3 py-2 text-sm text-gray-900 max-w-[150px] truncate"
                    title={image.attribution}
                  >
                    <%= if present?(image.attribution) do %>
                      {image.attribution}
                    <% else %>
                      <span class="text-gray-400">—</span>
                    <% end %>
                  </td>
                  <td
                    class="px-3 py-2 text-sm text-gray-900 max-w-[150px] truncate"
                    title={image.caption}
                  >
                    <%= if present?(image.caption) do %>
                      {image.caption}
                    <% else %>
                      <span class="text-gray-400">—</span>
                    <% end %>
                  </td>
                  <td class="px-3 py-2 text-right">
                    <%= if @copy_mode && image.id == @copy_mode.source_id do %>
                      <%!-- Source row: Apply/Cancel buttons --%>
                      <div class="flex justify-end gap-2">
                        <button
                          type="button"
                          phx-click="confirm_copy"
                          phx-target={@myself}
                          disabled={MapSet.size(@copy_mode.selected_ids) == 0}
                          class={[
                            "px-3 py-1 text-sm rounded",
                            MapSet.size(@copy_mode.selected_ids) > 0 &&
                              "bg-gf-maroon text-white hover:bg-gf-maroon/90",
                            MapSet.size(@copy_mode.selected_ids) == 0 &&
                              "bg-gray-200 text-gray-400 cursor-not-allowed"
                          ]}
                        >
                          Apply ({MapSet.size(@copy_mode.selected_ids)})
                        </button>
                        <button
                          type="button"
                          phx-click="cancel_copy"
                          phx-target={@myself}
                          class="px-3 py-1 text-sm rounded border border-gray-300 text-gray-600 hover:bg-gray-50"
                        >
                          Cancel
                        </button>
                      </div>
                    <% else %>
                      <%!-- Normal row actions (hidden during copy mode for non-source rows) --%>
                      <div :if={!@copy_mode} class="flex justify-end gap-2">
                        <button
                          type="button"
                          phx-click="start_copy"
                          phx-value-id={image.id}
                          phx-target={@myself}
                          class="p-1 text-gray-500 hover:text-gf-maroon"
                          title="Copy metadata from this image"
                        >
                          <.icon name="ph-copy" class="h-4 w-4" />
                        </button>
                        <button
                          type="button"
                          phx-click="edit_image"
                          phx-value-id={image.id}
                          phx-target={@myself}
                          data-action="edit"
                          class="p-1 text-gray-500 hover:text-gf-maroon"
                          title="Edit"
                        >
                          <.icon name="ph-pencil" class="h-4 w-4" />
                        </button>
                        <button
                          type="button"
                          phx-click="confirm_delete"
                          phx-value-id={image.id}
                          phx-target={@myself}
                          data-action="delete"
                          class="p-1 text-gray-500 hover:text-red-600"
                          title="Delete"
                        >
                          <.icon name="ph-trash" class="h-4 w-4" />
                        </button>
                      </div>
                    <% end %>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <%!-- Upload Section --%>
      <div class="bg-white rounded-lg border border-gray-200 p-6">
        <h2 class="text-lg font-medium text-gray-900 mb-4">Upload Images</h2>

        <div
          id={"#{@id}-uploader"}
          phx-hook="ImageUpload"
          phx-target={@myself}
          phx-update="ignore"
          data-max-files="20"
          data-accepted-types="image/jpeg,image/png,image/jpg"
        >
          <%!-- Dropzone --%>
          <div
            data-dropzone
            class="border-2 border-dashed border-gray-300 rounded-lg p-8 text-center cursor-pointer hover:border-gf-maroon transition-colors"
          >
            <.icon name="ph-cloud-arrow-up" class="h-12 w-12 mx-auto text-gray-400" />
            <p class="mt-2 text-sm text-gray-600">
              Drag and drop images here, or click to select
            </p>
            <p class="mt-1 text-xs text-gray-500">
              Max 20 files. JPG or PNG only.
            </p>
            <input data-file-input type="file" accept="image/jpeg,image/png" multiple class="hidden" />
          </div>

          <%!-- Preview Container --%>
          <div data-preview-container class="flex flex-wrap gap-4 mt-4"></div>

          <%!-- Progress Container --%>
          <div data-progress-container class="hidden mt-4"></div>

          <%!-- Upload Button --%>
          <div class="mt-4">
            <button
              data-upload-button
              type="button"
              disabled
              class="px-4 py-2 bg-gf-maroon text-white rounded-md hover:bg-gf-maroon/90 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              Upload Images
            </button>
          </div>
        </div>

        <%!-- iNat Import --%>
        <.live_component
          module={InatImportComponent}
          id={"#{@id}-inat"}
          owner={@owner}
          uploader={@uploader}
          notify={{__MODULE__, @id}}
        />
      </div>

      <%!-- Edit Modal --%>
      <.modal
        :if={@editing_image}
        id={"#{@id}-edit-modal"}
        show
        on_cancel={JS.push("cancel_edit", target: @myself)}
      >
        <:header>Edit Image Metadata</:header>
        <:body>
          <div class="flex gap-6 items-start">
            <%!-- Image Thumbnail (left column) --%>
            <div class="flex-shrink-0">
              <img
                src={Image.sized_url(@editing_image.path, :medium)}
                onerror={"this.onerror=null; this.src='#{Image.sized_url(@editing_image.path, :original)}'"}
                alt="Image being edited"
                class="w-[200px] rounded border border-gray-200"
              />
            </div>

            <%!-- Form Content (right column) --%>
            <div class="flex-1 space-y-4">
              <.error_message
                :if={@attribution_error}
                data-attribution-error
                title="Not attributed"
                message={@attribution_error}
              />

              <%!-- Source Typeahead (outside form to prevent conflicts) --%>
              <div id={"#{@id}-source-typeahead-wrapper-#{@editing_image.id}"} class="space-y-1">
                <div class="flex items-center gap-2">
                  <span class="text-sm font-medium text-gray-700">Source</span>
                  <.info_tip content={source_tip(@source_options)} />
                </div>
                <%= if @source_options == [] do %>
                  <p class="text-xs text-gray-500 mb-2">
                    This Gall has no Sources yet.
                  </p>
                  <div class="p-2 bg-gray-100 rounded border border-gray-200 text-gray-400 text-sm">
                    No sources available
                  </div>
                <% else %>
                  <p class="text-xs text-gray-500 mb-2">
                    If the image is from a publication, select the source here. This will auto-populate the license and creator fields.
                  </p>
                  <.typeahead
                    id={"#{@id}-source-picker-#{@editing_image.id}"}
                    label=""
                    placeholder="Search for a source..."
                    query={@source_query}
                    results={@source_results}
                    selected={@selected_source}
                    search_event="search_source"
                    select_event="select_source"
                    clear_event="clear_source"
                    display_fn={& &1.title}
                    target={@myself}
                  >
                    <:result :let={source}>
                      <div class="flex flex-col">
                        <span class="text-gray-900">{source.title}</span>
                        <span class="text-xs text-gray-500">
                          {source.author} ({source.pubyear})
                        </span>
                      </div>
                    </:result>
                  </.typeahead>
                <% end %>
              </div>

              <hr class="border-gray-200" />

              <form
                id={"#{@id}-edit-form"}
                phx-submit="save_image"
                phx-change="form_change"
                phx-target={@myself}
                class="space-y-4"
              >
                <%!-- Source Link --%>
                <div class="space-y-1">
                  <div class="flex items-center gap-2">
                    <span class="text-sm font-medium text-gray-700">
                      {if @selected_source,
                        do: "Direct Link to Image",
                        else: "Source URL (e.g., iNaturalist)"}
                    </span>
                    <.info_tip content="A URL that points to the image in the original publication or observation." />
                  </div>
                  <.input
                    type="text"
                    name="sourcelink"
                    label=""
                    value={@editing_image.sourcelink || ""}
                    placeholder={
                      if @selected_source,
                        do: "Link to image in publication",
                        else: "Link to observation"
                    }
                  />
                </div>

                <hr class="border-gray-200" />

                <p class="text-xs text-gray-500">
                  These fields should be filled out regardless of the source type. If you select a Source, the license info will be pre-populated.
                </p>

                <%!-- License --%>
                <div class="space-y-1">
                  <div class="flex items-center gap-2">
                    <span class="text-sm font-medium text-gray-700">
                      License<span class="text-red-600 ml-0.5">*</span>
                    </span>
                    <.info_tip content="The license for the image. We can only accept images with one of the licenses listed." />
                  </div>
                  <select
                    name="license"
                    class="gf-select"
                    phx-change="update_license"
                    phx-target={@myself}
                  >
                    <option value="">Select a license</option>
                    <option
                      :for={license <- Licenses.all()}
                      value={license}
                      selected={license == @editing_image.license}
                    >
                      {license}
                    </option>
                  </select>
                </div>

                <%!-- License Link --%>
                <div class="space-y-1">
                  <div class="flex items-center gap-2">
                    <span class="text-sm font-medium text-gray-700">License Link</span>
                    <.info_tip content="The link to the license. Mandatory if CC-BY is chosen." />
                  </div>
                  <.input
                    :if={Licenses.url_readonly?(@editing_image.license)}
                    type="text"
                    name="licenselink"
                    label=""
                    value={Licenses.url(@editing_image.license)}
                    readonly
                    class="gf-input bg-gray-50 text-gray-500 cursor-not-allowed"
                  />
                  <div :if={not Licenses.url_readonly?(@editing_image.license)}>
                    <.input
                      type="text"
                      name="licenselink"
                      label=""
                      value={@editing_image.licenselink || Licenses.url(@editing_image.license) || ""}
                      placeholder={
                        if @editing_image.license == "All Rights Reserved",
                          do: "Optional - link to usage terms",
                          else: ""
                      }
                    />
                    <p
                      :if={@editing_image.license == "Public Domain / CC0"}
                      class="mt-1 text-xs text-gray-500"
                    >
                      Defaults to CC0, but can be changed for other public domain references
                    </p>
                  </div>
                </div>

                <%!-- Creator --%>
                <div class="space-y-1">
                  <div class="flex items-center gap-2">
                    <span class="text-sm font-medium text-gray-700">
                      Creator / Photographer<span
                        :if={@editing_image.license != "Public Domain / CC0"}
                        class="text-red-600 ml-0.5"
                      >*</span>
                    </span>
                    <.info_tip content="Who created the image. Usually a link to the individual or their name. Please no emails! Not needed for Public Domain / CC0 or an image from a Source with a license." />
                  </div>
                  <.input type="text" name="creator" label="" value={@editing_image.creator || ""} />
                </div>

                <%!-- Attribution Notes --%>
                <div class="space-y-1">
                  <div class="flex items-center gap-2">
                    <span class="text-sm font-medium text-gray-700">Attribution Notes</span>
                    <.info_tip content="Any additional attribution information." />
                  </div>
                  <.input
                    type="textarea"
                    name="attribution"
                    label=""
                    rows="2"
                    value={@editing_image.attribution || ""}
                  />
                </div>

                <%!-- Caption --%>
                <div class="space-y-1">
                  <div class="flex items-center gap-2">
                    <span class="text-sm font-medium text-gray-700">Caption</span>
                    <.info_tip content="An optional caption to be displayed with the image." />
                  </div>
                  <.input
                    type="textarea"
                    name="caption"
                    label=""
                    rows="2"
                    value={@editing_image.caption || ""}
                  />
                </div>
              </form>

              <hr class="border-gray-200" />

              <%!-- Uploader / Last Changed --%>
              <div class="flex justify-between text-sm text-gray-500">
                <span>Uploader: {@editing_image.uploader || "Unknown"}</span>
                <span>Last Changed: {@editing_image.lastchangedby || "Unknown"}</span>
              </div>
            </div>
          </div>
        </:body>
        <:footer>
          <.button type="button" variant="secondary" phx-click="cancel_edit" phx-target={@myself}>
            {if @form_dirty, do: "Discard Changes", else: "Cancel"}
          </.button>
          <.button
            type="submit"
            variant="primary"
            form={"#{@id}-edit-form"}
            disabled={not @form_dirty}
          >
            Save Changes
          </.button>
        </:footer>
      </.modal>

      <%!-- Delete Confirmation Modal --%>
      <.modal
        :if={@delete_image}
        id={"#{@id}-delete-modal"}
        show
        on_cancel={JS.push("cancel_delete", target: @myself)}
        class="gf-modal-md"
      >
        <:header>Delete Image</:header>
        <:body>
          <p class="text-gray-600 mb-4">
            Are you sure you want to delete this image? This action cannot be undone.
          </p>
          <div class="flex justify-center mb-4">
            <img
              src={Image.sized_url(@delete_image.path, :medium)}
              onerror={"this.onerror=null; this.src='#{Image.sized_url(@delete_image.path, :original)}'"}
              alt="Image to delete"
              class="max-w-xs rounded"
            />
          </div>
        </:body>
        <:footer>
          <.button type="button" variant="secondary" phx-click="cancel_delete" phx-target={@myself}>
            Cancel
          </.button>
          <.button
            type="button"
            variant="danger"
            phx-click="delete_image"
            phx-value-id={@delete_image.id}
            phx-target={@myself}
          >
            Delete
          </.button>
        </:footer>
      </.modal>

      <%!-- View Image Modal --%>
      <.modal
        :if={@viewing_image}
        id={"#{@id}-view-modal"}
        show
        on_cancel={JS.push("cancel_view", target: @myself)}
        class="max-w-7xl"
      >
        <:header>{@name}</:header>
        <:body>
          <div class="flex justify-center">
            <img
              src={Image.sized_url(@viewing_image.path, :original)}
              alt={@viewing_image.caption || "Image"}
              class="max-h-[90vh] w-auto object-contain"
            />
          </div>
        </:body>
      </.modal>

      <%!-- Copy Confirmation Modal --%>
      <.modal
        :if={@show_copy_confirm && @copy_mode}
        id={"#{@id}-copy-modal"}
        show
        on_cancel={JS.push("cancel_copy_confirm", target: @myself)}
      >
        <:header>Copy Image Metadata</:header>
        <:body>
          <div class="space-y-4">
            <p class="text-gray-600">
              Copy metadata from:
            </p>
            <% source_image = Enum.find(@images, &(&1.id == @copy_mode.source_id)) %>
            <div class="flex items-center gap-4 p-3 bg-gray-50 rounded-lg">
              <img
                :if={source_image}
                src={Image.sized_url(source_image.path, :small)}
                onerror={"this.onerror=null; this.src='#{Image.sized_url(source_image.path, :original)}'"}
                alt="Source image"
                class="w-16 h-16 object-cover rounded"
              />
              <div :if={source_image} class="text-sm">
                <p><strong>Creator:</strong> {source_image.creator || "—"}</p>
                <p><strong>License:</strong> {source_image.license || "—"}</p>
              </div>
            </div>
            <p class="text-gray-600">
              To <strong>{MapSet.size(@copy_mode.selected_ids)}</strong> selected image(s)?
            </p>
            <div class="text-sm text-gray-500 bg-gray-50 p-3 rounded">
              <p class="font-medium mb-1">Fields to be copied:</p>
              <p>Creator, License, License Link, Source Link, Attribution, Caption, Source</p>
            </div>
            <div
              :if={source_image && unattributed?(source_image)}
              class="p-3 bg-orange-50 border border-orange-200 rounded-lg flex items-start gap-3"
            >
              <.icon name="ph-warning" class="h-5 w-5 text-orange-500 flex-shrink-0 mt-0.5" />
              <p class="text-sm text-orange-800">
                The source image is not attributed. Its empty values will overwrite the target images' data.
              </p>
            </div>
          </div>
        </:body>
        <:footer>
          <.button
            type="button"
            variant="secondary"
            phx-click="cancel_copy_confirm"
            phx-target={@myself}
          >
            Cancel
          </.button>
          <.button type="button" variant="primary" phx-click="execute_copy" phx-target={@myself}>
            Copy Metadata
          </.button>
        </:footer>
      </.modal>
    </div>
    """
  end

  # -- view mode and copy mode ---------------------------------------------------

  @impl true
  def handle_event("toggle_view", %{"view" => view}, socket) do
    # Don't allow view toggle during copy mode
    if socket.assigns.copy_mode do
      {:noreply, socket}
    else
      {:noreply, assign(socket, :view_mode, if(view == "table", do: :table, else: :grid))}
    end
  end

  def handle_event("start_copy", %{"id" => id}, socket) do
    case owned_image(socket, id) do
      nil ->
        {:noreply, socket}

      image ->
        {:noreply, assign(socket, :copy_mode, %{source_id: image.id, selected_ids: MapSet.new()})}
    end
  end

  def handle_event("cancel_copy", _params, socket) do
    {:noreply, assign(socket, copy_mode: nil, show_copy_confirm: false)}
  end

  def handle_event("toggle_copy_target", %{"id" => id}, socket) do
    %{copy_mode: copy_mode} = socket.assigns

    case owned_image(socket, id) do
      %Image{id: image_id} when image_id != copy_mode.source_id ->
        selected_ids =
          if MapSet.member?(copy_mode.selected_ids, image_id),
            do: MapSet.delete(copy_mode.selected_ids, image_id),
            else: MapSet.put(copy_mode.selected_ids, image_id)

        {:noreply, assign(socket, :copy_mode, %{copy_mode | selected_ids: selected_ids})}

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("select_all_targets", _params, socket) do
    copy_mode = socket.assigns.copy_mode
    all_target_ids = target_ids(copy_mode, socket.assigns.images)

    # Toggle: if all selected, deselect all; otherwise select all
    selected_ids =
      if MapSet.equal?(copy_mode.selected_ids, all_target_ids),
        do: MapSet.new(),
        else: all_target_ids

    {:noreply, assign(socket, :copy_mode, %{copy_mode | selected_ids: selected_ids})}
  end

  def handle_event("confirm_copy", _params, socket) do
    {:noreply, assign(socket, :show_copy_confirm, true)}
  end

  def handle_event("cancel_copy_confirm", _params, socket) do
    {:noreply, assign(socket, :show_copy_confirm, false)}
  end

  def handle_event("execute_copy", _params, socket) do
    %{copy_mode: copy_mode, uploader: uploader} = socket.assigns
    target_ids = MapSet.to_list(copy_mode.selected_ids)

    case Images.copy_metadata(copy_mode.source_id, target_ids, uploader) do
      {:ok, count} ->
        {:noreply,
         socket
         |> reload()
         |> assign(copy_mode: nil, show_copy_confirm: false)
         |> put_flash(:info, "Copied metadata to #{count} image(s)")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to copy metadata: #{inspect(reason)}")}
    end
  end

  # -- upload and order (the ImageUpload and SortableImages hooks) ---------------

  def handle_event("request_presigned_urls", %{"files" => files}, socket) do
    owner = socket.assigns.owner

    urls =
      files
      |> Enum.map(fn file ->
        path = ImageStorage.generate_path(owner, file["extension"])

        case ImageStorage.presigned_upload_url(path, file["type"]) do
          {:ok, presigned_url} ->
            %{path: path, presigned_url: presigned_url, content_type: file["type"]}

          {:error, reason} ->
            Logger.error(
              "Failed to generate presigned URL for #{file["name"]}: #{inspect(reason)}"
            )

            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:noreply, push_event(socket, "presigned_urls", %{urls: urls})}
  end

  # The hook also sends the old screen's `species_id`, ignored: the owner is
  # this component's.
  def handle_event("uploads_completed", %{"paths" => paths}, socket) do
    %{owner: owner, uploader: uploader} = socket.assigns

    {created, failed} =
      paths
      |> Enum.map(&Images.finalize_upload(&1, owner, uploader))
      |> Enum.split_with(&match?({:ok, _image}, &1))

    Enum.each(failed, fn {:error, changeset} ->
      Logger.error("Failed to record an uploaded image: #{inspect(changeset.errors)}")
    end)

    socket =
      socket
      |> reload()
      |> update(:images_version, &(&1 + 1))
      |> images_changed()
      |> push_event("upload_complete", %{
        message: "#{length(created)} image(s) uploaded successfully"
      })

    socket =
      if failed == [],
        do: socket,
        else: put_flash(socket, :error, "#{length(failed)} uploaded image(s) could not be saved")

    {:noreply, socket}
  end

  def handle_event("refresh_images", _params, socket) do
    {:noreply, reload(socket)}
  end

  def handle_event("reorder_images", %{"order" => order}, socket) do
    case Images.reorder_images(socket.assigns.owner, Enum.map(order, &to_id/1)) do
      :ok ->
        {:noreply,
         socket
         |> reload()
         |> update(:images_version, &(&1 + 1))
         |> images_changed()
         |> put_flash(:info, "Image order saved")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save image order")}
    end
  end

  # -- view ------------------------------------------------------------------------

  def handle_event("view_image", %{"id" => id}, socket) do
    {:noreply, assign(socket, :viewing_image, owned_image(socket, id))}
  end

  def handle_event("cancel_view", _params, socket) do
    {:noreply, assign(socket, :viewing_image, nil)}
  end

  # -- edit ------------------------------------------------------------------------

  def handle_event("edit_image", %{"id" => id}, socket) do
    case owned_image(socket, id) do
      nil ->
        {:noreply, socket}

      %Image{id: image_id} ->
        image = Images.get_image!(image_id)

        {:noreply,
         socket
         |> reset_edit()
         |> assign(:editing_image, image)
         |> assign(:original_image, image)
         |> assign(:source_options, source_options(socket.assigns.owner))
         |> assign(:selected_source, image.source)}
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, reset_edit(socket)}
  end

  def handle_event("update_license", %{"license" => license}, socket) do
    # The license's canonical link replaces the link (a starting point where it
    # is not read-only).
    {:noreply,
     put_editing(socket, %{
       socket.assigns.editing_image
       | license: license,
         licenselink: Licenses.url(license)
     })}
  end

  def handle_event("search_source", %{"value" => query}, socket) do
    results = search_sources(socket.assigns.source_options, query)
    {:noreply, assign(socket, source_query: query, source_results: results)}
  end

  def handle_event("select_source", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.source_results, &(&1.id == to_id(id))) do
      nil ->
        {:noreply, socket}

      source ->
        # Picking a Source fills the license, its link and the creator.
        image = %{
          socket.assigns.editing_image
          | source_id: source.id,
            license: source.license,
            licenselink: source.licenselink,
            creator: source.author
        }

        {:noreply,
         socket
         |> assign(selected_source: source, source_query: "", source_results: [])
         |> put_editing(image)}
    end
  end

  def handle_event("clear_source", _params, socket) do
    {:noreply,
     socket
     |> assign(selected_source: nil, source_query: "", source_results: [])
     |> put_editing(%{socket.assigns.editing_image | source_id: nil})}
  end

  # Tracks form field changes for the dirty state.
  def handle_event("form_change", params, socket) do
    {:noreply, put_editing(socket, put_form_fields(socket.assigns.editing_image, params))}
  end

  def handle_event("save_image", params, socket) do
    %{editing_image: editing, selected_source: source} = socket.assigns
    edited = put_form_fields(editing, params)

    # A save must leave the image attributed.
    if Attribution.image_attributed?(%{edited | source: source}) do
      save_image(socket, edited)
    else
      {:noreply,
       socket
       |> assign(:editing_image, edited)
       |> assign(:attribution_error, @attribution_error)}
    end
  end

  # -- delete ------------------------------------------------------------------------

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :delete_image, owned_image(socket, id))}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :delete_image, nil)}
  end

  def handle_event("delete_image", %{"id" => id}, socket) do
    with %Image{id: image_id} <- owned_image(socket, id),
         %Image{} = image <- Images.get_image(image_id),
         {:ok, _deleted} <- Images.delete_image(image) do
      {:noreply,
       socket
       |> reload()
       |> update(:images_version, &(&1 + 1))
       |> assign(:delete_image, nil)
       |> images_changed()
       |> put_flash(:info, "Image deleted successfully")}
    else
      nil ->
        {:noreply, assign(socket, :delete_image, nil)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete image: #{inspect(reason)}")}
    end
  end

  # -- helpers -------------------------------------------------------------------------

  defp save_image(socket, edited) do
    license = edited.license

    licenselink =
      if Licenses.url_readonly?(license), do: Licenses.url(license), else: edited.licenselink

    attrs = %{
      creator: edited.creator,
      attribution: edited.attribution,
      sourcelink: edited.sourcelink,
      caption: edited.caption,
      license: license,
      licenselink: licenselink,
      source_id: edited.source_id,
      lastchangedby: socket.assigns.uploader
    }

    # The stored image, not the edited copy (Ecto would see no changes).
    case Images.update_image(Images.get_image!(edited.id), attrs) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> reload()
         |> update(:images_version, &(&1 + 1))
         |> reset_edit()
         |> put_flash(:info, "Image updated successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update image")}
    end
  end

  defp reload(socket), do: assign(socket, :images, Images.list_images(socket.assigns.owner))

  # A Gall's default image is in the ID tool's table.
  defp images_changed(%{assigns: %{owner: {:gall, gall_id}}} = socket) do
    :ok = Catalog.gall_images_changed(gall_id)
    socket
  end

  defp images_changed(socket), do: socket

  defp reset_edit(socket) do
    assign(socket,
      editing_image: nil,
      original_image: nil,
      source_options: [],
      source_query: "",
      source_results: [],
      selected_source: nil,
      form_dirty: false,
      attribution_error: nil
    )
  end

  defp put_editing(socket, image) do
    socket
    |> assign(:editing_image, image)
    |> assign(:form_dirty, image_changed?(image, socket.assigns.original_image))
  end

  defp put_form_fields(image, params) do
    %{
      image
      | creator: params["creator"],
        attribution: params["attribution"],
        sourcelink: params["sourcelink"],
        caption: params["caption"],
        licenselink: params["licenselink"]
    }
  end

  # An image of this owner (the list shown), by an ID from the page.
  defp owned_image(socket, id) do
    image_id = to_id(id)
    Enum.find(socket.assigns.images, &(&1.id == image_id))
  end

  defp to_id(id) when is_integer(id), do: id
  defp to_id(id) when is_binary(id), do: String.to_integer(id)

  # The Sources an image may name: a Gall's own Sources, or `:all` (searched)
  # for a taxon, which has no Source list of its own.
  defp source_options({:gall, gall_id}), do: Catalog.gall_sources(gall_id)
  defp source_options({:taxon, _taxon_id}), do: :all

  defp search_sources(:all, query) do
    if String.length(String.trim(query)) >= 2,
      do: query |> Sources.search_sources() |> Enum.take(10),
      else: []
  end

  defp search_sources(sources, query) do
    if String.length(query) >= 1 do
      sources
      |> Enum.filter(&TextMatch.matches_all_terms?(query, "#{&1.title} #{&1.author}"))
      |> Enum.take(10)
    else
      []
    end
  end

  defp source_tip(:all),
    do: "The source that the image came from, searched among all Sources."

  defp source_tip(_gall_sources),
    do:
      "The source that the image came from: one of this Gall's Sources (its citations, its Gallformers notes and the Sources of its Facts)."

  defp unattributed?(image), do: not Attribution.image_attributed?(image)

  defp present?(value), do: value not in [nil, ""]

  defp truncate(nil, _length), do: ""

  defp truncate(text, length) do
    if String.length(text) > length, do: String.slice(text, 0, length) <> "...", else: text
  end

  # Whether the image has been modified from its original state.
  defp image_changed?(_current, nil), do: false

  defp image_changed?(current, original) do
    Enum.any?(
      [:creator, :attribution, :license, :licenselink, :sourcelink, :caption, :source_id],
      &(Map.get(current, &1) != Map.get(original, &1))
    )
  end

  defp target_ids(copy_mode, images) do
    images
    |> Enum.reject(&(&1.id == copy_mode.source_id))
    |> MapSet.new(& &1.id)
  end

  defp all_targets_selected?(nil, _images), do: false

  defp all_targets_selected?(copy_mode, images) do
    targets = target_ids(copy_mode, images)
    MapSet.equal?(copy_mode.selected_ids, targets) && MapSet.size(targets) > 0
  end
end
