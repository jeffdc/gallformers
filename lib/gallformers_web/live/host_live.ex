defmodule GallformersWeb.HostLive do
  @moduledoc """
  The Host page, on the design system (matter bc0d; behavior in
  docs/design-system/inventory/host-and-source-pages.md): a plant from
  `Gallformers.Taxa.host_page/1` (its names, each with its authority
  upright after the italic name, and lineage), "Identify a gall
  on …", the Galls on it as the rank pages' list (`GallformersWeb.RankGalls`,
  photos or a table with facets; for admins each links to its Gall's range
  exclusions), a pointer to the Galls on its genus as a whole, its photos,
  its range (framed on the native range; Enlarge opens a large map), its
  synonyms and See also. Citations on plants were not migrated, so the page
  has no Sources (`803b`, decision 1). An unknown or malformed ID, a Gall or
  a plant above species rank is a 404.

  Edit mode (`?edit`, curators; matter `ec2c`): the plant's name, its
  authorship, synonyms and range are edited into the curator's tray (`GallformersWeb.HostLive.Editor`;
  the range on the Host range editor,
  `GallformersWeb.Admin.TaxonomyLive.RangeEditor`, in a dialog), delete and
  merge sit at the foot of the rail (`GallformersWeb.RecordRemoval`), and
  what is edited in the taxonomy admin (lineage, common names, WCVP link,
  photos) is linked from the Editing notice.
  """
  use GallformersWeb, :live_view

  alias Gallformers.{Accounts, Catalog, Curation, Images, Places, Ranges, Taxa}
  alias Gallformers.Images.Image
  alias Gallformers.Taxa.ReadModels.HostPage
  alias GallformersWeb.Admin.TaxonomyLive.RangeEditor
  alias GallformersWeb.LineageBreadcrumb
  alias GallformersWeb.RankGalls
  alias GallformersWeb.RankPage
  alias GallformersWeb.SEO

  import GallformersWeb.RankPageComponents, only: [rank_galls: 1]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Integer.parse(id) do
      {host_id, ""} -> socket |> assign(editing: false, range_open: false) |> load_host(host_id)
      _ -> raise GallformersWeb.NotFoundError, "No host #{id}"
    end
    |> subscribe()
  end

  # A curator keeps up with their tray (Edit mode).
  defp subscribe({:ok, %{assigns: %{host: _}} = socket} = mounted) do
    if socket.assigns[:curator] && connected?(socket),
      do: Curation.subscribe(socket.assigns.curator)

    mounted
  end

  defp subscribe(mounted), do: mounted

  @impl true
  def handle_params(params, _uri, socket) do
    # Edit mode (`?edit`): curators only; for anyone else the public page.
    editing = Map.has_key?(params, "edit") and socket.assigns[:curator] != nil
    {:noreply, assign(socket, editing: editing)}
  end

  defp load_host(socket, host_id) do
    case Taxa.host_page(host_id) do
      :not_found ->
        # A plant merged into another (live navigation; the HTTP request is
        # redirected by `GallformersWeb.Plugs.LegacyEntityRedirect`).
        case Taxa.taxon_redirect(host_id) do
          nil -> raise GallformersWeb.NotFoundError, "No host #{host_id}"
          to -> {:ok, push_navigate(socket, to: ~p"/host/#{to}")}
        end

      {:ok, %HostPage{} = host} ->
        galls = Catalog.list_galls_for_hosts([host.id])
        images = host.id |> Images.list_images_for_taxon() |> format_images()
        range_data = Ranges.get_display_range_for_taxa([host.id])
        range = range_data.in_range
        inherited_range = range_data.inherited_range

        # Build SEO data
        page_url = "/host/#{host_id}"

        page_description =
          "#{host.name} - A host plant species documented on Gallformers with #{length(galls)} associated galls."

        page_image =
          case images do
            [first | _] -> first.url
            [] -> nil
          end

        # Build JSON-LD structured data
        json_ld = build_host_json_ld(host, page_url, page_description, page_image)

        {:ok,
         assign(socket,
           page_title: host.name,
           page_description: page_description,
           page_url: page_url,
           page_image: page_image,
           page_json_ld: json_ld,
           page_noindex: false,
           host: host,
           galls: galls,
           images: images,
           taxonomy: LineageBreadcrumb.from_lineage(host.lineage),
           range: range,
           inherited_range: inherited_range,
           introduced_range: range_data.introduced_range,
           # Framed on the native range; introduced places are drawn, not framed.
           range_bounds:
             Places.get_bounds_for_codes(
               (range -- range_data.introduced_range) ++ inherited_range
             ),
           host_galls: %{host_id: host.id} |> RankGalls.load() |> RankGalls.new(views: [:photos]),
           rank_sort: %{field: :name, dir: :asc},
           on_genus: on_genus(host),
           map_open: false
         )}
    end
  end

  defp build_host_json_ld(host, url, description, image) do
    json_ld = %{
      "@context" => "https://schema.org",
      "@type" => "Thing",
      "name" => host.name,
      "description" => description,
      "url" => SEO.base_url() <> url,
      "identifier" => host.name
    }

    json_ld = if image, do: Map.put(json_ld, "image", image), else: json_ld

    Jason.encode!(json_ld)
  end

  defp format_images(images) do
    base_url = Image.base_url()

    Enum.map(images, fn img ->
      # Replace "original" with size name in the path
      small_path = String.replace(img.path, "original", "small")
      full_url = "#{base_url}/#{img.path}"

      Map.merge(img, %{
        url: full_url,
        src: full_url,
        thumb: "#{base_url}/#{small_path}",
        small_url: "#{base_url}/#{small_path}",
        alt: nil
      })
    end)
  end

  # The Galls recorded on the plant's genus as a whole, for a pointer.
  defp on_genus(host) do
    case Enum.find(host.lineage, &(&1.rank == :genus)) do
      nil -> nil
      genus -> %{name: genus.name, count: length(RankPage.galls_on_hosts([genus.taxon_id]))}
    end
  end

  defp shown_galls(assigns), do: RankGalls.compute(assigns.host_galls, "", assigns.rank_sort)

  defp crumbs(lineage) do
    for taxon <- Enum.drop(lineage, -1),
        path = GallformersWeb.TaxonomyURL.public_path(taxon),
        path != nil,
        do: %{name: crumb_name(taxon), path: path, italic: taxon.rank in [:genus, :section]}
  end

  # A section is named "sect. Quercus", so it isn't read as its genus.
  defp crumb_name(%{rank: :section, name: name}), do: "sect. " <> name
  defp crumb_name(%{name: name}), do: name

  # The Galls list's events, and its sort.
  @impl true
  def handle_event("galls_" <> _ = event, params, socket),
    do: {:noreply, update(socket, :host_galls, &RankGalls.handle(&1, event, params))}

  @impl true
  def handle_event("sort", %{"field" => field}, socket)
      when field in ["name", "common_name", "count"] do
    %{field: current, dir: dir} = socket.assigns.rank_sort
    {field, dir} = RankPage.toggle_sort(current, dir, String.to_existing_atom(field))
    {:noreply, assign(socket, rank_sort: %{field: field, dir: dir})}
  end

  # -- Edit mode: the range, on the Host range editor --------------------------

  def handle_event("open_range", _params, %{assigns: %{editing: true}} = socket) do
    %{host: host} = socket.assigns

    socket =
      socket
      |> RangeEditor.init(taxon_name: host.name)
      |> RangeEditor.load(range_rows(socket))
      |> assign(range_open: true)

    {:noreply, socket}
  end

  def handle_event("close_range", _params, socket), do: {:noreply, close_range(socket)}

  def handle_event("range_to_tray", params, %{assigns: %{range_open: true}} = socket) do
    spec = %{
      kind: :editorial,
      subject: {:plant, socket.assigns.host.id},
      field: :range,
      value: RangeEditor.entries_for_save(socket),
      based_on: String.trim(params["based_on"] || "")
    }

    case Curation.add_item(socket.assigns.curator, spec) do
      {:ok, _item} ->
        send_update(GallformersWeb.HostLive.Editor, id: "host-editor", refresh: true)
        {:noreply, close_range(socket)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "The range couldn't go in your tray (#{reason}).")}
    end
  end

  def handle_event(event, params, %{assigns: %{range_open: true}} = socket)
      when event in ~w(toggle_region toggle_country refresh_from_wcvp cancel_wcvp_refresh
                       wcvp_nomatch_search select_wcvp_nomatch cancel_wcvp_search
                       continue_wcvp_search) do
    {:noreply, RangeEditor.handle_event(event, params, socket)}
  end

  @impl true
  def handle_event("open_map", _params, socket), do: {:noreply, assign(socket, map_open: true)}

  @impl true
  def handle_event("close_map", _params, socket), do: {:noreply, assign(socket, map_open: false)}

  @impl true
  def handle_event("gallery_index_changed", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("navigate_to_place", %{"code" => code}, socket) do
    {:noreply, push_navigate(socket, to: "/place/#{code}")}
  end

  @impl true
  def handle_info({:change_set, _change}, socket) do
    if socket.assigns.editing,
      do: send_update(GallformersWeb.HostLive.Editor, id: "host-editor", refresh: true)

    {:noreply, reload(socket)}
  end

  def handle_info(message, %{assigns: %{range_open: true}} = socket) do
    if RangeEditor.handles_info?(message),
      do: {:noreply, RangeEditor.handle_info(message, socket)},
      else: {:noreply, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_async(name, result, socket),
    do: {:noreply, RangeEditor.handle_async(name, result, socket)}

  # The range the editor starts from: the one in the tray, else the plant's.
  defp range_rows(socket) do
    %{host: host, curator: curator} = socket.assigns

    case Curation.pending_for(curator, {:plant, host.id}) |> Map.get({:editorial, :range}, []) do
      [item | _] ->
        code_of = Map.new(socket.assigns.all_places, &{&1.id, &1.code})

        for {place_id, precision, type} <- item.spec.value,
            code = code_of[place_id],
            do: %{code: code, precision: precision, distribution_type: type}

      [] ->
        Ranges.get_places_for_taxon_with_precision(host.id)
    end
  end

  # The editor shares the page's map assigns: the page's are loaded again.
  defp close_range(socket), do: socket |> assign(range_open: false) |> reload()

  defp reload(socket) do
    keep = Map.take(socket.assigns, [:editing, :range_open])
    {:ok, socket} = load_host(socket, socket.assigns.host.id)
    assign(socket, keep)
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, list: shown_galls(assigns))

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-section">
        <.page_header>
          <:crumb :for={c <- crumbs(@host.lineage)} navigate={c.path} italic={c.italic}>
            {c.name}
          </:crumb>
          <:title name>
            <.taxon_name name={@host.name} />
            <span
              :if={@host.authorship}
              data-part="authorship"
              class="font-normal not-italic text-ink-2"
            >
              {@host.authorship}
            </span>
          </:title>
          <:chip variant={:rank}>{String.capitalize(to_string(@host.rank))}</:chip>
          <:chip>Host plant</:chip>
          <:chip variant={if @host.datacomplete, do: :ok, else: :warn}>
            <span title={
              if @host.datacomplete,
                do: "All galls known to occur on this plant have been added.",
                else: "We are still working on this plant so galls might be missing."
            }>
              {if @host.datacomplete, do: "Complete", else: "In progress"}
            </span>
          </:chip>
          <:meta :if={@host.common_names != []} label="Common name">
            {Enum.join(@host.common_names, ", ")}
          </:meta>
          <:meta :if={@host.abundance} label="Abundance">{@host.abundance}</:meta>
          <:action>
            <.button
              navigate={"/id?h=#{URI.encode_www_form(@host.name)}"}
              variant="primary"
              icon="ph-magnifying-glass-plus"
            >
              Identify a gall on {@host.name}
            </.button>
          </:action>
          <:action :if={@curator}>
            <.edit_toggle editing={@editing} path={"/host/#{@host.id}"} />
          </:action>
        </.page_header>

        <div :if={@editing} id="editing" class="flex flex-col gap-2">
          <.notice kind={:info} title="Editing">
            Each change goes into your tray at the foot of the screen. Nothing changes until you Review and apply.
          </.notice>
          <.edit_scope kind={:elsewhere} href={~p"/admin/taxonomy/#{@host.id}"}>
            The lineage, common names, WCVP link and photos: on the taxonomy of <i>{@host.name}</i>.
          </.edit_scope>
          <.edit_scope kind={:follows}>
            The Galls on it follow from each Gall's Hosts: edit them on the Gall's page.
          </.edit_scope>
        </div>

        <div class="gf-with-rail">
          <div class="flex min-w-0 flex-col gap-section">
            <.live_component
              :if={@editing}
              module={GallformersWeb.HostLive.Editor}
              id="host-editor"
              host={@host}
              curator={@curator}
            />

            <.rank_galls
              :if={@host_galls.all != []}
              id="host-galls"
              list={@list}
              sort={@rank_sort}
              narrowed={false}
              title="Galls on it"
              edit_path={if Accounts.admin?(@current_user), do: &"/gall/#{&1.id}?edit"}
            />
            <.empty_state :if={@host_galls.all == []} title="No galls recorded on this plant yet." />

            <p :if={@on_genus && @on_genus.count > 0} id="on-genus" class="text-meta text-ink-2">
              {@on_genus.count} more {if @on_genus.count == 1, do: "gall is", else: "galls are"} recorded on
              <.link navigate={"/genus/#{URI.encode(@on_genus.name)}"}>
                <.taxon_name name={@on_genus.name} rank="genus" />
              </.link>
              as a whole, with no species named.
            </p>
          </div>

          <.rail width={:wide}>
            <%!-- Plants rarely have photos: an empty viewer only for an admin, to add some. --%>
            <.photo_viewer
              :if={@images != [] or Accounts.admin?(@current_user)}
              id="host-images"
              photos={@images}
              name={@host.name}
              edit_href={~p"/admin/taxonomy/#{@host.id}" <> "#images"}
              admin={Accounts.admin?(@current_user)}
            />

            <.panel title="Range">
              <:header_action>
                <.button
                  :if={@range != [] or @inherited_range != []}
                  variant="ghost"
                  size="sm"
                  icon="ph-arrows-out"
                  phx-click="open_map"
                >
                  Enlarge
                </.button>
              </:header_action>
              <p :if={@range == [] and @inherited_range == []} class="text-ui text-muted">
                No range data.
              </p>
              <.range_map
                :if={(@range != [] or @inherited_range != []) and not @map_open and not @range_open}
                id="host-range-map"
                class="h-72"
                in_range={@range}
                inherited_range={@inherited_range}
                introduced_range={@introduced_range}
                bounds={@range_bounds}
                navigable
              />
              <:footer :if={@inherited_range != [] or @introduced_range != []}>
                <.range_map_legend mode={:public} />
              </:footer>
            </.panel>

            <dl :if={@host.synonyms != []} class="flex flex-col gap-3 text-ui">
              <div>
                <dt class="text-meta text-muted">
                  Also known as
                </dt>
                <dd id="host-names" class="text-ink-2">
                  <span :for={{s, i} <- Enum.with_index(@host.synonyms)}>
                    {if i > 0, do: " · "}<.taxon_name name={s.name} />
                    <span :if={s.authorship} data-part="authorship">{s.authorship}</span>
                    <span
                      :if={s.sensu}
                      class="text-meta text-muted"
                    >
                      (misapplied, {s.sensu})
                    </span>
                  </span>
                </dd>
              </div>
            </dl>
            <.see_also name={@host.name} type={:host} />
            <.record_metadata inserted_at={@host.inserted_at} updated_at={@host.updated_at} />

            <.live_component
              :if={@editing}
              module={GallformersWeb.RecordRemoval}
              id="record-removal"
              subject={{:taxon, @host.id}}
              name={@host.name}
              actor={@curator}
              merge={:plant}
              deleted_path={~p"/hosts"}
              merged_path={&"/host/#{&1}?edit"}
            />
          </.rail>
        </div>
      </div>

      <.dialog
        :if={@range_open}
        id="host-range-dialog"
        title={"Range of #{@host.name}"}
        size={:full}
        show
        on_cancel={JS.push("close_range")}
      >
        <RangeEditor.editor
          range_taxon_name={@range_taxon_name}
          range_entries={@range_entries}
          all_places={@all_places}
          place_by_code={@place_by_code}
          in_range={@in_range}
          inherited_range={@inherited_range}
          introduced_range={@introduced_range}
          range_bounds={@range_bounds}
          powo_diff={@powo_diff}
          wcvp_nomatch_search={@wcvp_nomatch_search}
          wcvp_available={@wcvp_available}
          wcvp_refreshing={@wcvp_refreshing}
          wcvp_searching={@wcvp_searching}
          wcvp_loading={@wcvp_loading}
        />
        <form id="host-range-tray" phx-submit="range_to_tray" class="mt-block">
          <.field label="Based on" for="host-range-based-on" help="When it departs from WCVP">
            <input id="host-range-based-on" name="based_on" type="text" class="gf-input" />
          </.field>
        </form>
        <:actions>
          <.button type="button" variant="ghost" phx-click="close_range">Cancel</.button>
          <.button type="submit" form="host-range-tray" variant="primary">Put in tray</.button>
        </:actions>
      </.dialog>

      <.dialog
        :if={@map_open}
        id="range-dialog"
        title={"Range of #{@host.name}"}
        size={:full}
        show
        on_cancel={JS.push("close_map")}
      >
        <.range_map
          id="host-range-map-large"
          class="h-160"
          in_range={@range}
          inherited_range={@inherited_range}
          introduced_range={@introduced_range}
          bounds={@range_bounds}
          navigable
        />
      </.dialog>
    </Layouts.app>
    """
  end
end
