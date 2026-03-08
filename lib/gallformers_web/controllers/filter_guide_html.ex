defmodule GallformersWeb.FilterGuideHTML do
  use GallformersWeb, :html

  alias Gallformers.Markdown

  embed_templates "filter_guide_html/*"

  def sort_by_field(items) do
    Enum.sort_by(items, & &1.field)
  end

  attr :href, :string, required: true
  slot :inner_block, required: true

  def jump_link(assigns) do
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

  def filter_section(assigns) do
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
