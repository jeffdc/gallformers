defmodule GallformersWeb.Admin.ImagesLive do
  @moduledoc """
  Admin LiveView for managing species images.

  Features:
  - Species search and selection
  - Image upload with drag-drop and progress
  - Image grid with reordering
  - Image metadata editing
  - Image deletion with confirmation
  """

  use GallformersWeb, :live_view

  require Logger

  alias Gallformers.Images
  alias Gallformers.Images.Image
  alias Gallformers.Licenses
  alias Gallformers.Search.TextMatch
  alias Gallformers.Sources
  alias Gallformers.Storage

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]
    db_display_name = Gallformers.Accounts.db_display_name(session)

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:db_display_name, db_display_name)
      |> assign(:page_title, "Image Management")
      |> assign(:search_query, "")
      |> assign(:search_results, [])
      |> assign(:selected_species, nil)
      |> assign(:images, [])
      |> assign(:images_version, 0)
      |> assign(:editing_image, nil)
      |> assign(:original_image, nil)
      |> assign(:delete_image, nil)
      |> assign(:viewing_image, nil)
      # Source typeahead state
      |> assign(:source_options, [])
      |> assign(:source_query, "")
      |> assign(:source_results, [])
      |> assign(:selected_source, nil)
      # Dirty state tracking
      |> assign(:form_dirty, false)
      # View mode: :grid (default) or :table
      |> assign(:view_mode, :grid)
      # Copy mode state: nil or %{source_id: id, selected_ids: MapSet.t()}
      |> assign(:copy_mode, nil)
      |> assign(:show_copy_confirm, false)

    {:ok, socket}
  end

  # License options removed - directly in template now

  @impl true
  def handle_params(params, _uri, socket) do
    case Map.get(params, "species_id") do
      nil ->
        {:noreply, socket}

      species_id ->
        species_id = String.to_integer(species_id)
        images = Images.list_images_for_species(species_id)

        # Get species name and taxoncode
        {species_name, taxoncode} =
          case Gallformers.Species.get_species(species_id) do
            nil -> {"Unknown Species", "gall"}
            s -> {s.name, s.taxoncode}
          end

        socket =
          socket
          |> assign(:selected_species, %{id: species_id, name: species_name, taxoncode: taxoncode})
          |> assign(:images, images)
          |> assign(:images_version, 0)

        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin
      flash={@flash}
      current_user={@current_user}
      page_title="Image Management"
    >
      <div class="space-y-6">
        <%!-- Species Search --%>
        <div class="bg-white rounded-lg border border-gray-200 p-6">
          <h2 class="text-lg font-medium text-gray-900 mb-4">Select Species</h2>
          <.typeahead
            id="species-picker"
            label=""
            placeholder="Search for a species..."
            query={@search_query}
            results={@search_results}
            selected={@selected_species}
            search_event="search_species"
            select_event="select_species"
            clear_event="clear_species"
            display_fn={& &1.name}
          >
            <:result :let={species}>
              <div class="flex justify-between items-center w-full">
                <.taxon_name name={species.name} class="text-gray-900" />
                <span class="text-sm text-gray-500">{species.image_count} images</span>
              </div>
            </:result>
          </.typeahead>
        </div>

        <%!-- Image Management Section --%>
        <div :if={@selected_species} class="space-y-6">
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
                    disabled={@copy_mode != nil}
                    class={[
                      "px-3 py-1.5 text-sm",
                      @view_mode == :grid && "bg-gf-maroon text-white",
                      @view_mode != :grid && !@copy_mode && "bg-white text-gray-600 hover:bg-gray-50",
                      @copy_mode && @view_mode != :grid &&
                        "bg-gray-100 text-gray-400 cursor-not-allowed"
                    ]}
                    title="Grid view"
                  >
                    <.icon name="ph-squares-four" class="h-4 w-4" />
                  </button>
                  <button
                    type="button"
                    phx-click="toggle_view"
                    phx-value-view="table"
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

            <div
              :if={@images == []}
              class="text-center py-8 text-gray-500"
            >
              No images uploaded yet.
            </div>

            <%!-- Warning banner for incomplete images --%>
            <div
              :if={@images != [] && Enum.any?(@images, &image_incomplete?/1)}
              class="mb-4 p-3 bg-orange-50 border border-orange-200 rounded-lg flex items-start gap-3"
            >
              <.icon name="ph-warning" class="h-5 w-5 text-orange-500 flex-shrink-0 mt-0.5" />
              <div class="text-sm text-orange-800">
                <p class="font-medium">Some images need attention</p>
                <p class="mt-1">
                  Images marked with an orange border are missing required metadata (creator or license).
                  Hover over the image and click the edit button to add this information or switch to then
                  table view above and to the right to edit the metadata.
                </p>
              </div>
            </div>

            <div :if={@images != []} id={"images-version-#{@images_version}"}>
              <%!-- Grid View --%>
              <div :if={@view_mode == :grid}>
                <div
                  id="sortable-images"
                  phx-hook="SortableImages"
                  class="flex flex-wrap gap-6"
                >
                  <div
                    :for={image <- @images}
                    data-image-id={image.id}
                    class={[
                      "relative group cursor-move",
                      image.sort_order == 0 && "ring-2 ring-gf-maroon ring-offset-2",
                      image_incomplete?(image) && "ring-2 ring-orange-400 ring-offset-2"
                    ]}
                  >
                    <img
                      src={Image.sized_url(image.path, :original)}
                      alt={image.caption || "Species image"}
                      class="w-48 h-48 object-cover rounded"
                    />
                    <div
                      :if={image.sort_order == 0}
                      class="absolute top-2 left-2 bg-gf-maroon text-white text-sm px-2 py-1 rounded"
                    >
                      Default
                    </div>
                    <%!-- Warning badge for incomplete images --%>
                    <div
                      :if={image_incomplete?(image)}
                      class="absolute top-2 right-2 bg-orange-500 text-white w-7 h-7 rounded-full flex items-center justify-center"
                      title="Missing required metadata"
                    >
                      <.icon name="ph-warning" class="w-4 h-4" />
                    </div>
                    <%!-- Hover overlay with all actions --%>
                    <div class="absolute inset-0 bg-black/50 opacity-0 group-hover:opacity-100 transition-opacity rounded flex items-center justify-center gap-4">
                      <button
                        type="button"
                        phx-click="view_image"
                        phx-value-id={image.id}
                        class="p-2 bg-white rounded text-gray-700 hover:text-gf-maroon"
                        aria-label="View image"
                      >
                        <.icon name="ph-eye" class="h-6 w-6" />
                      </button>
                      <button
                        type="button"
                        phx-click="edit_image"
                        phx-value-id={image.id}
                        class="p-2 bg-white rounded text-gray-700 hover:text-gf-maroon"
                        aria-label="Edit image"
                      >
                        <.icon name="ph-pencil" class="h-6 w-6" />
                      </button>
                      <button
                        type="button"
                        phx-click="confirm_delete"
                        phx-value-id={image.id}
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
              >
                <table class="min-w-full divide-y divide-gray-200">
                  <thead class="bg-gray-50">
                    <tr>
                      <th :if={@copy_mode} class="px-3 py-3 text-center w-[50px]">
                        <input
                          type="checkbox"
                          phx-click="select_all_targets"
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
                      :for={image <- @images}
                      class={[
                        "hover:bg-gray-50",
                        @copy_mode && image.id == @copy_mode.source_id && "bg-canary",
                        @copy_mode && MapSet.member?(@copy_mode.selected_ids, image.id) &&
                          "bg-blue-50"
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
                            checked={MapSet.member?(@copy_mode.selected_ids, image.id)}
                            class="rounded border-gray-300 text-gf-maroon focus:ring-gf-maroon"
                          />
                        <% end %>
                      </td>
                      <td class="px-3 py-2">
                        <img
                          src={Image.sized_url(image.path, :small)}
                          onerror={"this.onerror=null; this.src='#{Image.sized_url(image.path, :original)}'"}
                          alt={image.caption || "Species image"}
                          class="w-20 h-20 object-cover rounded"
                        />
                      </td>
                      <td class="px-3 py-2 text-center">
                        <span :if={image.sort_order == 0} class="text-gf-maroon">
                          <.icon name="ph-check-circle-fill" class="h-5 w-5" />
                        </span>
                      </td>
                      <td class="px-3 py-2 text-sm text-gray-900">
                        <%= if image.creator && image.creator != "" do %>
                          {image.creator}
                        <% else %>
                          <span class="text-gray-400">—</span>
                        <% end %>
                      </td>
                      <td class="px-3 py-2 text-sm text-gray-900">
                        <%= if image.license && image.license != "" do %>
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
                            {String.slice(image.source.title || "", 0, 30)}{if String.length(
                                                                                 image.source.title ||
                                                                                   ""
                                                                               ) > 30, do: "..."}
                          </.link>
                        <% else %>
                          <span class="text-gray-400">—</span>
                        <% end %>
                      </td>
                      <td class="px-3 py-2 text-sm">
                        <%= if image.sourcelink && image.sourcelink != "" do %>
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
                            {URI.parse(image.licenselink).host ||
                              String.slice(image.licenselink, 0, 20)}
                          </a>
                        <% else %>
                          <span class="text-gray-400">—</span>
                        <% end %>
                      </td>
                      <td
                        class="px-3 py-2 text-sm text-gray-900 max-w-[150px] truncate"
                        title={image.attribution}
                      >
                        <%= if image.attribution && image.attribution != "" do %>
                          {image.attribution}
                        <% else %>
                          <span class="text-gray-400">—</span>
                        <% end %>
                      </td>
                      <td
                        class="px-3 py-2 text-sm text-gray-900 max-w-[150px] truncate"
                        title={image.caption}
                      >
                        <%= if image.caption && image.caption != "" do %>
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
                              class="p-1 text-gray-500 hover:text-gf-maroon"
                              title="Copy metadata from this image"
                            >
                              <.icon name="ph-copy" class="h-4 w-4" />
                            </button>
                            <button
                              type="button"
                              phx-click="edit_image"
                              phx-value-id={image.id}
                              class="p-1 text-gray-500 hover:text-gf-maroon"
                              title="Edit"
                            >
                              <.icon name="ph-pencil" class="h-4 w-4" />
                            </button>
                            <button
                              type="button"
                              phx-click="confirm_delete"
                              phx-value-id={image.id}
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
              id="image-uploader"
              phx-hook="ImageUpload"
              phx-update="ignore"
              data-species-id={@selected_species.id}
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
                <input
                  data-file-input
                  type="file"
                  accept="image/jpeg,image/png"
                  multiple
                  class="hidden"
                />
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
              module={GallformersWeb.Admin.InatImportComponent}
              id="inat-import"
              species_id={@selected_species.id}
              uploader={@db_display_name}
            />
          </div>
        </div>

        <%!-- Edit Modal --%>
        <.modal
          :if={@editing_image}
          id="edit-modal"
          show
          on_cancel={JS.push("cancel_edit")}
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
                <%!-- Source Typeahead (outside form to prevent conflicts) --%>
                <div id={"source-typeahead-wrapper-#{@editing_image.id}"} class="space-y-1">
                  <div class="flex items-center gap-2">
                    <span class="text-sm font-medium text-gray-700">Source</span>
                    <.info_tip content="The source that the image came from. This list will only show Sources that have already been mapped to the species." />
                  </div>
                  <%= if @source_options == [] do %>
                    <p class="text-xs text-gray-500 mb-2">
                      No sources are mapped to this species yet. To use source auto-fill, <.link
                        navigate={~p"/admin/species-sources/add?species_id=#{@selected_species.id}"}
                        class="text-gf-maroon hover:underline"
                      >
                      map a source to this species first
                    </.link>.
                    </p>
                    <div class="p-2 bg-gray-100 rounded border border-gray-200 text-gray-400 text-sm">
                      No sources available
                    </div>
                  <% else %>
                    <p class="text-xs text-gray-500 mb-2">
                      If the image is from a publication, select the source here. This will auto-populate the license and creator fields.
                    </p>
                    <.typeahead
                      id={"source-picker-#{@editing_image.id}"}
                      label=""
                      placeholder="Search for a source..."
                      query={@source_query}
                      results={@source_results}
                      selected={@selected_source}
                      search_event="search_source"
                      select_event="select_source"
                      clear_event="clear_source"
                      display_fn={& &1.title}
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
                  id="edit-image-form"
                  phx-submit="save_image"
                  phx-change="form_change"
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
                      <.info_tip content="The license for the image. Currently we can only accept images with one of the 3 licenses that are listed as options." />
                    </div>
                    <select name="license" class="gf-select" phx-change="update_license">
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
                        value={
                          @editing_image.licenselink || Licenses.url(@editing_image.license) || ""
                        }
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
                        Creator / Photographer<span class="text-red-600 ml-0.5">*</span>
                      </span>
                      <.info_tip content="Who created the image. Usually a link to the individual or their name. Please no emails!" />
                    </div>
                    <.input
                      type="text"
                      name="creator"
                      label=""
                      value={@editing_image.creator || ""}
                    />
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
            <.button type="button" variant="secondary" phx-click="cancel_edit">
              {if @form_dirty, do: "Discard Changes", else: "Cancel"}
            </.button>
            <.button type="submit" variant="primary" form="edit-image-form" disabled={not @form_dirty}>
              Save Changes
            </.button>
          </:footer>
        </.modal>

        <%!-- Delete Confirmation Modal --%>
        <.modal
          :if={@delete_image}
          id="delete-modal"
          show
          on_cancel={JS.push("cancel_delete")}
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
            <.button type="button" variant="secondary" phx-click="cancel_delete">
              Cancel
            </.button>
            <.button
              type="button"
              variant="danger"
              phx-click="delete_image"
              phx-value-id={@delete_image.id}
            >
              Delete
            </.button>
          </:footer>
        </.modal>

        <%!-- View Image Modal --%>
        <.modal
          :if={@viewing_image}
          id="view-modal"
          show
          on_cancel={JS.push("cancel_view")}
          class="max-w-7xl"
        >
          <:header>{@selected_species.name}</:header>
          <:body>
            <div class="flex justify-center">
              <img
                src={Image.sized_url(@viewing_image.path, :original)}
                alt={@viewing_image.caption || "Species image"}
                class="max-h-[90vh] w-auto object-contain"
              />
            </div>
          </:body>
        </.modal>

        <%!-- Copy Confirmation Modal --%>
        <.modal
          :if={@show_copy_confirm && @copy_mode}
          id="copy-confirm-modal"
          show
          on_cancel={JS.push("cancel_copy_confirm")}
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
              <%= if source_image && image_incomplete?(source_image) do %>
                <div class="p-3 bg-orange-50 border border-orange-200 rounded-lg flex items-start gap-3">
                  <.icon name="ph-warning" class="h-5 w-5 text-orange-500 flex-shrink-0 mt-0.5" />
                  <p class="text-sm text-orange-800">
                    Source image is missing some metadata. Empty values will overwrite existing data in target images.
                  </p>
                </div>
              <% end %>
            </div>
          </:body>
          <:footer>
            <.button type="button" variant="secondary" phx-click="cancel_copy_confirm">
              Cancel
            </.button>
            <.button type="button" variant="primary" phx-click="execute_copy">
              Copy Metadata
            </.button>
          </:footer>
        </.modal>
      </div>
    </Layouts.admin>
    """
  end

  @impl true
  def handle_event("search_species", %{"value" => query}, socket) do
    search_results =
      if String.length(query) >= 2 do
        Images.search_species(query)
      else
        []
      end

    {:noreply, assign(socket, search_query: query, search_results: search_results)}
  end

  @impl true
  def handle_event("select_species", %{"id" => id}, socket) do
    species_id = String.to_integer(id)

    # Get the species name and taxoncode from search results
    species_result = Enum.find(socket.assigns.search_results, &(&1.id == species_id))
    name = if species_result, do: species_result.name, else: "Unknown"
    taxoncode = if species_result, do: species_result.taxoncode, else: "gall"

    images = Images.list_images_for_species(species_id)

    socket =
      socket
      |> assign(:selected_species, %{id: species_id, name: name, taxoncode: taxoncode})
      |> assign(:images, images)
      |> assign(:images_version, 0)
      |> assign(:search_results, [])
      |> assign(:search_query, "")
      |> push_patch(to: ~p"/admin/images?species_id=#{species_id}")

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_species", _params, socket) do
    socket =
      socket
      |> assign(:selected_species, nil)
      |> assign(:images, [])
      |> assign(:images_version, 0)
      |> push_patch(to: ~p"/admin/images")

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_view", %{"view" => view}, socket) do
    # Don't allow view toggle during copy mode
    if socket.assigns.copy_mode do
      {:noreply, socket}
    else
      view_mode = if view == "table", do: :table, else: :grid
      {:noreply, assign(socket, :view_mode, view_mode)}
    end
  end

  @impl true
  def handle_event("start_copy", %{"id" => id}, socket) do
    source_id = String.to_integer(id)
    copy_mode = %{source_id: source_id, selected_ids: MapSet.new()}
    {:noreply, assign(socket, :copy_mode, copy_mode)}
  end

  @impl true
  def handle_event("cancel_copy", _params, socket) do
    {:noreply, assign(socket, :copy_mode, nil)}
  end

  @impl true
  def handle_event("toggle_copy_target", %{"id" => id}, socket) do
    image_id = String.to_integer(id)
    copy_mode = socket.assigns.copy_mode

    selected_ids =
      if MapSet.member?(copy_mode.selected_ids, image_id) do
        MapSet.delete(copy_mode.selected_ids, image_id)
      else
        MapSet.put(copy_mode.selected_ids, image_id)
      end

    {:noreply, assign(socket, :copy_mode, %{copy_mode | selected_ids: selected_ids})}
  end

  @impl true
  def handle_event("select_all_targets", _params, socket) do
    copy_mode = socket.assigns.copy_mode

    all_target_ids =
      socket.assigns.images
      |> Enum.reject(&(&1.id == copy_mode.source_id))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    # Toggle: if all selected, deselect all; otherwise select all
    selected_ids =
      if MapSet.equal?(copy_mode.selected_ids, all_target_ids) do
        MapSet.new()
      else
        all_target_ids
      end

    {:noreply, assign(socket, :copy_mode, %{copy_mode | selected_ids: selected_ids})}
  end

  @impl true
  def handle_event("confirm_copy", _params, socket) do
    # Show confirmation modal by setting a flag
    {:noreply, assign(socket, :show_copy_confirm, true)}
  end

  @impl true
  def handle_event("cancel_copy_confirm", _params, socket) do
    {:noreply, assign(socket, :show_copy_confirm, false)}
  end

  @impl true
  def handle_event("execute_copy", _params, socket) do
    copy_mode = socket.assigns.copy_mode
    target_ids = MapSet.to_list(copy_mode.selected_ids)

    updated_by = socket.assigns.db_display_name

    case Images.copy_metadata(copy_mode.source_id, target_ids, updated_by) do
      {:ok, count} ->
        images = Images.list_images_for_species(socket.assigns.selected_species.id)

        socket =
          socket
          |> assign(:images, images)
          |> assign(:copy_mode, nil)
          |> assign(:show_copy_confirm, false)
          |> put_flash(:info, "Copied metadata to #{count} image(s)")

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to copy metadata: #{inspect(reason)}")}
    end
  end

  # Handle presigned URL requests from JS hook
  @impl true
  def handle_event("request_presigned_urls", %{"files" => files}, socket) do
    species_id = socket.assigns.selected_species.id

    urls =
      Enum.map(files, fn file ->
        path = Storage.generate_path(species_id, file["extension"])

        case Storage.presigned_upload_url(path, file["type"]) do
          {:ok, presigned_url} ->
            %{
              path: path,
              presigned_url: presigned_url,
              content_type: file["type"]
            }

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

  # Handle upload completion from JS hook
  @impl true
  def handle_event("uploads_completed", %{"paths" => paths, "species_id" => species_id}, socket) do
    species_id = if is_binary(species_id), do: String.to_integer(species_id), else: species_id

    uploader = socket.assigns.db_display_name

    # Create image records and schedule variant generation
    Enum.each(paths, fn path ->
      Images.finalize_upload(path, species_id, uploader)
    end)

    # Reload images
    images = Images.list_images_for_species(species_id)

    socket =
      socket
      |> assign(:images, images)
      |> update(:images_version, &(&1 + 1))
      |> push_event("upload_complete", %{
        message: "#{length(paths)} image(s) uploaded successfully"
      })

    {:noreply, socket}
  end

  @impl true
  def handle_event("refresh_images", _params, socket) do
    case socket.assigns.selected_species do
      nil ->
        {:noreply, socket}

      species ->
        images = Images.list_images_for_species(species.id)
        {:noreply, assign(socket, :images, images)}
    end
  end

  @impl true
  def handle_event("reorder_images", %{"order" => order}, socket) do
    species_id = socket.assigns.selected_species.id

    case Images.reorder_images(species_id, order) do
      :ok ->
        images = Images.list_images_for_species(species_id)

        socket =
          socket
          |> assign(:images, images)
          |> update(:images_version, &(&1 + 1))
          |> put_flash(:info, "Image order saved")

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to save image order")}
    end
  end

  @impl true
  def handle_event("edit_image", %{"id" => id}, socket) do
    image = Images.get_image!(String.to_integer(id))
    species_id = socket.assigns.selected_species.id

    # Fetch sources mapped to this species for the typeahead
    source_options = Sources.get_sources_for_species(species_id)

    # Find if image already has a source selected
    selected_source =
      if image.source_id do
        Enum.find(source_options, &(&1.id == image.source_id))
      end

    socket =
      socket
      |> assign(:editing_image, image)
      |> assign(:original_image, image)
      |> assign(:source_options, source_options)
      |> assign(:source_query, "")
      |> assign(:source_results, [])
      |> assign(:selected_source, selected_source)
      |> assign(:form_dirty, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    socket =
      socket
      |> assign(:editing_image, nil)
      |> assign(:original_image, nil)
      |> assign(:source_options, [])
      |> assign(:source_query, "")
      |> assign(:source_results, [])
      |> assign(:selected_source, nil)
      |> assign(:form_dirty, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("view_image", %{"id" => id}, socket) do
    image = Images.get_image!(String.to_integer(id))
    {:noreply, assign(socket, :viewing_image, image)}
  end

  @impl true
  def handle_event("cancel_view", _params, socket) do
    {:noreply, assign(socket, :viewing_image, nil)}
  end

  @impl true
  def handle_event("update_license", %{"license" => license}, socket) do
    # Update both license and licenselink to reflect the new selection
    # For CC licenses, use the canonical URL; for others, use the canonical URL as a starting point
    updated_image = %{
      socket.assigns.editing_image
      | license: license,
        licenselink: Licenses.url(license)
    }

    socket =
      socket
      |> assign(:editing_image, updated_image)
      |> assign(:form_dirty, image_changed?(updated_image, socket.assigns.original_image))

    {:noreply, socket}
  end

  # Source typeahead event handlers
  @impl true
  def handle_event("search_source", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 1 do
        socket.assigns.source_options
        |> Enum.filter(fn source ->
          title = source.title || ""
          author = source.author || ""

          TextMatch.matches_all_terms?(query, "#{title} #{author}")
        end)
        |> Enum.take(10)
      else
        []
      end

    {:noreply, assign(socket, source_query: query, source_results: results)}
  end

  @impl true
  def handle_event("select_source", %{"id" => id}, socket) do
    source_id = String.to_integer(id)
    source = Enum.find(socket.assigns.source_options, &(&1.id == source_id))

    if source do
      # Auto-populate fields from source
      updated_image = %{
        socket.assigns.editing_image
        | source_id: source.id,
          license: source.license,
          licenselink: source.licenselink,
          creator: source.author
      }

      socket =
        socket
        |> assign(:editing_image, updated_image)
        |> assign(:selected_source, source)
        |> assign(:source_query, "")
        |> assign(:source_results, [])
        |> assign(:form_dirty, image_changed?(updated_image, socket.assigns.original_image))

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_source", _params, socket) do
    updated_image = %{socket.assigns.editing_image | source_id: nil}

    socket =
      socket
      |> assign(:editing_image, updated_image)
      |> assign(:selected_source, nil)
      |> assign(:source_query, "")
      |> assign(:source_results, [])
      |> assign(:form_dirty, image_changed?(updated_image, socket.assigns.original_image))

    {:noreply, socket}
  end

  # Track form field changes for dirty state
  @impl true
  def handle_event("form_change", params, socket) do
    updated_image = %{
      socket.assigns.editing_image
      | creator: params["creator"],
        attribution: params["attribution"],
        sourcelink: params["sourcelink"],
        caption: params["caption"],
        licenselink: params["licenselink"]
    }

    socket =
      socket
      |> assign(:editing_image, updated_image)
      |> assign(:form_dirty, image_changed?(updated_image, socket.assigns.original_image))

    {:noreply, socket}
  end

  @impl true
  def handle_event("save_image", params, socket) do
    editing_image = socket.assigns.editing_image

    # Re-fetch from database to get persisted state (editing_image may have been
    # modified in-memory by update_license, which would cause Ecto to see no changes)
    image = Images.get_image!(editing_image.id)

    lastchangedby = socket.assigns.db_display_name

    # Use license from assigns (kept in sync by update_license handler) rather than
    # form params, as LiveView select elements can have issues with form submission
    license = editing_image.license

    licenselink =
      if Licenses.url_readonly?(license), do: Licenses.url(license), else: params["licenselink"]

    attrs =
      params
      |> Map.put("license", license)
      |> Map.put("lastchangedby", lastchangedby)
      |> Map.put("licenselink", licenselink)
      |> Map.put("source_id", editing_image.source_id)

    case Images.update_image(image, attrs) do
      {:ok, _updated} ->
        images = Images.list_images_for_species(socket.assigns.selected_species.id)

        socket =
          socket
          |> assign(:images, images)
          |> update(:images_version, &(&1 + 1))
          |> assign(:editing_image, nil)
          |> assign(:original_image, nil)
          |> assign(:source_options, [])
          |> assign(:source_query, "")
          |> assign(:source_results, [])
          |> assign(:selected_source, nil)
          |> assign(:form_dirty, false)
          |> put_flash(:info, "Image updated successfully")

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update image")}
    end
  end

  @impl true
  def handle_event("confirm_delete", %{"id" => id}, socket) do
    image = Images.get_image!(String.to_integer(id))
    {:noreply, assign(socket, :delete_image, image)}
  end

  @impl true
  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :delete_image, nil)}
  end

  @impl true
  def handle_event("delete_image", %{"id" => id}, socket) do
    image = Images.get_image!(String.to_integer(id))

    case Images.delete_image(image) do
      {:ok, _} ->
        images = Images.list_images_for_species(socket.assigns.selected_species.id)

        socket =
          socket
          |> assign(:images, images)
          |> update(:images_version, &(&1 + 1))
          |> assign(:delete_image, nil)
          |> put_flash(:info, "Image deleted successfully")

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete image: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:inat_import_complete, species_id}, socket) do
    images = Images.list_images_for_species(species_id)

    {:noreply,
     socket
     |> assign(:images, images)
     |> update(:images_version, &(&1 + 1))}
  end

  # Helper to check if an image is missing required metadata
  defp image_incomplete?(image) do
    is_nil(image.creator) or image.creator == "" or
      is_nil(image.license) or image.license == ""
  end

  # Helper to check if the image has been modified from its original state
  defp image_changed?(_current, original) when is_nil(original), do: false

  defp image_changed?(current, original) do
    current.creator != original.creator ||
      current.attribution != original.attribution ||
      current.license != original.license ||
      current.licenselink != original.licenselink ||
      current.sourcelink != original.sourcelink ||
      current.caption != original.caption ||
      current.source_id != original.source_id
  end

  # Helper to check if all copy targets are selected
  defp all_targets_selected?(nil, _images), do: false

  defp all_targets_selected?(copy_mode, images) do
    target_ids =
      images
      |> Enum.reject(&(&1.id == copy_mode.source_id))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    MapSet.equal?(copy_mode.selected_ids, target_ids) && MapSet.size(target_ids) > 0
  end
end
