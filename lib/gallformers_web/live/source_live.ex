defmodule GallformersWeb.SourceLive do
  @moduledoc """
  The Source page, on the design system (matter bc0d; behavior in
  docs/design-system/inventory/host-and-source-pages.md): a Source's title,
  kind, status and retraction (with its notice), its authors, year, DOI,
  ISBN and license, the original, its citation, the Galls it speaks of
  (`Gallformers.Catalog.list_galls_for_source/1`, each opening that Gall's
  entry for it), what it says of them (its Facts, grouped by Gall then
  category, then its taxonomic statements with whether Gallformers
  follows each, `Gallformers.Import.facts_for_source/1`, read-only; matters
  `f14c`, `f923`, read on the connected mount only), when it came to Gallformers
  (`Gallformers.Import.source_dates/1`) and its images, when it has any. An
  unknown or malformed ID is a 404.
  """
  use GallformersWeb, :live_view

  import GallformersWeb.FactsComponents, only: [facts_view: 1, facts_taxonomy: 1]

  alias Gallformers.{Accounts, Catalog, Images, Import, Sources}
  alias Gallformers.Images.Image

  # 60 Galls a page fill three columns.
  @page_size 60

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Integer.parse(id) do
      {source_id, ""} ->
        load_source(socket, source_id)

      _ ->
        raise GallformersWeb.NotFoundError, "No source #{id}"
    end
  end

  defp load_source(socket, source_id) do
    case Sources.get_source(source_id) do
      nil ->
        raise GallformersWeb.NotFoundError, "No source #{source_id}"

      source ->
        galls = Catalog.list_galls_for_source(source_id)
        images = Images.list_images_for_source(source_id) |> format_images()
        author_text = if source.author, do: " by #{source.author}", else: ""

        page_image =
          case images do
            [first | _] -> first.url
            [] -> nil
          end

        {:ok,
         assign(socket,
           page_title: source.title,
           page_description:
             "#{source.title}#{author_text} - A source referenced on Gallformers.",
           page_url: "/source/#{source_id}",
           page_image: page_image,
           page_json_ld: nil,
           page_noindex: false,
           source: source,
           dates: Map.fetch!(Import.source_dates([source_id]), source_id),
           galls: galls,
           images: images,
           current_page: 1,
           page_size: @page_size,
           facts: nil
         )
         |> load_facts(source_id)}
    end
  end

  # Read once, on the connected mount: the first render (what search
  # engines read) has the Source and its Galls without waiting for them.
  defp load_facts(socket, source_id) do
    if connected?(socket),
      do: assign(socket, facts: Import.facts_for_source(source_id)),
      else: socket
  end

  # The Source's kind, and its authors (the new list, else the old field).
  defp kind_label(kind),
    do: kind |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp authors(%{authors: [_ | _] = authors}), do: Enum.join(authors, "; ")
  defp authors(%{author: author}) when author not in [nil, ""], do: author
  defp authors(_source), do: nil

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    page = max(1, min(page, total_pages(socket.assigns.galls, socket.assigns.page_size)))
    {:noreply, assign(socket, current_page: page)}
  end

  @impl true
  def handle_event("gallery_index_changed", _params, socket) do
    {:noreply, socket}
  end

  defp format_images(images) do
    base_url = Image.base_url()

    Enum.map(images, fn img ->
      # Replace "original" with size name in the path
      small_path = String.replace(img.path, "original", "small")
      full_url = "#{base_url}/#{img.path}"

      %{
        id: img.id,
        url: full_url,
        src: full_url,
        thumb: "#{base_url}/#{small_path}",
        small_url: "#{base_url}/#{small_path}",
        alt: nil,
        creator: img.creator,
        attribution: img.attribution,
        license: img.license,
        licenselink: img.licenselink,
        sourcelink: img.sourcelink,
        uploader: img.uploader,
        lastchangedby: img.lastchangedby,
        caption: img.caption
      }
    end)
  end

  defp paginated_galls(galls, current_page, page_size) do
    galls
    |> Enum.drop((current_page - 1) * page_size)
    |> Enum.take(page_size)
  end

  defp total_pages(galls, page_size) do
    max(1, ceil(length(galls) / page_size))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-section">
        <.page_header>
          <:title>{@source.title}</:title>
          <:chip :if={@source.kind} variant={:rank}>{kind_label(@source.kind)}</:chip>
          <:chip :if={@source.retracted_on} variant={:danger}>Retracted</:chip>
          <:chip variant={if @source.datacomplete, do: :ok, else: :warn}>
            <span title={
              if @source.datacomplete,
                do:
                  "This source has been comprehensively reviewed and all relevant information entered.",
                else:
                  "We are still working on this source so information from the source is potentially still missing."
            }>
              {if @source.datacomplete, do: "Complete", else: "In progress"}
            </span>
          </:chip>
          <:meta label="Authors">{authors(@source) || "Not specified"}</:meta>
          <:meta label="Year">{@source.pubyear || "Not specified"}</:meta>
          <:meta :if={@source.doi} label="DOI">
            <a href={"https://doi.org/#{@source.doi}"} target="_blank" rel="noopener noreferrer">
              {@source.doi}
            </a>
          </:meta>
          <:meta :if={@source.isbn} label="ISBN">{@source.isbn}</:meta>
          <:meta label="License">
            <.link
              :if={valid_url?(@source.licenselink)}
              href={@source.licenselink}
              target="_blank"
              rel="noopener noreferrer"
            >
              {@source.license || "View"}
            </.link>
            <span :if={!valid_url?(@source.licenselink)}>{@source.license || "Not specified"}</span>
          </:meta>
          <:action>
            <.button
              :if={valid_url?(@source.link)}
              href={@source.link}
              target="_blank"
              rel="noopener noreferrer"
              icon="ph-arrow-square-out"
            >
              Original
            </.button>
            <.button
              :if={Accounts.admin?(@current_user)}
              href={~p"/admin/sources/#{@source.id}"}
              variant="ghost"
              size="sm"
              icon="ph-pencil-simple"
            >
              Edit
            </.button>
          </:action>
        </.page_header>

        <.notice
          :if={@source.retracted_on}
          kind={:danger}
          title={"Retracted on #{@source.retracted_on}"}
        >
          Gallformers no longer relies on what this Source says.
          <.link :if={@source.retracted_by_id} navigate={"/source/#{@source.retracted_by_id}"}>
            The retraction notice
          </.link>
        </.notice>

        <div class={if @images != [], do: "gf-with-rail", else: ""}>
          <div class="flex min-w-0 flex-col gap-section">
            <.section :if={@source.citation} title="Citation">
              <p class="font-serif text-body text-ink">{@source.citation}</p>
            </.section>

            <.section id="source-galls-section" title="Galls it covers" count={length(@galls)}>
              <p :if={@galls == []} class="text-ui text-muted">No galls connected to this source.</p>
              <.name_list
                :if={@galls != []}
                id="source-galls"
                items={paginated_galls(@galls, @current_page, @page_size)}
                columns={3}
              >
                <:item :let={gall}>
                  <.link navigate={"/gall/#{gall.id}?source=#{@source.id}"}>
                    <.taxon_name name={gall.name} />
                  </.link>
                </:item>
              </.name_list>
              <.pagination
                :if={total_pages(@galls, @page_size) > 1}
                page={@current_page}
                total_pages={total_pages(@galls, @page_size)}
                total_items={length(@galls)}
                page_size={@page_size}
                on_page_change={fn page -> JS.push("page", value: %{page: page}) end}
                class="mt-3"
              />
            </.section>

            <.section id="source-facts" title="What this Source says">
              <:aside>The facts Gallformers holds from it, by gall, in its own words</:aside>
              <p :if={@facts == nil} class="flex items-center gap-2 text-ui text-muted">
                <.loading_spinner size="sm" /> Loading…
              </p>
              <p
                :if={@facts && @facts.galls == [] && @facts.taxonomy.acts == []}
                class="text-ui text-muted"
              >
                No facts from this Source yet.
              </p>
              <div
                :if={@facts && (@facts.galls != [] || @facts.taxonomy.acts != [])}
                class="grid gap-3"
              >
                <.facts_view
                  :if={@facts.galls != []}
                  id="source-facts-galls"
                  galls={@facts.galls}
                  mode={:public}
                />
                <.facts_taxonomy
                  id="source-facts-taxonomy"
                  taxonomy={@facts.taxonomy}
                  mode={:public}
                />
              </div>
            </.section>

            <.source_dates id="source-dates" dates={@dates} class="text-meta text-muted" />
          </div>

          <.rail :if={@images != []} width={:wide}>
            <.photo_viewer id="source-images" photos={@images} name={@source.title} />
          </.rail>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
