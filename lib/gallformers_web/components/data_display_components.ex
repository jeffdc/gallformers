defmodule GallformersWeb.DataDisplayComponents do
  @moduledoc """
  Data display components for the Gallformers application.

  Provides components for displaying species data, images, taxonomy,
  sources, and other domain-specific information.
  """
  use Phoenix.Component
  use Gettext, backend: GallformersWeb.Gettext

  import GallformersWeb.CoreComponents, only: [icon: 1]

  @doc """
  Renders an image gallery with lightbox support and V1-style attribution.

  ## Examples

      <.image_gallery images={@images} />

      <.image_gallery images={@images} species_id={123} current_user={@current_user} />
  """
  attr :images, :list,
    required: true,
    doc:
      "list of image maps with :src, :alt, :creator, :license, :licenselink, :sourcelink, :caption keys"

  attr :species_id, :integer, default: nil, doc: "species ID for admin edit link"
  attr :current_user, :any, default: nil, doc: "current user for showing admin controls"
  attr :class, :any, default: nil, doc: "additional CSS classes"
  attr :id, :string, default: "image-gallery", doc: "unique id for the gallery"
  attr :no_image_src, :string, default: nil, doc: "optional placeholder image when no images"

  def image_gallery(assigns) do
    assigns =
      assigns
      |> assign(:images_json, prepare_images_json(assigns.images))
      |> assign(:first_image, List.first(assigns.images) || %{})
      |> assign(:image_count, length(assigns.images))

    ~H"""
    <div
      :if={@image_count > 0}
      id={@id}
      class={["relative", @class]}
      phx-hook="ImageGallery"
      phx-update="ignore"
      data-images={@images_json}
      tabindex="0"
    >
      <div class="relative bg-gray-100 rounded-lg overflow-hidden flex items-center justify-center">
        <img
          data-main-image
          src={@first_image[:src] || @first_image["src"]}
          alt={@first_image[:alt] || @first_image["alt"] || ""}
          class="max-h-[400px] max-w-full object-contain cursor-pointer"
          loading="lazy"
          data-open-lightbox
        />

        <button
          :if={@image_count > 1}
          type="button"
          data-prev
          class="absolute left-1 top-1/2 -translate-y-1/2 px-3 py-4 rounded bg-black/50 hover:bg-black/70 text-white text-2xl font-bold transition-colors"
          aria-label={gettext("Previous image")}
        >
          &lt;
        </button>

        <button
          :if={@image_count > 1}
          type="button"
          data-next
          class="absolute right-1 top-1/2 -translate-y-1/2 px-3 py-4 rounded bg-black/50 hover:bg-black/70 text-white text-2xl font-bold transition-colors"
          aria-label={gettext("Next image")}
        >
          &gt;
        </button>

        <div
          :if={@image_count > 1}
          data-counter
          class="absolute bottom-2 left-1/2 -translate-x-1/2 px-2 py-1 rounded bg-black/60 text-white text-sm"
        >
          1 / {@image_count}
        </div>
      </div>

      <%!-- Caption (updated by JS) --%>
      <p
        data-caption
        class={[
          "mt-1 text-sm text-gray-600 italic",
          if(get_img_field(@first_image, :caption) == "", do: "hidden")
        ]}
      >
        {get_img_field(@first_image, :caption)}
      </p>

      <%!-- Attribution line (updated by JS) --%>
      <div class="mt-1 text-sm text-gray-600">
        <span :if={get_img_field(@first_image, :sourcelink) != ""}>
          <a
            data-source-link
            href={get_img_field(@first_image, :sourcelink)}
            target="_blank"
            rel="noopener noreferrer"
            class="hover:underline"
          >
            Image
          </a>
          {" "}by{" "}
        </span>
        <span data-creator>{get_img_field(@first_image, :creator)}</span>
        <span :if={get_img_field(@first_image, :license) != ""}>{" © "}</span>
        <a
          :if={get_img_field(@first_image, :licenselink) != ""}
          data-license-link
          href={get_img_field(@first_image, :licenselink)}
          target="_blank"
          rel="noopener noreferrer"
          class="hover:underline"
        >
          <span data-license>{get_img_field(@first_image, :license)}</span>
        </a>
        <span
          :if={
            get_img_field(@first_image, :licenselink) == "" &&
              get_img_field(@first_image, :license) != ""
          }
          data-license
        >
          {get_img_field(@first_image, :license)}
        </span>
      </div>

      <%!-- Action buttons --%>
      <div class="mt-2 flex justify-center gap-1">
        <button
          type="button"
          data-open-info
          class="px-2 py-1 text-sm font-bold border border-gray-300 rounded bg-white hover:bg-gray-50"
          aria-label={gettext("Image details")}
        >
          ⓘ
        </button>
        <.link
          :if={@current_user && @species_id}
          href={"/admin/images?species_id=#{@species_id}"}
          class="px-2 py-1 text-sm border border-gray-300 rounded bg-white hover:bg-gray-50"
          aria-label={gettext("Edit images")}
        >
          ✎
        </.link>
      </div>

      <%!-- Info dialog --%>
      <dialog
        data-info-dialog
        class="rounded-lg shadow-xl max-w-4xl w-full p-0 m-auto backdrop:bg-black/50"
      >
        <div class="p-8">
          <div class="flex justify-between items-center mb-6">
            <h3 class="text-2xl font-semibold">{gettext("Image Details")}</h3>
            <button
              type="button"
              data-close-info
              class="text-gray-400 hover:text-gray-600"
              aria-label={gettext("Close")}
            >
              <.icon name="ph-x" class="size-7" />
            </button>
          </div>
          <div class="flex gap-8">
            <div class="flex-shrink-0">
              <img
                data-info-image
                src={@first_image[:src] || @first_image["src"]}
                alt={@first_image[:alt] || @first_image["alt"] || "Image preview"}
                class="w-80 h-80 object-contain rounded border border-gray-200 bg-gray-50"
              />
            </div>
            <div class="flex-1 space-y-4 text-lg">
              <div>
                <strong>{gettext("Source:")}</strong>{" "}
                <a
                  :if={get_img_field(@first_image, :sourcelink) != ""}
                  data-info-source
                  href={get_img_field(@first_image, :sourcelink)}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="hover:underline"
                >
                  {get_img_field(@first_image, :source_title) ||
                    get_img_field(@first_image, :sourcelink)}
                </a>
                <span :if={get_img_field(@first_image, :sourcelink) == ""} data-info-source>
                  {get_img_field(@first_image, :source_title)}
                </span>
              </div>
              <div>
                <strong>{gettext("License:")}</strong>{" "}
                <a
                  :if={get_img_field(@first_image, :licenselink) != ""}
                  data-info-license
                  href={get_img_field(@first_image, :licenselink)}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="hover:underline"
                >
                  {get_img_field(@first_image, :license)}
                </a>
                <span
                  :if={
                    get_img_field(@first_image, :licenselink) == "" &&
                      get_img_field(@first_image, :license) != ""
                  }
                  data-info-license
                >
                  {get_img_field(@first_image, :license)}
                </span>
              </div>
              <div>
                <strong>{gettext("Attribution:")}</strong>{" "}
                <span data-info-attribution>{get_img_field(@first_image, :attribution)}</span>
              </div>
              <div>
                <strong>{gettext("Creator:")}</strong>{" "}
                <span data-info-creator>{get_img_field(@first_image, :creator)}</span>
              </div>
              <div>
                <strong>{gettext("Uploader:")}</strong>{" "}
                <span data-info-uploader>{get_img_field(@first_image, :uploader)}</span>
              </div>
              <div>
                <strong>{gettext("Last Modified:")}</strong>{" "}
                <span data-info-lastchangedby>{get_img_field(@first_image, :lastchangedby)}</span>
              </div>
              <div>
                <strong>{gettext("Caption:")}</strong>{" "}
                <span data-info-caption>{get_img_field(@first_image, :caption)}</span>
              </div>
            </div>
          </div>
        </div>
      </dialog>

      <%!-- Lightbox --%>
      <dialog
        data-lightbox
        class="w-screen h-screen max-w-none m-0 p-0 bg-black/90 backdrop:bg-transparent"
      >
        <div class="w-full h-full flex flex-col items-center justify-center p-4">
          <button
            type="button"
            data-close-lightbox
            class="absolute top-4 right-4 p-2 rounded-full bg-white/20 hover:bg-white/30 text-white"
            aria-label={gettext("Close")}
          >
            <.icon name="ph-x" class="size-6" />
          </button>

          <img
            data-lightbox-image
            src={@first_image[:src] || @first_image["src"]}
            alt={@first_image[:alt] || @first_image["alt"] || ""}
            class="max-w-full max-h-[70vh] object-contain"
          />

          <%!-- Lightbox attribution --%>
          <div class="mt-2 text-sm text-white/80" data-lightbox-attribution>
            <a
              :if={get_img_field(@first_image, :sourcelink) != ""}
              data-lightbox-source-link
              href={get_img_field(@first_image, :sourcelink)}
              target="_blank"
              rel="noopener noreferrer"
              class="text-white hover:underline"
            >
              Image
            </a>
            <span :if={get_img_field(@first_image, :sourcelink) == ""} data-lightbox-source-link>
              Image
            </span>
            {" "}by{" "}
            <span data-lightbox-creator>{get_img_field(@first_image, :creator)}</span>
            <span :if={get_img_field(@first_image, :license) != ""}>{" © "}</span>
            <a
              :if={get_img_field(@first_image, :licenselink) != ""}
              data-lightbox-license-link
              href={get_img_field(@first_image, :licenselink)}
              target="_blank"
              rel="noopener noreferrer"
              class="text-white hover:underline"
            >
              <span data-lightbox-license>{get_img_field(@first_image, :license)}</span>
            </a>
            <span
              :if={
                get_img_field(@first_image, :licenselink) == "" &&
                  get_img_field(@first_image, :license) != ""
              }
              data-lightbox-license
            >
              {get_img_field(@first_image, :license)}
            </span>
          </div>

          <div :if={@image_count > 1} class="mt-4 flex items-center gap-6">
            <button
              type="button"
              data-prev
              class="px-5 py-3 rounded bg-white/20 hover:bg-white/30 text-white text-3xl font-bold"
              aria-label={gettext("Previous image")}
            >
              &lt;
            </button>
            <span data-counter class="text-white text-lg">1 / {@image_count}</span>
            <button
              type="button"
              data-next
              class="px-5 py-3 rounded bg-white/20 hover:bg-white/30 text-white text-3xl font-bold"
              aria-label={gettext("Next image")}
            >
              &gt;
            </button>
          </div>
        </div>
      </dialog>
    </div>

    <div
      :if={@image_count == 0 && @no_image_src}
      class="aspect-[4/3] bg-gray-100 rounded-lg overflow-hidden"
    >
      <img
        src={@no_image_src}
        alt="No image available for this species"
        class="w-full h-full object-contain"
      />
    </div>

    <div
      :if={@image_count == 0 && !@no_image_src}
      class="aspect-[4/3] bg-gray-100 rounded-lg flex items-center justify-center"
    >
      <div class="text-gray-400 text-center">
        <.icon name="ph-image" class="size-12 mx-auto mb-2" />
        <p>{gettext("No images available")}</p>
      </div>
    </div>
    """
  end

  # Helper to safely get image field with fallback
  defp get_img_field(img, field) when is_map(img) do
    Map.get(img, field) || Map.get(img, to_string(field)) || ""
  end

  defp get_img_field(_, _), do: ""

  defp prepare_images_json(images) do
    images
    |> Enum.map(&normalize_image_data/1)
    |> Jason.encode!()
  end

  defp normalize_image_data(img) do
    %{
      id: get_img_field(img, :id),
      src: get_img_field(img, :src),
      alt: get_img_field(img, :alt),
      caption: get_img_field(img, :caption),
      creator: get_img_field(img, :creator),
      license: get_img_field(img, :license),
      licenselink: get_img_field(img, :licenselink),
      sourcelink: get_img_field(img, :sourcelink),
      attribution: get_img_field(img, :attribution),
      source_title: Map.get(img, :source_title) || Map.get(img, "source_title"),
      uploader: get_img_field(img, :uploader),
      lastchangedby: get_img_field(img, :lastchangedby)
    }
  end

  @doc """
  Renders a species card for list views.

  ## Examples

      <.species_card species={@species} />
  """
  attr :species, :map,
    required: true,
    doc: "species data with :id, :name, :description, :image keys"

  attr :href, :string, default: nil, doc: "link to the species detail page"
  attr :class, :any, default: nil, doc: "additional CSS classes"

  def species_card(assigns) do
    ~H"""
    <div class={[
      "bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden hover:shadow-md transition-shadow",
      @class
    ]}>
      <.link :if={@href} navigate={@href} class="block">
        <div class="aspect-[4/3] bg-gray-100">
          <img
            :if={@species[:image] || @species["image"]}
            src={@species[:image] || @species["image"]}
            alt={@species[:name] || @species["name"]}
            class="w-full h-full object-cover"
            loading="lazy"
          />
          <div
            :if={!(@species[:image] || @species["image"])}
            class="w-full h-full flex items-center justify-center text-gray-400"
          >
            <.icon name="ph-image" class="size-12" />
          </div>
        </div>
        <div class="p-4">
          <h3 class="text-lg font-medium hover:underline">
            <em>{@species[:name] || @species["name"]}</em>
          </h3>
          <p
            :if={@species[:description] || @species["description"]}
            class="mt-1 text-sm text-gray-600 line-clamp-2"
          >
            {@species[:description] || @species["description"]}
          </p>
        </div>
      </.link>
      <div :if={!@href}>
        <div class="aspect-[4/3] bg-gray-100">
          <img
            :if={@species[:image] || @species["image"]}
            src={@species[:image] || @species["image"]}
            alt={@species[:name] || @species["name"]}
            class="w-full h-full object-cover"
            loading="lazy"
          />
          <div
            :if={!(@species[:image] || @species["image"])}
            class="w-full h-full flex items-center justify-center text-gray-400"
          >
            <.icon name="ph-image" class="size-12" />
          </div>
        </div>
        <div class="p-4">
          <h3 class="text-lg font-medium text-gf-maroon">
            <em>{@species[:name] || @species["name"]}</em>
          </h3>
          <p
            :if={@species[:description] || @species["description"]}
            class="mt-1 text-sm text-gray-600 line-clamp-2"
          >
            {@species[:description] || @species["description"]}
          </p>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a list of host plants.

  ## Examples

      <.host_list hosts={@hosts} />
  """
  attr :hosts, :list, required: true, doc: "list of host maps with :id, :name, :genus keys"
  attr :class, :any, default: nil, doc: "additional CSS classes"

  def host_list(assigns) do
    ~H"""
    <ul :if={@hosts != []} class={["space-y-1", @class]}>
      <li :for={host <- @hosts} class="flex items-center gap-2">
        <.icon name="ph-leaf" class="size-4 text-green-600 flex-shrink-0" />
        <.link
          :if={host[:id] || host["id"]}
          navigate={"/host/#{host[:id] || host["id"]}"}
          class="hover:underline"
        >
          <em>{host[:name] || host["name"]}</em>
          <span :if={host[:common_name] || host["common_name"]} class="text-gray-600 ml-1">
            ({host[:common_name] || host["common_name"]})
          </span>
        </.link>
        <span :if={!(host[:id] || host["id"])}>
          <em>{host[:name] || host["name"]}</em>
          <span :if={host[:common_name] || host["common_name"]} class="text-gray-600 ml-1">
            ({host[:common_name] || host["common_name"]})
          </span>
        </span>
      </li>
    </ul>
    <p :if={@hosts == []} class="text-gray-500 italic">
      {gettext("No host plants recorded")}
    </p>
    """
  end

  @doc """
  Renders a source citation.

  ## Examples

      <.source_citation source={@source} />
  """
  attr :source, :map, required: true, doc: "source data with :title, :author, :year, :url keys"
  attr :class, :any, default: nil, doc: "additional CSS classes"

  def source_citation(assigns) do
    ~H"""
    <div class={["text-sm", @class]}>
      <span :if={@source[:author] || @source["author"]} class="font-medium">
        {@source[:author] || @source["author"]}.
      </span>
      <span :if={@source[:year] || @source["year"]}>
        ({@source[:year] || @source["year"]}).
      </span>
      <span :if={@source[:title] || @source["title"]}>
        <.link
          :if={@source[:url] || @source["url"]}
          href={@source[:url] || @source["url"]}
          target="_blank"
          rel="noopener noreferrer"
          class="text-blue-600 hover:underline"
        >
          {@source[:title] || @source["title"]}
          <.icon name="ph-arrow-square-out" class="size-3 inline ml-0.5" />
        </.link>
        <span :if={!(@source[:url] || @source["url"])}>
          {@source[:title] || @source["title"]}
        </span>
      </span>
      <span :if={@source[:publication] || @source["publication"]} class="italic">
        {@source[:publication] || @source["publication"]}.
      </span>
    </div>
    """
  end

  @doc """
  Renders a taxonomy breadcrumb showing the taxonomic hierarchy.

  ## Examples

      <.taxonomy_breadcrumb family={@family} genus={@genus} species={@species} />
  """
  attr :family, :map, default: nil, doc: "family data with :id, :name keys"
  attr :genus, :map, default: nil, doc: "genus data with :id, :name, :description keys"
  attr :species, :map, default: nil, doc: "species name (for display only)"
  attr :show_family, :boolean, default: true, doc: "whether to show family"
  attr :show_genus, :boolean, default: true, doc: "whether to show genus"
  attr :class, :any, default: nil, doc: "additional CSS classes"

  def taxonomy_breadcrumb(assigns) do
    ~H"""
    <div class={["flex flex-wrap items-center gap-1 text-sm", @class]}>
      <span :if={@show_family && @family} class="flex items-center gap-1">
        <strong>{gettext("Family:")}</strong>
        <.link
          :if={@family[:id] || @family["id"]}
          navigate={"/family/#{@family[:id] || @family["id"]}"}
          class="hover:underline"
        >
          {@family[:name] || @family["name"]}
        </.link>
        <span :if={!(@family[:id] || @family["id"])}>
          {@family[:name] || @family["name"]}
        </span>
      </span>

      <span :if={@show_family && @family && @show_genus && @genus} class="mx-1 text-gray-400">|</span>

      <span :if={@show_genus && @genus} class="flex items-center gap-1">
        <strong>{gettext("Genus:")}</strong>
        <.link
          :if={@genus[:id] || @genus["id"]}
          navigate={"/genus/#{@genus[:id] || @genus["id"]}"}
          class="hover:underline"
        >
          <em>{@genus[:name] || @genus["name"]}</em>
          <span :if={@genus[:description] || @genus["description"]} class="text-gray-600 not-italic">
            - {@genus[:description] || @genus["description"]}
          </span>
        </.link>
        <span :if={!(@genus[:id] || @genus["id"])}>
          <em>{@genus[:name] || @genus["name"]}</em>
          <span :if={@genus[:description] || @genus["description"]} class="text-gray-600 not-italic">
            - {@genus[:description] || @genus["description"]}
          </span>
        </span>
      </span>

      <span
        :if={((@show_family && @family) || (@show_genus && @genus)) && @species}
        class="mx-1 text-gray-400"
      >
        |
      </span>

      <span :if={@species} class="flex items-center gap-1">
        <strong>{gettext("Species:")}</strong>
        <em>{@species[:name] || @species["name"] || @species}</em>
      </span>
    </div>
    """
  end

  @doc """
  Renders a data completeness indicator.

  Shows whether data for an entity is complete or has missing information.

  ## Examples

      <.data_completeness_indicator complete={true} />
      <.data_completeness_indicator complete={false} missing={["hosts", "description"]} />
  """
  attr :complete, :boolean, required: true, doc: "whether the data is complete"
  attr :missing, :list, default: [], doc: "list of missing fields"
  attr :class, :any, default: nil, doc: "additional CSS classes"

  def data_completeness_indicator(assigns) do
    ~H"""
    <span class={["relative inline-flex group", @class]}>
      <button
        type="button"
        class="px-2 py-1 text-lg border border-gray-300 rounded bg-white hover:bg-gray-50"
        aria-label={if @complete, do: gettext("Data complete"), else: gettext("Data incomplete")}
      >
        {if @complete, do: "💯", else: "❓"}
      </button>
      <div
        class="absolute z-50 hidden group-hover:block left-full top-1/2 -translate-y-1/2 ml-2 w-64 px-3 py-2 text-sm bg-gray-900 text-white rounded-md shadow-lg"
        role="tooltip"
      >
        <span :if={@complete}>
          {gettext("All data fields are complete")}
        </span>
        <div :if={!@complete}>
          <p class="font-medium mb-1">{gettext("Missing information:")}</p>
          <ul class="list-disc list-inside">
            <li :for={field <- @missing}>{field}</li>
          </ul>
          <p :if={@missing == []} class="italic">
            {gettext("Some data may be incomplete")}
          </p>
        </div>
        <div class="absolute right-full top-1/2 -translate-y-1/2 w-0 h-0 border-4 border-r-gray-900 border-y-transparent border-l-transparent" />
      </div>
    </span>
    """
  end

  @doc """
  Renders an edit button for admin users.

  ## Examples

      <.edit_button href="/admin/species/123/edit" />
      <.edit_button href="/admin/species/123/edit" label="Edit Species" />
  """
  attr :href, :string, required: true, doc: "link to the edit page"
  attr :label, :string, default: nil, doc: "optional button label"
  attr :class, :any, default: nil, doc: "additional CSS classes"

  def edit_button(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={[
        "inline-flex items-center gap-1 px-3 py-1.5 text-sm font-medium rounded-md",
        "bg-gf-maroon text-white hover:bg-gf-maroon/90 transition-colors",
        @class
      ]}
    >
      <.icon name="ph-pencil-simple" class="size-4" />
      <span :if={@label}>{@label}</span>
      <span :if={!@label}>{gettext("Edit")}</span>
    </.link>
    """
  end

  @doc """
  Renders external links for a species (iNaturalist, BugGuide, etc).

  ## Examples

      <.external_links links={@external_links} />
  """
  attr :links, :list, required: true, doc: "list of link maps with :name, :url keys"
  attr :class, :any, default: nil, doc: "additional CSS classes"

  def external_links(assigns) do
    ~H"""
    <div :if={@links != []} class={["flex flex-wrap gap-2", @class]}>
      <.link
        :for={link <- @links}
        href={link[:url] || link["url"]}
        target="_blank"
        rel="noopener noreferrer"
        class="inline-flex items-center gap-1 px-3 py-1.5 text-sm rounded-full border border-gray-300 hover:bg-gray-50 transition-colors"
      >
        {link[:name] || link["name"]}
        <.icon name="ph-arrow-square-out" class="size-3" />
      </.link>
    </div>
    """
  end

  @doc """
  Renders a source list.

  ## Examples

      <.source_list sources={@sources} />
  """
  attr :sources, :list, required: true, doc: "list of source maps"
  attr :class, :any, default: nil, doc: "additional CSS classes"

  def source_list(assigns) do
    ~H"""
    <ul :if={@sources != []} class={["space-y-3", @class]}>
      <li :for={source <- @sources}>
        <.source_citation source={source} />
      </li>
    </ul>
    <p :if={@sources == []} class="text-gray-500 italic">
      {gettext("No sources available")}
    </p>
    """
  end

  @doc """
  Renders species synonymy information.

  ## Examples

      <.species_synonymy aliases={@aliases} />
  """
  attr :aliases, :list, required: true, doc: "list of alias/synonym names"
  attr :class, :any, default: nil, doc: "additional CSS classes"

  def species_synonymy(assigns) do
    ~H"""
    <div :if={@aliases != []} class={@class}>
      <h4 class="text-sm font-medium text-gray-700 mb-1">{gettext("Also known as:")}</h4>
      <ul class="flex flex-wrap gap-2">
        <li
          :for={alias_name <- @aliases}
          class="px-2 py-0.5 bg-gray-100 rounded text-sm italic"
        >
          {alias_name}
        </li>
      </ul>
    </div>
    """
  end

  @doc """
  Renders an abundance indicator.

  ## Examples

      <.abundance_indicator level="common" />
  """
  attr :level, :string, required: true, doc: "abundance level (common, uncommon, rare, etc)"
  attr :class, :any, default: nil, doc: "additional CSS classes"

  def abundance_indicator(assigns) do
    level_styles = %{
      "common" => %{bg: "bg-green-100", text: "text-green-800"},
      "uncommon" => %{bg: "bg-yellow-100", text: "text-yellow-800"},
      "rare" => %{bg: "bg-orange-100", text: "text-orange-800"},
      "very rare" => %{bg: "bg-red-100", text: "text-red-800"},
      "unknown" => %{bg: "bg-gray-100", text: "text-gray-800"}
    }

    styles = Map.get(level_styles, String.downcase(assigns.level), level_styles["unknown"])
    assigns = assign(assigns, :styles, styles)

    ~H"""
    <span class={[
      "inline-flex items-center px-2 py-0.5 rounded text-sm font-medium",
      @styles.bg,
      @styles.text,
      @class
    ]}>
      {@level}
    </span>
    """
  end

  @doc """
  Renders a container for table row actions.

  Groups action buttons with consistent spacing.

  ## Examples

      <.table_actions>
        <.action_button icon="ph-arrow-square-out" label="View" href="/gall/123" />
        <.action_button icon="ph-pencil-simple" label="Edit" href="/admin/galls/123" />
        <.action_button icon="ph-trash" label="Delete" variant="danger" phx-click="delete" phx-value-id="123" />
      </.table_actions>
  """
  attr :class, :any, default: nil, doc: "additional CSS classes"
  slot :inner_block, required: true

  def table_actions(assigns) do
    ~H"""
    <div class={["flex items-center justify-center gap-1", @class]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders an icon button with tooltip for table actions.

  ## Examples

      <.action_button icon="ph-arrow-square-out" label="View" href="/gall/123" />
      <.action_button icon="ph-pencil-simple" label="Edit" navigate="/admin/galls/123" />
      <.action_button icon="ph-trash" label="Delete" variant="danger" phx-click="delete" />
  """
  attr :icon, :string, required: true, doc: "Phosphor icon name"
  attr :label, :string, required: true, doc: "tooltip text and aria-label"

  attr :variant, :string,
    default: "default",
    values: ~w(default primary danger),
    doc: "button style variant"

  attr :href, :string, default: nil, doc: "external link URL"
  attr :navigate, :string, default: nil, doc: "LiveView navigation path"
  attr :confirm, :string, default: nil, doc: "confirmation message"
  attr :class, :any, default: nil, doc: "additional CSS classes"
  attr :rest, :global, include: ~w(phx-click phx-value-id disabled)

  def action_button(assigns) do
    variant_classes = %{
      "default" => "text-gray-600 hover:text-gray-900 hover:bg-gray-100",
      "primary" => "text-gf-maroon hover:text-gf-autumn hover:bg-gf-maroon/10",
      "danger" => "text-red-600 hover:text-red-900 hover:bg-red-50"
    }

    assigns = assign(assigns, :variant_class, Map.fetch!(variant_classes, assigns.variant))

    ~H"""
    <div class="relative group">
      <.link
        :if={@href}
        href={@href}
        class={[
          "inline-flex items-center justify-center p-1.5 rounded transition-colors",
          @variant_class,
          @class
        ]}
        aria-label={@label}
        {@rest}
      >
        <.icon name={@icon} class="size-5" />
      </.link>
      <.link
        :if={@navigate}
        navigate={@navigate}
        class={[
          "inline-flex items-center justify-center p-1.5 rounded transition-colors",
          @variant_class,
          @class
        ]}
        aria-label={@label}
        {@rest}
      >
        <.icon name={@icon} class="size-5" />
      </.link>
      <button
        :if={!@href && !@navigate}
        type="button"
        class={[
          "inline-flex items-center justify-center p-1.5 rounded transition-colors",
          @variant_class,
          @class
        ]}
        aria-label={@label}
        data-confirm={@confirm}
        {@rest}
      >
        <.icon name={@icon} class="size-5" />
      </button>
      <div
        class="absolute z-50 hidden group-hover:block bottom-full left-1/2 -translate-x-1/2 mb-1 px-2 py-1 text-xs bg-gray-900 text-white rounded whitespace-nowrap"
        role="tooltip"
      >
        {@label}
        <div class="absolute top-full left-1/2 -translate-x-1/2 w-0 h-0 border-4 border-t-gray-900 border-x-transparent border-b-transparent" />
      </div>
    </div>
    """
  end

  @doc """
  Renders a geographic range map showing US and Canadian states/provinces.

  Uses D3.js for SVG-based choropleth rendering. Displays regions in green if
  in range, coral if excluded, and white otherwise.

  ## Examples

      <.range_map in_range={["CA", "TX", "NY"]} />

      <.range_map in_range={["CA", "TX"]} excluded_range={["AZ"]} />

      <.range_map in_range={@places} editable on_toggle={JS.push("toggle_region")} />
  """
  attr :in_range, :list,
    required: true,
    doc: "list of postal codes in range (e.g., [\"CA\", \"TX\"])"

  attr :excluded_range, :list,
    default: [],
    doc: "list of postal codes explicitly excluded"

  attr :editable, :boolean,
    default: false,
    doc: "whether regions are clickable for editing"

  attr :id, :string,
    default: "range-map",
    doc: "unique id for the map element"

  attr :class, :any,
    default: nil,
    doc: "additional CSS classes"

  def range_map(assigns) do
    in_range_json = Jason.encode!(assigns.in_range)
    excluded_range_json = Jason.encode!(assigns.excluded_range)

    assigns =
      assigns
      |> assign(:in_range_json, in_range_json)
      |> assign(:excluded_range_json, excluded_range_json)

    ~H"""
    <div
      id={@id}
      class={["relative", @class]}
      phx-hook="RangeMap"
      phx-update="ignore"
      data-in-range={@in_range_json}
      data-excluded-range={@excluded_range_json}
      data-editable={to_string(@editable)}
    >
      <div class="flex items-center justify-center p-8 text-gray-500">
        <.icon name="ph-map-trifold" class="size-8 animate-pulse" />
        <span class="ml-2">{gettext("Loading map...")}</span>
      </div>
    </div>
    """
  end
end
