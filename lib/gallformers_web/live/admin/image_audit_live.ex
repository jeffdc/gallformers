defmodule GallformersWeb.Admin.ImageAuditLive do
  @moduledoc """
  Admin LiveView for auditing images - finding orphans and unattributed images.

  Features:
  - Filter by orphans (S3 files with no DB record)
  - Filter by unattributed (images missing required attribution)
  - Paginated display with 50 images per page
  - Delete orphans or assign them to species
  - Edit unattributed images to add metadata
  """

  use GallformersWeb, :live_view

  alias Gallformers.Images
  alias Gallformers.Images.Audit
  alias Gallformers.Images.AuditCache
  alias Gallformers.Images.Image
  alias Gallformers.Licenses
  alias Gallformers.Sources
  alias Gallformers.Storage

  @per_page 50

  @impl true
  def mount(_params, session, socket) do
    current_user = session["current_user"]

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:page_title, "Image Audit")
      |> assign(:filter, :orphans)
      |> assign(:page, 1)
      |> assign(:per_page, @per_page)
      # Orphan state
      |> assign(:orphans, [])
      |> assign(:orphan_count, 0)
      |> assign(:orphan_stale, true)
      |> assign(:cache_status, nil)
      # Unattributed state
      |> assign(:unattributed, [])
      |> assign(:unattributed_count, 0)
      # Modal state
      |> assign(:editing_image, nil)
      |> assign(:original_image, nil)
      |> assign(:delete_orphan, nil)
      |> assign(:assign_orphan, nil)
      # Source typeahead state for edit modal
      |> assign(:source_options, [])
      |> assign(:source_query, "")
      |> assign(:source_results, [])
      |> assign(:selected_source, nil)
      # Species typeahead state for assign modal
      |> assign(:species_query, "")
      |> assign(:species_results, [])
      |> assign(:selected_species, nil)
      # Dirty state tracking
      |> assign(:form_dirty, false)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter =
      case Map.get(params, "filter", "orphans") do
        "unattributed" -> :unattributed
        _ -> :orphans
      end

    page = String.to_integer(Map.get(params, "page", "1"))

    socket =
      socket
      |> assign(:filter, filter)
      |> assign(:page, page)
      |> load_data()

    {:noreply, socket}
  end

  defp load_data(socket) do
    # Always load both counts for the tabs, then load full data for active filter
    socket
    |> load_counts()
    |> load_active_filter_data()
  end

  defp load_counts(socket) do
    # Load orphan count from cache
    {orphan_count, _stale?} =
      try do
        AuditCache.get_count()
      catch
        :exit, _ -> {0, true}
      end

    # Load unattributed count from DB (fast query)
    unattributed_count = Images.count_unattributed_images()

    socket
    |> assign(:orphan_count, orphan_count)
    |> assign(:unattributed_count, unattributed_count)
  end

  defp load_active_filter_data(socket) do
    case socket.assigns.filter do
      :orphans -> load_orphans_data(socket)
      :unattributed -> load_unattributed_data(socket)
    end
  end

  defp load_orphans_data(socket) do
    page = socket.assigns.page
    per_page = socket.assigns.per_page

    # Handle case where cache GenServer isn't running
    try do
      {orphans, total, stale?} = AuditCache.get_orphans(page: page, per_page: per_page)
      status = AuditCache.status()

      socket
      |> assign(:orphans, orphans)
      |> assign(:orphan_count, total)
      |> assign(:orphan_stale, stale?)
      |> assign(:cache_status, status)
    catch
      :exit, _ ->
        socket
        |> assign(:orphans, [])
        |> assign(:orphan_stale, true)
        |> assign(:cache_status, %{
          scanning?: false,
          last_scanned: nil,
          error: "Cache not available"
        })
        |> put_flash(:error, "Image audit cache is not running. Please restart the server.")
    end
  end

  defp load_unattributed_data(socket) do
    page = socket.assigns.page
    per_page = socket.assigns.per_page

    {images, _total} = Images.list_unattributed_images(page: page, per_page: per_page)

    assign(socket, :unattributed, images)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user} page_title="Image Audit">
      <div class="space-y-6">
        <%!-- Header with description --%>
        <div class="bg-white rounded-lg border border-gray-200 p-6">
          <h2 class="text-lg font-medium text-gray-900 mb-2">Image Audit Tool</h2>
          <p class="text-sm text-gray-600">
            Find and fix image issues across the entire image library. Orphaned images
            exist on S3 but have no database record. Unattributed images are missing
            required licensing or creator information.
          </p>
        </div>

        <%!-- Filter Tabs --%>
        <div class="border-b border-gray-200">
          <nav class="-mb-px flex space-x-8" aria-label="Tabs">
            <.link
              patch={~p"/admin/image-audit?filter=orphans"}
              class={[
                "whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm",
                @filter == :orphans &&
                  "border-gf-maroon text-gf-maroon",
                @filter != :orphans &&
                  "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              ]}
            >
              Orphans
              <span class={[
                "ml-2 px-2 py-0.5 rounded-full text-xs",
                @filter == :orphans && "bg-gf-maroon/10 text-gf-maroon",
                @filter != :orphans && "bg-gray-100 text-gray-600"
              ]}>
                {@orphan_count}
              </span>
            </.link>
            <.link
              patch={~p"/admin/image-audit?filter=unattributed"}
              class={[
                "whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm",
                @filter == :unattributed &&
                  "border-gf-maroon text-gf-maroon",
                @filter != :unattributed &&
                  "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
              ]}
            >
              Unattributed
              <span class={[
                "ml-2 px-2 py-0.5 rounded-full text-xs",
                @filter == :unattributed && "bg-gf-maroon/10 text-gf-maroon",
                @filter != :unattributed && "bg-gray-100 text-gray-600"
              ]}>
                {@unattributed_count}
              </span>
            </.link>
          </nav>
        </div>

        <%!-- Cache Status (orphans only) --%>
        <div
          :if={@filter == :orphans && @cache_status}
          class="flex items-center justify-between text-sm"
        >
          <div class="flex items-center gap-2 text-gray-500">
            <span :if={@cache_status.scanning?} class="flex items-center gap-2">
              <.loading_spinner size="sm" /> Scanning S3...
            </span>
            <span :if={!@cache_status.scanning? && @cache_status.last_scanned}>
              Last scanned: {format_time_ago(@cache_status.last_scanned)}
              <span :if={@orphan_stale} class="text-orange-600">(stale)</span>
            </span>
            <span :if={!@cache_status.scanning? && !@cache_status.last_scanned}>
              Not yet scanned
            </span>
          </div>
          <.button
            type="button"
            variant="secondary"
            size="sm"
            phx-click="refresh_cache"
            disabled={@cache_status.scanning?}
          >
            <.icon name="ph-arrows-clockwise" class="w-4 h-4 mr-1" /> Refresh
          </.button>
        </div>

        <%!-- Content based on filter --%>
        <div :if={@filter == :orphans} class="space-y-4">
          <.orphan_grid orphans={@orphans} />
          <.pagination
            :if={@orphan_count > 0}
            page={@page}
            total_pages={ceil(@orphan_count / @per_page)}
            total_items={@orphan_count}
            page_size={@per_page}
            on_page_change={
              fn page -> JS.push("change_page", value: %{page: page, filter: "orphans"}) end
            }
          />
        </div>

        <div :if={@filter == :unattributed} class="space-y-4">
          <.unattributed_grid images={@unattributed} />
          <.pagination
            :if={@unattributed_count > 0}
            page={@page}
            total_pages={ceil(@unattributed_count / @per_page)}
            total_items={@unattributed_count}
            page_size={@per_page}
            on_page_change={
              fn page -> JS.push("change_page", value: %{page: page, filter: "unattributed"}) end
            }
          />
        </div>

        <%!-- Edit Modal (for unattributed images) --%>
        <.edit_modal
          :if={@editing_image}
          image={@editing_image}
          original_image={@original_image}
          source_options={@source_options}
          source_query={@source_query}
          source_results={@source_results}
          selected_source={@selected_source}
          form_dirty={@form_dirty}
        />

        <%!-- Delete Orphan Modal --%>
        <.delete_orphan_modal :if={@delete_orphan} orphan={@delete_orphan} />

        <%!-- Assign Orphan Modal --%>
        <.assign_orphan_modal
          :if={@assign_orphan}
          orphan={@assign_orphan}
          species_query={@species_query}
          species_results={@species_results}
          selected_species={@selected_species}
        />
      </div>
    </Layouts.admin>
    """
  end

  # Component: Orphan Grid
  defp orphan_grid(assigns) do
    ~H"""
    <div :if={@orphans == []} class="text-center py-12 text-gray-500">
      <.icon name="ph-check-circle" class="w-12 h-12 mx-auto mb-4 text-green-500" />
      <p class="text-lg font-medium">No orphaned images found</p>
      <p class="text-sm">All S3 images have corresponding database records.</p>
    </div>

    <div
      :if={@orphans != []}
      id="orphan-grid"
      class="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-4"
    >
      <div
        :for={orphan <- @orphans}
        id={"orphan-#{Base.encode16(:crypto.hash(:md5, orphan.key), case: :lower) |> binary_part(0, 8)}"}
        class="relative group bg-white rounded-lg border border-gray-200 overflow-hidden"
      >
        <img
          src={orphan_thumbnail_url(orphan.key)}
          alt="Orphaned image"
          class="w-full aspect-square object-cover"
          loading="lazy"
        />
        <%!-- Status badge --%>
        <div class="absolute top-2 left-2 bg-red-500 text-white text-xs px-2 py-1 rounded">
          ORPHAN
        </div>
        <%!-- Species ID indicator --%>
        <div class="absolute top-2 right-2 text-xs">
          <span
            :if={orphan.species_exists}
            class="bg-blue-500 text-white px-2 py-1 rounded"
            title="Species exists but image not in DB"
          >
            ID: {orphan.species_id}
          </span>
          <span
            :if={!orphan.species_exists && orphan.species_id}
            class="bg-orange-500 text-white px-2 py-1 rounded"
            title="Species does not exist"
          >
            Invalid: {orphan.species_id}
          </span>
        </div>
        <%!-- Path info --%>
        <div class="p-2">
          <p class="text-xs text-gray-500 truncate" title={orphan.key}>
            {Path.basename(orphan.key)}
          </p>
        </div>
        <%!-- Hover actions --%>
        <div class="absolute inset-0 bg-black/50 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center gap-2">
          <button
            type="button"
            phx-click="confirm_delete_orphan"
            phx-value-path={orphan.key}
            class="p-2 bg-white rounded text-gray-700 hover:text-red-600"
            title="Delete from S3"
          >
            <.icon name="ph-trash" class="h-5 w-5" />
          </button>
          <button
            :if={orphan.species_exists}
            type="button"
            phx-click="assign_orphan"
            phx-value-path={orphan.key}
            phx-value-species-id={orphan.species_id}
            class="p-2 bg-white rounded text-gray-700 hover:text-green-600"
            title="Assign to species"
          >
            <.icon name="ph-link" class="h-5 w-5" />
          </button>
          <button
            :if={!orphan.species_exists}
            type="button"
            phx-click="assign_orphan_search"
            phx-value-path={orphan.key}
            class="p-2 bg-white rounded text-gray-700 hover:text-green-600"
            title="Search for species to assign"
          >
            <.icon name="ph-magnifying-glass-plus" class="h-5 w-5" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  # Component: Unattributed Grid
  defp unattributed_grid(assigns) do
    ~H"""
    <div :if={@images == []} class="text-center py-12 text-gray-500">
      <.icon name="ph-check-circle" class="w-12 h-12 mx-auto mb-4 text-green-500" />
      <p class="text-lg font-medium">All images are properly attributed</p>
      <p class="text-sm">No images are missing required licensing information.</p>
    </div>

    <div
      :if={@images != []}
      id="unattributed-grid"
      class="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-4"
    >
      <div
        :for={image <- @images}
        id={"unattributed-#{image.id}"}
        class="relative group bg-white rounded-lg border border-orange-300 overflow-hidden"
      >
        <img
          src={Image.sized_url(image.path, :small)}
          alt={image.caption || "Unattributed image"}
          class="w-full aspect-square object-cover"
          loading="lazy"
        />
        <%!-- Missing info badges --%>
        <div class="absolute top-2 left-2 flex flex-col gap-1">
          <span
            :if={is_nil(image.license) || image.license == ""}
            class="bg-orange-500 text-white text-xs px-2 py-0.5 rounded"
          >
            No License
          </span>
          <span
            :if={needs_creator?(image)}
            class="bg-orange-500 text-white text-xs px-2 py-0.5 rounded"
          >
            No Creator
          </span>
        </div>
        <%!-- Species info --%>
        <div class="p-2">
          <p
            class="text-xs text-gray-700 truncate font-medium"
            title={image.species && image.species.name}
          >
            {image.species && image.species.name}
          </p>
          <p class="text-xs text-gray-500">
            ID: {image.id}
          </p>
        </div>
        <%!-- Hover actions --%>
        <div class="absolute inset-0 bg-black/50 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center">
          <button
            type="button"
            phx-click="edit_image"
            phx-value-id={image.id}
            class="p-2 bg-white rounded text-gray-700 hover:text-gf-maroon"
            title="Edit metadata"
          >
            <.icon name="ph-pencil" class="h-5 w-5" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  # Component: Edit Modal
  defp edit_modal(assigns) do
    ~H"""
    <.modal id="edit-modal" show on_cancel={JS.push("cancel_edit")}>
      <:header>Edit Image Metadata</:header>
      <:body>
        <div class="flex gap-6 items-start">
          <%!-- Image Thumbnail --%>
          <div class="flex-shrink-0">
            <img
              src={Image.sized_url(@image.path, :medium)}
              alt="Image being edited"
              class="w-[200px] rounded border border-gray-200"
            />
            <p class="mt-2 text-sm text-gray-600">
              <.link
                navigate={~p"/gall/#{@image.species_id}"}
                class="text-gf-maroon hover:underline"
              >
                {@image.species && @image.species.name}
              </.link>
            </p>
          </div>

          <%!-- Form --%>
          <div class="flex-1 space-y-4">
            <%!-- Source Typeahead --%>
            <div class="space-y-1">
              <div class="flex items-center gap-2">
                <span class="text-sm font-medium text-gray-700">Source</span>
                <.info_tip content="Select a source to auto-populate license and creator." />
              </div>
              <%= if @source_options == [] do %>
                <p class="text-xs text-gray-500">No sources mapped to this species.</p>
              <% else %>
                <.typeahead
                  id={"source-picker-#{@image.id}"}
                  label=""
                  placeholder="Search sources..."
                  query={@source_query}
                  results={@source_results}
                  selected={@selected_source}
                  search_event="search_source"
                  select_event="select_source"
                  clear_event="clear_source"
                  display_fn={& &1.title}
                >
                  <:result :let={source}>
                    <span class="text-gray-900">{source.title}</span>
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
              <.input
                type="text"
                name="sourcelink"
                label="Source URL"
                value={@image.sourcelink || ""}
                placeholder="Link to original source"
              />

              <%!-- License --%>
              <div class="space-y-1">
                <label class="text-sm font-medium text-gray-700">License</label>
                <select name="license" class="gf-select" phx-change="update_license">
                  <option value="">Select a license</option>
                  <option
                    :for={license <- Licenses.all()}
                    value={license}
                    selected={license == @image.license}
                  >
                    {license}
                  </option>
                </select>
              </div>

              <%!-- License Link --%>
              <.input
                :if={!Licenses.url_readonly?(@image.license)}
                type="text"
                name="licenselink"
                label="License Link"
                value={@image.licenselink || Licenses.url(@image.license) || ""}
              />
              <.input
                :if={Licenses.url_readonly?(@image.license)}
                type="text"
                name="licenselink"
                label="License Link"
                value={Licenses.url(@image.license)}
                readonly
                class="bg-gray-50"
              />

              <%!-- Creator --%>
              <.input
                type="text"
                name="creator"
                label="Creator / Photographer"
                value={@image.creator || ""}
              />

              <%!-- Attribution --%>
              <.input
                type="textarea"
                name="attribution"
                label="Attribution Notes"
                value={@image.attribution || ""}
                rows="2"
              />

              <%!-- Caption --%>
              <.input
                type="textarea"
                name="caption"
                label="Caption"
                value={@image.caption || ""}
                rows="2"
              />
            </form>
          </div>
        </div>
      </:body>
      <:footer>
        <.button type="button" variant="secondary" phx-click="cancel_edit">
          Cancel
        </.button>
        <.button type="submit" variant="primary" form="edit-image-form" disabled={!@form_dirty}>
          Save Changes
        </.button>
      </:footer>
    </.modal>
    """
  end

  # Component: Delete Orphan Modal
  defp delete_orphan_modal(assigns) do
    ~H"""
    <.modal
      id="delete-orphan-modal"
      show
      on_cancel={JS.push("cancel_delete_orphan")}
      class="gf-modal-md"
    >
      <:header>Delete Orphan Image</:header>
      <:body>
        <p class="text-gray-600 mb-4">
          Are you sure you want to permanently delete this image from S3?
          This action cannot be undone.
        </p>
        <div class="flex justify-center mb-4">
          <img
            src={orphan_thumbnail_url(@orphan.key)}
            alt="Image to delete"
            class="max-w-xs rounded"
          />
        </div>
        <p class="text-xs text-gray-500 text-center break-all">
          {@orphan.key}
        </p>
      </:body>
      <:footer>
        <.button type="button" variant="secondary" phx-click="cancel_delete_orphan">
          Cancel
        </.button>
        <.button
          type="button"
          variant="danger"
          phx-click="delete_orphan"
          phx-value-path={@orphan.key}
        >
          Delete
        </.button>
      </:footer>
    </.modal>
    """
  end

  # Component: Assign Orphan Modal
  defp assign_orphan_modal(assigns) do
    ~H"""
    <.modal id="assign-orphan-modal" show on_cancel={JS.push("cancel_assign_orphan")}>
      <:header>Assign Orphan to Species</:header>
      <:body>
        <div class="space-y-4">
          <div class="flex justify-center mb-4">
            <img
              src={orphan_thumbnail_url(@orphan.key)}
              alt="Image to assign"
              class="max-w-xs rounded"
            />
          </div>

          <.typeahead
            id="species-picker"
            label="Species"
            placeholder="Search for a species..."
            query={@species_query}
            results={@species_results}
            selected={@selected_species}
            search_event="search_species"
            select_event="select_species"
            clear_event="clear_species"
            display_fn={& &1.name}
          >
            <:result :let={species}>
              <span class="text-gray-900">{species.name}</span>
            </:result>
          </.typeahead>

          <form
            :if={@selected_species}
            id="assign-orphan-form"
            phx-submit="do_assign_orphan"
            class="space-y-4"
          >
            <input type="hidden" name="path" value={@orphan.key} />
            <input type="hidden" name="species_id" value={@selected_species.id} />

            <.input
              type="text"
              name="creator"
              label="Creator / Photographer"
              value=""
            />

            <div class="space-y-1">
              <label class="text-sm font-medium text-gray-700">License</label>
              <select name="license" class="gf-select">
                <option value="">Select a license</option>
                <option :for={license <- Licenses.all()} value={license}>
                  {license}
                </option>
              </select>
            </div>
          </form>
        </div>
      </:body>
      <:footer>
        <.button type="button" variant="secondary" phx-click="cancel_assign_orphan">
          Cancel
        </.button>
        <.button
          :if={@selected_species}
          type="submit"
          variant="primary"
          form="assign-orphan-form"
        >
          Assign to {@selected_species.name}
        </.button>
      </:footer>
    </.modal>
    """
  end

  # Event Handlers

  @impl true
  def handle_event("change_page", %{"page" => page, "filter" => filter}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/image-audit?filter=#{filter}&page=#{page}")}
  end

  @impl true
  def handle_event("refresh_cache", _params, socket) do
    AuditCache.refresh()
    # Reload after a brief delay to show scanning state
    Process.send_after(self(), :reload_orphans, 500)
    {:noreply, put_flash(socket, :info, "Refreshing cache...")}
  catch
    :exit, _ ->
      {:noreply, put_flash(socket, :error, "Cache not available. Please restart the server.")}
  end

  @impl true
  def handle_event("confirm_delete_orphan", %{"path" => path}, socket) do
    orphan = Enum.find(socket.assigns.orphans, &(&1.key == path))
    {:noreply, assign(socket, :delete_orphan, orphan)}
  end

  @impl true
  def handle_event("cancel_delete_orphan", _params, socket) do
    {:noreply, assign(socket, :delete_orphan, nil)}
  end

  @impl true
  def handle_event("delete_orphan", %{"path" => path}, socket) do
    case Audit.delete_s3_orphan(path) do
      :ok ->
        # Refresh the cache in background (for future page loads)
        AuditCache.refresh()

        # Optimistically remove from current view immediately
        updated_orphans = Enum.reject(socket.assigns.orphans, &(&1.key == path))
        new_count = socket.assigns.orphan_count - 1

        socket =
          socket
          |> assign(:delete_orphan, nil)
          |> assign(:orphans, updated_orphans)
          |> assign(:orphan_count, max(new_count, 0))
          |> put_flash(:info, "Orphan image deleted")

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("assign_orphan", %{"path" => path, "species-id" => species_id}, socket) do
    orphan = Enum.find(socket.assigns.orphans, &(&1.key == path))
    species_id = String.to_integer(species_id)
    species = Gallformers.Species.get_species(species_id)

    socket =
      socket
      |> assign(:assign_orphan, orphan)
      |> assign(:selected_species, species && %{id: species.id, name: species.name})
      |> assign(:species_query, "")
      |> assign(:species_results, [])

    {:noreply, socket}
  end

  @impl true
  def handle_event("assign_orphan_search", %{"path" => path}, socket) do
    orphan = Enum.find(socket.assigns.orphans, &(&1.key == path))

    socket =
      socket
      |> assign(:assign_orphan, orphan)
      |> assign(:selected_species, nil)
      |> assign(:species_query, "")
      |> assign(:species_results, [])

    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_assign_orphan", _params, socket) do
    socket =
      socket
      |> assign(:assign_orphan, nil)
      |> assign(:selected_species, nil)
      |> assign(:species_query, "")
      |> assign(:species_results, [])

    {:noreply, socket}
  end

  @impl true
  def handle_event("search_species", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        Images.search_species(query)
      else
        []
      end

    {:noreply, assign(socket, species_query: query, species_results: results)}
  end

  @impl true
  def handle_event("select_species", %{"id" => id}, socket) do
    species_id = String.to_integer(id)
    species = Enum.find(socket.assigns.species_results, &(&1.id == species_id))

    socket =
      socket
      |> assign(:selected_species, species)
      |> assign(:species_query, "")
      |> assign(:species_results, [])

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_species", _params, socket) do
    socket =
      socket
      |> assign(:selected_species, nil)
      |> assign(:species_query, "")
      |> assign(:species_results, [])

    {:noreply, socket}
  end

  @impl true
  def handle_event("do_assign_orphan", params, socket) do
    path = params["path"]
    species_id = String.to_integer(params["species_id"])

    uploader =
      socket.assigns.current_user.name || socket.assigns.current_user.email || "admin"

    attrs = %{
      creator: params["creator"],
      license: params["license"],
      uploader: uploader,
      lastchangedby: uploader
    }

    case Audit.create_image_from_orphan(path, species_id, attrs) do
      {:ok, _image} ->
        # Refresh cache in background (for future page loads)
        AuditCache.refresh()

        # Optimistically remove from current view immediately
        updated_orphans = Enum.reject(socket.assigns.orphans, &(&1.key == path))
        new_count = socket.assigns.orphan_count - 1

        socket =
          socket
          |> assign(:assign_orphan, nil)
          |> assign(:selected_species, nil)
          |> assign(:orphans, updated_orphans)
          |> assign(:orphan_count, max(new_count, 0))
          |> put_flash(:info, "Image assigned to species")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to assign: #{inspect(changeset.errors)}")}
    end
  end

  @impl true
  def handle_event("edit_image", %{"id" => id}, socket) do
    image = Images.get_image_with_species(String.to_integer(id))
    source_options = Sources.get_sources_for_species(image.species_id)

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
  def handle_event("search_source", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 1 do
        search_term = String.downcase(query)

        socket.assigns.source_options
        |> Enum.filter(fn source ->
          title = source.title || ""
          String.contains?(String.downcase(title), search_term)
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

  @impl true
  def handle_event("update_license", %{"license" => license}, socket) do
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
    image = Images.get_image!(editing_image.id)

    lastchangedby =
      socket.assigns.current_user.name || socket.assigns.current_user.email || "admin"

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
        socket =
          socket
          |> assign(:editing_image, nil)
          |> assign(:original_image, nil)
          |> assign(:source_options, [])
          |> assign(:source_query, "")
          |> assign(:source_results, [])
          |> assign(:selected_source, nil)
          |> assign(:form_dirty, false)
          |> load_data()
          |> put_flash(:info, "Image updated successfully")

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update image")}
    end
  end

  @impl true
  def handle_info(:reload_orphans, socket) do
    {:noreply, load_data(socket)}
  end

  # Helper Functions

  defp orphan_thumbnail_url(path) do
    # Orphans don't have size variants (those are generated on proper upload),
    # so always use the original
    cdn_url = Storage.cdn_url()
    "#{cdn_url}/#{path}"
  end

  defp needs_creator?(image) do
    Images.requires_attribution?(image.license) &&
      (is_nil(image.creator) || image.creator == "")
  end

  defp format_time_ago(nil), do: "Never"

  defp format_time_ago(datetime) do
    diff_seconds = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff_seconds < 60 -> "just now"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)} min ago"
      diff_seconds < 86_400 -> "#{div(diff_seconds, 3600)} hours ago"
      true -> "#{div(diff_seconds, 86_400)} days ago"
    end
  end

  defp image_changed?(_current, nil), do: false

  defp image_changed?(current, original) do
    current.creator != original.creator ||
      current.attribution != original.attribution ||
      current.license != original.license ||
      current.licenselink != original.licenselink ||
      current.sourcelink != original.sourcelink ||
      current.caption != original.caption ||
      current.source_id != original.source_id
  end
end
