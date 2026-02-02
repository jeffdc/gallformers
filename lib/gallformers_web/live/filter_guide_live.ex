defmodule GallformersWeb.FilterGuideLive do
  @moduledoc """
  LiveView for the filter guide page.

  Displays explanations for all filter terms used in the ID tool.
  """
  use GallformersWeb, :live_view

  alias Gallformers.IDTool
  alias Gallformers.Markdown

  @impl true
  def mount(_params, _session, socket) do
    filter_fields = %{
      alignment:
        IDTool.list_alignments() |> Enum.map(&%{field: &1.alignment, description: &1.description}),
      cells: IDTool.list_cells() |> Enum.map(&%{field: &1.cells, description: &1.description}),
      form: IDTool.list_forms() |> Enum.map(&%{field: &1.form, description: &1.description}),
      plant_part:
        IDTool.list_plant_parts() |> Enum.map(&%{field: &1.part, description: &1.description}),
      shape: IDTool.list_shapes() |> Enum.map(&%{field: &1.shape, description: &1.description}),
      texture:
        IDTool.list_textures() |> Enum.map(&%{field: &1.texture, description: &1.description}),
      walls: IDTool.list_walls() |> Enum.map(&%{field: &1.walls, description: &1.description})
    }

    {:ok,
     assign(socket,
       page_title: "Filter Guide",
       page_description:
         "Guide to the filter terms used in the Gallformers gall identification tool - explanations of alignment, cells, forms, plant part, shape, texture, and walls.",
       page_url: "/filterguide",
       page_image: nil,
       page_json_ld: nil,
       filter_fields: filter_fields
     )}
  end

  defp sort_by_field(items) do
    Enum.sort_by(items, & &1.field)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="max-w-4xl">
        <h1 class="text-3xl font-bold text-gf-maroon mb-2">ID Tool Filter Guide</h1>
        <p class="text-gray-600 mb-6">
          This guide explains the filter terms used in our gall identification tool.
        </p>

        <%!-- Jump links --%>
        <nav class="mb-8 flex flex-wrap gap-2">
          <.jump_link href="#alignment">Alignment</.jump_link>
          <.jump_link href="#cells">Cells</.jump_link>
          <.jump_link href="#detachable">Detachable</.jump_link>
          <.jump_link href="#forms">Forms</.jump_link>
          <.jump_link href="#plant_part">Plant Part</.jump_link>
          <.jump_link href="#shape">Shape</.jump_link>
          <.jump_link href="#texture">Texture</.jump_link>
          <.jump_link href="#walls">Walls</.jump_link>
        </nav>

        <div class="space-y-8">
          <%!-- Alignment --%>
          <.filter_section
            id="alignment"
            title="Alignment"
            items={sort_by_field(@filter_fields.alignment)}
          />

          <%!-- Cells --%>
          <.filter_section
            id="cells"
            title="Cells"
            items={sort_by_field(@filter_fields.cells)}
            note="If multiple larvae are found in one space, these may be inquilines rather than gall-inducers."
          />

          <%!-- Detachable (hardcoded values) --%>
          <section id="detachable">
            <h2 class="text-xl font-semibold text-gf-maroon mb-3 border-b border-gray-200 pb-2">
              Detachable
            </h2>
            <dl class="space-y-2">
              <div>
                <dt class="inline font-medium text-gray-900">Yes</dt>
                <dd class="inline text-gray-700">
                  – the gall could be removed from the plant without destroying the tissue it's attached to (detachable).
                </dd>
              </div>
              <div>
                <dt class="inline font-medium text-gray-900">No</dt>
                <dd class="inline text-gray-700">
                  – the gall could only be removed from the plant by destroying the tissue it's attached to (integral).
                </dd>
              </div>
            </dl>
            <p class="mt-3 text-sm text-gray-600 italic">
              Note: Galls that have detachable parts but leave some galled tissue behind (more than a scar
              or blister), are only detachable in some parts of the season, or may be detachable or not, are
              included in both terms.
            </p>
          </section>

          <%!-- Forms --%>
          <.filter_section id="forms" title="Forms" items={sort_by_field(@filter_fields.form)} />

          <%!-- Plant Part --%>
          <.filter_section
            id="plant_part"
            title="Plant Part"
            items={sort_by_field(@filter_fields.plant_part)}
          />

          <%!-- Shape --%>
          <.filter_section id="shape" title="Shape" items={sort_by_field(@filter_fields.shape)} />

          <%!-- Texture --%>
          <.filter_section id="texture" title="Texture" items={sort_by_field(@filter_fields.texture)} />

          <%!-- Walls --%>
          <.filter_section id="walls" title="Walls" items={sort_by_field(@filter_fields.walls)} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :href, :string, required: true
  slot :inner_block, required: true

  defp jump_link(assigns) do
    ~H"""
    <a
      href={@href}
      class="px-3 py-1.5 text-sm font-medium bg-gray-100 text-gray-700 rounded-full border border-gray-200 hover:bg-gf-maroon hover:border-gf-maroon hover:!text-white transition-colors"
    >
      {render_slot(@inner_block)}
    </a>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :items, :list, required: true
  attr :note, :string, default: nil

  defp filter_section(assigns) do
    ~H"""
    <section id={@id}>
      <h2 class="text-xl font-semibold text-gf-maroon mb-3 border-b border-gray-200 pb-2">
        {@title}
      </h2>
      <dl class="space-y-2">
        <div :for={item <- @items}>
          <dt class="inline font-medium text-gray-900">{item.field}</dt>
          <dd :if={item.description} class="inline text-gray-700">– {item.description}</dd>
        </div>
      </dl>
      <%= if @note do %>
        <p class="mt-3 text-sm text-gray-600 italic">
          Note: {Phoenix.HTML.raw(Markdown.linkify_glossary_terms(@note))}
        </p>
      <% end %>
    </section>
    """
  end
end
