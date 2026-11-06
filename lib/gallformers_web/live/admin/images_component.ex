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
    <div id={@id} class="flex flex-col gap-section">
      <%!-- A component's flash stays its own (LiveView copies it to the page only on navigation) --%>
      <.flash
        id={"#{@id}-flash-info"}
        kind={:info}
        flash={@flash}
        auto_dismiss={5000}
        phx-target={@myself}
      />
      <.flash id={"#{@id}-flash-error"} kind={:error} flash={@flash} phx-target={@myself} />

      <%!-- Images: a grid (drag to reorder) or a table --%>
      <.section title="Images" count={length(@images)} level={3}>
        <:aside>
          <div class="flex flex-wrap items-center gap-3">
            <span :if={@images != [] && @view_mode == :grid}>
              Drag to reorder. First image is the default.
            </span>
            <span
              class="inline-flex overflow-hidden rounded-ctl border border-line-strong"
              role="group"
              aria-label="View"
            >
              <button
                :for={
                  {view, icon, label} <- [
                    {:grid, "ph-squares-four", "Grid view"},
                    {:table, "ph-list", "Table view"}
                  ]
                }
                type="button"
                phx-click="toggle_view"
                phx-value-view={view}
                phx-target={@myself}
                disabled={@copy_mode != nil}
                aria-pressed={to_string(@view_mode == view)}
                aria-label={label}
                title={label}
                class={[
                  "flex h-7 items-center px-2.5 disabled:cursor-not-allowed",
                  view == :table && "border-l border-line-strong",
                  cond do
                    @view_mode == view -> "bg-brand-fill text-on-fill"
                    @copy_mode -> "bg-surface-2 text-muted"
                    true -> "bg-surface text-ink-2 hover:bg-surface-2"
                  end
                ]}
              >
                <.icon name={icon} class="size-4" />
              </button>
            </span>
          </div>
        </:aside>

        <div class="flex flex-col gap-block">
          <.empty_state :if={@images == []} title="No images uploaded yet" icon="ph-image" />

          <%!-- Warning for unattributed images --%>
          <.notice
            :if={Enum.any?(@images, &unattributed?/1)}
            kind={:warn}
            title="Some images are not attributed"
            data-unattributed-warning
          >
            Images marked with an orange border need a license, and a creator unless they are
            Public Domain / CC0 or come from a Source with a license. Hover over the image and
            click the edit button, or switch to the table view, to add this information.
          </.notice>

          <div :if={@images != []} id={"#{@id}-version-#{@images_version}"}>
            <%!-- Grid View --%>
            <div
              :if={@view_mode == :grid}
              id={"#{@id}-sortable"}
              phx-hook="SortableImages"
              phx-target={@myself}
              class="flex flex-wrap gap-4 p-1"
            >
              <div
                :for={{image, index} <- Enum.with_index(@images)}
                data-image-id={image.id}
                class={[
                  "group relative cursor-move rounded-panel",
                  cond do
                    unattributed?(image) -> "ring-2 ring-autumn ring-offset-2 ring-offset-surface"
                    index == 0 -> "ring-2 ring-brand ring-offset-2 ring-offset-surface"
                    true -> nil
                  end
                ]}
              >
                <img
                  src={Image.sized_url(image.path, :original)}
                  alt={image.caption || "Image"}
                  class="size-48 rounded-panel object-cover"
                />
                <.chip
                  :if={index == 0}
                  variant={:info}
                  data-default-image
                  class="absolute top-2 left-2"
                >
                  Default
                </.chip>
                <%!-- Warning badge for unattributed images --%>
                <div
                  :if={unattributed?(image)}
                  data-unattributed
                  class="absolute top-2 right-2 flex size-7 items-center justify-center rounded-full bg-autumn text-on-fill"
                  title="Not attributed"
                >
                  <.icon name="ph-warning" class="size-4" />
                </div>
                <%!-- Hover overlay with all actions --%>
                <div class="absolute inset-0 flex items-center justify-center gap-3 rounded-panel bg-overlay opacity-0 transition-opacity group-focus-within:opacity-100 group-hover:opacity-100">
                  <.button
                    icon="ph-eye"
                    icon_only
                    label="View image"
                    phx-click="view_image"
                    phx-value-id={image.id}
                    phx-target={@myself}
                    data-action="view"
                  />
                  <.button
                    icon="ph-pencil"
                    icon_only
                    label="Edit image"
                    phx-click="edit_image"
                    phx-value-id={image.id}
                    phx-target={@myself}
                    data-action="edit"
                  />
                  <.button
                    variant="danger"
                    icon="ph-trash"
                    icon_only
                    label="Delete image"
                    phx-click="confirm_delete"
                    phx-value-id={image.id}
                    phx-target={@myself}
                    data-action="delete"
                  />
                </div>
              </div>
            </div>

            <%!-- Table View --%>
            <div
              :if={@view_mode == :table}
              class="flex flex-col gap-block"
              phx-window-keydown={@copy_mode && "cancel_copy"}
              phx-key={@copy_mode && "Escape"}
              phx-target={@myself}
            >
              <.notice :if={@copy_mode} title="Copy metadata">
                Tick the images to copy this image's metadata to. Escape cancels.
                <:action>
                  <label class="inline-flex items-center gap-2 text-meta text-ink">
                    <input
                      type="checkbox"
                      phx-click="select_all_targets"
                      phx-target={@myself}
                      checked={all_targets_selected?(@copy_mode, @images)}
                      class="gf-checkbox"
                    /> Select all
                  </label>
                  <.button
                    variant="primary"
                    size="sm"
                    phx-click="confirm_copy"
                    phx-target={@myself}
                    disabled={MapSet.size(@copy_mode.selected_ids) == 0}
                  >
                    Apply ({MapSet.size(@copy_mode.selected_ids)})
                  </.button>
                  <.button size="sm" phx-click="cancel_copy" phx-target={@myself}>
                    Cancel
                  </.button>
                </:action>
              </.notice>

              <.data_table id={"#{@id}-table"} rows={@images}>
                <%!-- Checkbox column (copy mode only) --%>
                <:col :let={image} :if={@copy_mode} label="Copy to">
                  <%= if image.id == @copy_mode.source_id do %>
                    <.chip variant={:info} size="sm">From</.chip>
                  <% else %>
                    <input
                      type="checkbox"
                      phx-click="toggle_copy_target"
                      phx-value-id={image.id}
                      phx-target={@myself}
                      checked={MapSet.member?(@copy_mode.selected_ids, image.id)}
                      aria-label="Copy to this image"
                      class="gf-checkbox align-middle"
                    />
                  <% end %>
                </:col>
                <:col :let={image} label="Image">
                  <div class="relative w-16">
                    <img
                      src={Image.sized_url(image.path, :small)}
                      onerror={"this.onerror=null; this.src='#{Image.sized_url(image.path, :original)}'"}
                      alt={image.caption || "Image"}
                      class="size-16 rounded-ctl object-cover"
                    />
                    <div
                      :if={unattributed?(image)}
                      data-unattributed
                      class="absolute top-1 right-1 flex size-5 items-center justify-center rounded-full bg-autumn text-on-fill"
                      title="Not attributed"
                    >
                      <.icon name="ph-warning" class="size-3" />
                    </div>
                  </div>
                </:col>
                <:col :let={image} label="Default">
                  <span :if={default_image?(image, @images)} data-default-image class="text-brand">
                    <.icon name="ph-check-circle-fill" class="size-5" />
                    <span class="sr-only">Default</span>
                  </span>
                </:col>
                <:col :let={image} label="Creator" field={:creator}>{image.creator}</:col>
                <:col :let={image} label="License" field={:license}>{image.license}</:col>
                <:col :let={image} label="Source" field={:source}>
                  <.link :if={image.source} navigate={~p"/source/#{image.source.id}"}>
                    {truncate(image.source.title, 30)}
                  </.link>
                </:col>
                <:col :let={image} label="Source link" field={:sourcelink}>
                  <a
                    :if={present?(image.sourcelink)}
                    href={image.sourcelink}
                    target="_blank"
                    rel="noopener"
                    title={image.sourcelink}
                  >
                    {URI.parse(image.sourcelink).host || String.slice(image.sourcelink, 0, 20)}
                  </a>
                </:col>
                <:col :let={image} label="License link" field={:licenselink}>
                  <a
                    :if={valid_url?(image.licenselink)}
                    href={image.licenselink}
                    target="_blank"
                    rel="noopener"
                    title={image.licenselink}
                  >
                    {URI.parse(image.licenselink).host || String.slice(image.licenselink, 0, 20)}
                  </a>
                </:col>
                <:col :let={image} label="Attribution" field={:attribution}>
                  {image.attribution}
                </:col>
                <:col :let={image} label="Caption" field={:caption}>{image.caption}</:col>
                <:col :let={image} label="Actions" numeric>
                  <%!-- Row actions (hidden during copy mode) --%>
                  <div :if={!@copy_mode} class="flex justify-end gap-1">
                    <.button
                      variant="ghost"
                      size="sm"
                      icon="ph-copy"
                      icon_only
                      label="Copy metadata from this image"
                      title="Copy metadata from this image"
                      phx-click="start_copy"
                      phx-value-id={image.id}
                      phx-target={@myself}
                    />
                    <.button
                      variant="ghost"
                      size="sm"
                      icon="ph-pencil"
                      icon_only
                      label="Edit"
                      title="Edit"
                      phx-click="edit_image"
                      phx-value-id={image.id}
                      phx-target={@myself}
                      data-action="edit"
                    />
                    <.button
                      variant="ghost"
                      size="sm"
                      icon="ph-trash"
                      icon_only
                      label="Delete"
                      title="Delete"
                      phx-click="confirm_delete"
                      phx-value-id={image.id}
                      phx-target={@myself}
                      data-action="delete"
                    />
                  </div>
                </:col>
              </.data_table>
            </div>
          </div>
        </div>
      </.section>

      <%!-- Upload --%>
      <.section title="Upload images" level={3}>
        <div
          id={"#{@id}-uploader"}
          phx-hook="ImageUpload"
          phx-target={@myself}
          phx-update="ignore"
          data-max-files="20"
          data-accepted-types="image/jpeg,image/png,image/jpg"
          class="flex flex-col items-start gap-block"
        >
          <%!-- Dropzone --%>
          <div
            data-dropzone
            class="flex w-full cursor-pointer flex-col items-center gap-1 rounded-panel border-2 border-dashed border-line-strong p-6 text-center transition-colors hover:border-brand"
          >
            <.icon name="ph-cloud-arrow-up" class="size-10 text-muted" />
            <p class="text-ui text-ink-2">Drag and drop images here, or click to select</p>
            <p class="text-meta text-muted">Max 20 files. JPG or PNG only.</p>
            <input data-file-input type="file" accept="image/jpeg,image/png" multiple class="hidden" />
          </div>

          <%!-- Preview Container --%>
          <div data-preview-container class="flex flex-wrap gap-4"></div>

          <%!-- Progress Container --%>
          <div data-progress-container class="hidden w-full"></div>

          <.button data-upload-button variant="primary" disabled>Upload Images</.button>
        </div>
      </.section>

      <%!-- iNat Import --%>
      <.live_component
        module={InatImportComponent}
        id={"#{@id}-inat"}
        owner={@owner}
        uploader={@uploader}
        notify={{__MODULE__, @id}}
      />

      <%!-- Edit dialog --%>
      <.dialog
        :if={@editing_image}
        id={"#{@id}-edit-modal"}
        title="Edit image metadata"
        size={:lg}
        show
        on_cancel={JS.push("cancel_edit", target: @myself)}
      >
        <div class="flex flex-col gap-4 sm:flex-row sm:items-start">
          <%!-- Image Thumbnail (left column) --%>
          <img
            src={Image.sized_url(@editing_image.path, :medium)}
            onerror={"this.onerror=null; this.src='#{Image.sized_url(@editing_image.path, :original)}'"}
            alt="Image being edited"
            class="w-50 shrink-0 rounded-panel border border-line"
          />

          <%!-- Form Content (right column) --%>
          <div class="flex min-w-0 flex-1 flex-col gap-block">
            <.notice
              :if={@attribution_error}
              kind={:danger}
              title="Not attributed"
              data-attribution-error
            >
              {@attribution_error}
            </.notice>

            <%!-- Source Typeahead (outside form to prevent conflicts) --%>
            <div
              id={"#{@id}-source-typeahead-wrapper-#{@editing_image.id}"}
              class="flex flex-col gap-1"
            >
              <%= if @source_options == [] do %>
                <span class="gf-label">Source</span>
                <div class="flex h-ctl items-center rounded-ctl border border-line bg-surface-2 px-3 text-ui text-muted">
                  No sources available
                </div>
                <p class="text-meta text-muted">This Gall has no Sources yet.</p>
              <% else %>
                <.typeahead
                  id={"#{@id}-source-picker-#{@editing_image.id}"}
                  label="Source"
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
                      <span class="text-ink">{source.title}</span>
                      <span class="text-meta text-muted">
                        {source.author} ({source.pubyear})
                      </span>
                    </div>
                  </:result>
                </.typeahead>
                <p class="text-meta text-muted">
                  If the image is from a publication, select the source here. This will auto-populate the license and creator fields. {source_tip(
                    @source_options
                  )}
                </p>
              <% end %>
            </div>

            <hr class="border-line" />

            <form
              id={"#{@id}-edit-form"}
              phx-submit="save_image"
              phx-change="form_change"
              phx-target={@myself}
              class="flex flex-col gap-block"
            >
              <.field
                label={
                  if @selected_source,
                    do: "Direct Link to Image",
                    else: "Source URL (e.g., iNaturalist)"
                }
                for={"#{@id}-sourcelink"}
                help="A URL that points to the image in the original publication or observation."
              >
                <.input
                  type="text"
                  id={"#{@id}-sourcelink"}
                  name="sourcelink"
                  value={@editing_image.sourcelink || ""}
                  placeholder={
                    if @selected_source,
                      do: "Link to image in publication",
                      else: "Link to observation"
                  }
                  aria-describedby={"#{@id}-sourcelink-help"}
                />
              </.field>

              <hr class="border-line" />

              <p class="text-meta text-muted">
                These fields should be filled out regardless of the source type. If you select a Source, the license info will be pre-populated.
              </p>

              <.field
                label="License"
                for={"#{@id}-license"}
                help="The license for the image. We can only accept images with one of the licenses listed."
                required
              >
                <select
                  id={"#{@id}-license"}
                  name="license"
                  class="gf-select"
                  phx-change="update_license"
                  phx-target={@myself}
                  aria-describedby={"#{@id}-license-help"}
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
              </.field>

              <.field
                label="License Link"
                for={"#{@id}-licenselink"}
                help={license_link_help(@editing_image.license)}
              >
                <.input
                  :if={Licenses.url_readonly?(@editing_image.license)}
                  type="text"
                  id={"#{@id}-licenselink"}
                  name="licenselink"
                  value={Licenses.url(@editing_image.license)}
                  readonly
                  class="gf-input cursor-not-allowed text-muted"
                  aria-describedby={"#{@id}-licenselink-help"}
                />
                <.input
                  :if={not Licenses.url_readonly?(@editing_image.license)}
                  type="text"
                  id={"#{@id}-licenselink"}
                  name="licenselink"
                  value={@editing_image.licenselink || Licenses.url(@editing_image.license) || ""}
                  placeholder={
                    if @editing_image.license == "All Rights Reserved",
                      do: "Optional - link to usage terms",
                      else: ""
                  }
                  aria-describedby={"#{@id}-licenselink-help"}
                />
              </.field>

              <.field
                label="Creator / Photographer"
                for={"#{@id}-creator"}
                help="Who created the image. Usually a link to the individual or their name. Please no emails! Not needed for Public Domain / CC0 or an image from a Source with a license."
                required={@editing_image.license != "Public Domain / CC0"}
              >
                <.input
                  type="text"
                  id={"#{@id}-creator"}
                  name="creator"
                  value={@editing_image.creator || ""}
                  aria-describedby={"#{@id}-creator-help"}
                />
              </.field>

              <.field
                label="Attribution Notes"
                for={"#{@id}-attribution"}
                help="Any additional attribution information."
              >
                <.input
                  type="textarea"
                  id={"#{@id}-attribution"}
                  name="attribution"
                  rows="2"
                  value={@editing_image.attribution || ""}
                  aria-describedby={"#{@id}-attribution-help"}
                />
              </.field>

              <.field
                label="Caption"
                for={"#{@id}-caption"}
                help="An optional caption to be displayed with the image."
              >
                <.input
                  type="textarea"
                  id={"#{@id}-caption"}
                  name="caption"
                  rows="2"
                  value={@editing_image.caption || ""}
                  aria-describedby={"#{@id}-caption-help"}
                />
              </.field>
            </form>

            <hr class="border-line" />

            <%!-- Uploader / Last Changed --%>
            <div class="flex flex-wrap justify-between gap-2 text-meta text-muted">
              <span>Uploader: {@editing_image.uploader || "Unknown"}</span>
              <span>Last Changed: {@editing_image.lastchangedby || "Unknown"}</span>
            </div>
          </div>
        </div>
        <:actions>
          <.button type="button" phx-click="cancel_edit" phx-target={@myself}>
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
        </:actions>
      </.dialog>

      <%!-- Delete confirmation --%>
      <.dialog
        :if={@delete_image}
        id={"#{@id}-delete-modal"}
        title="Delete this image?"
        size={:sm}
        show
        on_cancel={JS.push("cancel_delete", target: @myself)}
      >
        <div class="flex flex-col items-center gap-block">
          <p class="self-start text-ink-2">
            Are you sure you want to delete this image? This action cannot be undone.
          </p>
          <img
            src={Image.sized_url(@delete_image.path, :medium)}
            onerror={"this.onerror=null; this.src='#{Image.sized_url(@delete_image.path, :original)}'"}
            alt="Image to delete"
            class="max-w-xs rounded-panel"
          />
        </div>
        <:actions>
          <.button type="button" phx-click="cancel_delete" phx-target={@myself}>
            Cancel
          </.button>
          <.button
            type="button"
            variant="danger"
            icon="ph-trash"
            phx-click="delete_image"
            phx-value-id={@delete_image.id}
            phx-target={@myself}
          >
            Delete image
          </.button>
        </:actions>
      </.dialog>

      <%!-- Full-size view --%>
      <.dialog
        :if={@viewing_image}
        id={"#{@id}-view-modal"}
        title={@name}
        size={:full}
        show
        on_cancel={JS.push("cancel_view", target: @myself)}
      >
        <img
          src={Image.sized_url(@viewing_image.path, :original)}
          alt={@viewing_image.caption || "Image"}
          class="size-full object-contain"
        />
      </.dialog>

      <%!-- Copy confirmation --%>
      <.dialog
        :if={@show_copy_confirm && @copy_mode}
        id={"#{@id}-copy-modal"}
        title="Copy image metadata"
        show
        on_cancel={JS.push("cancel_copy_confirm", target: @myself)}
      >
        <% source_image = Enum.find(@images, &(&1.id == @copy_mode.source_id)) %>
        <div class="flex flex-col gap-block">
          <p class="text-ink-2">Copy metadata from:</p>
          <div class="flex items-center gap-4 rounded-panel bg-surface-2 p-3">
            <img
              :if={source_image}
              src={Image.sized_url(source_image.path, :small)}
              onerror={"this.onerror=null; this.src='#{Image.sized_url(source_image.path, :original)}'"}
              alt="Source image"
              class="size-16 rounded-ctl object-cover"
            />
            <div :if={source_image} class="text-ui">
              <p><strong>Creator:</strong> {source_image.creator || "—"}</p>
              <p><strong>License:</strong> {source_image.license || "—"}</p>
            </div>
          </div>
          <p class="text-ink-2">
            To <strong>{MapSet.size(@copy_mode.selected_ids)}</strong> selected image(s)?
          </p>
          <div class="rounded-panel bg-surface-2 p-3 text-meta text-ink-2">
            <p class="font-semibold">Fields to be copied:</p>
            <p>Creator, License, License Link, Source Link, Attribution, Caption, Source</p>
          </div>
          <.notice :if={source_image && unattributed?(source_image)} kind={:warn}>
            The source image is not attributed. Its empty values will overwrite the target images' data.
          </.notice>
        </div>
        <:actions>
          <.button type="button" phx-click="cancel_copy_confirm" phx-target={@myself}>
            Cancel
          </.button>
          <.button type="button" variant="primary" phx-click="execute_copy" phx-target={@myself}>
            Copy Metadata
          </.button>
        </:actions>
      </.dialog>
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

  # The first image is the default.
  defp default_image?(image, [first | _rest]), do: image.id == first.id
  defp default_image?(_image, []), do: false

  # The license link's help; a Public Domain link may be changed from CC0's.
  defp license_link_help(license) do
    base = "The link to the license. Mandatory if CC-BY is chosen."

    if license == "Public Domain / CC0" and not Licenses.url_readonly?(license),
      do: base <> " Defaults to CC0, but can be changed for other public domain references.",
      else: base
  end

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
