defmodule GallformersWeb.FilterGuideHTML do
  @moduledoc """
  The ID tool's filter guide, on the design system (matter bc0d): each
  Trait a `section` (anchored by its id, for the jump links and the ID
  page's links) listing its values with their definitions.
  """
  use GallformersWeb, :html

  alias Gallformers.Markdown

  embed_templates "filter_guide_html/*"

  def sort_by_field(items) do
    Enum.sort_by(items, & &1.field)
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :items, :list, required: true
  attr :note, :string, default: nil

  def filter_section(assigns) do
    ~H"""
    <.section id={@id} title={@title} count={length(@items)}>
      <dl class="flex flex-col gap-1.5 text-ui">
        <div :for={item <- @items}>
          <dt class="inline font-semibold text-ink">{item.field}{if item.description, do: ":"}</dt>
          <dd :if={item.description} class="inline text-ink-2">{item.description}</dd>
        </div>
      </dl>
      <p :if={@note} class="mt-3 text-meta text-muted">
        Note: {Phoenix.HTML.raw(Markdown.linkify_glossary_terms(@note))}
      </p>
    </.section>
    """
  end
end
