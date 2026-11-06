defmodule GallformersWeb.KeyComponents do
  @moduledoc """
  A dichotomous key's page (design system, matter bc0d): `key_couplet`,
  each couplet with its lettered leads as a printed key sets them, and
  `key_path`, the steps taken (a bar under the header on narrow screens, a
  panel beside the key on wide ones). See docs/design-system/components.md.

  A step is `{couplet_number, lead_index, label}`; a lead is named by its
  couplet's number and its letter ("3b").
  """
  use Phoenix.Component

  import GallformersWeb.CoreComponents, only: [icon: 1]
  import GallformersWeb.ActionComponents, only: [button: 1]
  import GallformersWeb.DataDisplayComponents, only: [taxon_name: 1]
  import GallformersWeb.PageComponents, only: [panel: 1]

  alias Gallformers.Storage.Images, as: ImageStorage

  @doc ~S|A lead's letter: 0 is "a", 1 is "b"…|
  @spec letter(non_neg_integer()) :: String.t()
  def letter(index), do: <<?a + index>>

  @doc ~S|A step's name, as the page shows it: "3b".|
  @spec step_name({String.t(), non_neg_integer(), any()}) :: String.t()
  def step_name({number, lead_index, _label}), do: "#{number}#{letter(lead_index)}"

  @doc """
  The path through the key. `layout: :panel` is the "Your path" panel for
  the rail (each step with its lead's text); `layout: :bar` is the bar
  pinned under the site header on narrow screens (`data-sticky-chrome`).
  Each step goes back to its couplet (`jump_to`); Back, Start over, Copy
  link (the `?path=` link, via the CopyToClipboard hook) and, at a result,
  Copy as text (`copy_path`).
  """
  attr :layout, :atom, required: true, values: [:panel, :bar]
  attr :key, :map, required: true
  attr :path, :list, required: true
  attr :terminal, :map, default: nil
  attr :link, :string, required: true, doc: "the `?path=` link to this point"
  attr :gall_names, :map, default: %{}
  attr :class, :any, default: nil, doc: "layout only"

  def key_path(%{layout: :panel} = assigns) do
    ~H"""
    <.panel id="key-path" title="Your path" class={@class}>
      <p :if={@path == []} class="text-ui text-muted">
        Start at couplet 1: choose the lead that fits what you have.
      </p>
      <ol :if={@path != []} class="flex flex-col gap-1 text-ui">
        <li :for={{step, index} <- Enum.with_index(@path)}>
          <button
            type="button"
            phx-click="jump_to"
            phx-value-index={index}
            title={"Go back to couplet #{elem(step, 0)}"}
            class="flex w-full gap-2 rounded-ctl px-1 py-0.5 text-left hover:bg-sky-soft"
          >
            <span class="w-8 shrink-0 font-semibold text-link tabular-nums">{step_name(step)}</span>
            <span class="line-clamp-2 text-ink-2">{lead_text(@key, step)}</span>
          </button>
        </li>
      </ol>
      <div
        :if={@terminal}
        data-part="result"
        class="mt-2 rounded-ctl bg-ok-bg px-2 py-1.5 font-semibold text-ok"
      >
        <.key_result destination={@terminal} gall_names={@gall_names} />
      </div>
      <:footer :if={@path != []}>
        <div class="flex flex-col gap-1">
          <div class="flex flex-wrap gap-1">
            <.copy_buttons id="key-path-copy-link" link={@link} terminal={@terminal} />
          </div>
          <div class="flex flex-wrap gap-1"><.step_buttons /></div>
        </div>
      </:footer>
    </.panel>
    """
  end

  def key_path(%{layout: :bar} = assigns) do
    ~H"""
    <div
      id="key-path-bar"
      class={[
        "sticky top-header z-30 -mx-page-x border-b border-line bg-paper px-page-x py-2",
        @class
      ]}
      data-sticky-chrome
    >
      <div class="flex flex-wrap items-center gap-1 text-ui">
        <span class="mr-1 font-semibold text-ink-2">Your path</span>
        <span :if={@path == []} class="text-muted">Start at couplet 1.</span>
        <span :for={{step, index} <- Enum.with_index(@path)} class="flex items-center gap-1">
          <.icon :if={index > 0} name="ph-caret-right" class="size-3 text-muted" />
          <button
            type="button"
            phx-click="jump_to"
            phx-value-index={index}
            title={"Go back to couplet #{elem(step, 0)}"}
            class="rounded-ctl px-1 font-semibold text-link tabular-nums hover:bg-sky-soft"
          >
            {step_name(step)}
          </button>
        </span>
        <span :if={@terminal} class="flex items-center gap-1">
          <.icon name="ph-caret-right" class="size-3 text-muted" />
          <span class="rounded-ctl bg-ok-bg px-1.5 font-semibold text-ok">
            <.key_result destination={@terminal} gall_names={@gall_names} />
          </span>
        </span>
        <span :if={@path != []} class="ml-auto flex flex-wrap items-center gap-1">
          <.copy_buttons id="key-path-bar-copy-link" link={@link} terminal={@terminal} />
          <.step_buttons />
        </span>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :link, :string, required: true
  attr :terminal, :map, default: nil

  defp copy_buttons(assigns) do
    ~H"""
    <.button
      id={@id}
      variant="ghost"
      size="sm"
      icon="ph-link"
      phx-hook="CopyToClipboard"
      data-copy-text={@link}
      data-copy-url
      title="Copy a link that opens the key at this point"
    >
      Copy link
    </.button>
    <.button
      :if={@terminal}
      variant="ghost"
      size="sm"
      icon="ph-copy"
      phx-click="copy_path"
      title="Copy the steps, the result and the link, to paste into a note or an observation"
    >
      Copy as text
    </.button>
    """
  end

  defp step_buttons(assigns) do
    ~H"""
    <.button
      variant="ghost"
      size="sm"
      icon="ph-arrow-left"
      phx-click="back"
      title="Undo the last step"
    >
      Back
    </.button>
    <.button variant="ghost" size="sm" icon="ph-arrows-clockwise" phx-click="reset">
      Start over
    </.button>
    """
  end

  defp lead_text(key, {number, lead_index, _label}) do
    case key.couplets[number] do
      %{leads: leads} -> (Enum.at(leads, lead_index) || %{text: ""}).text
      _ -> ""
    end
  end

  @doc """
  One couplet: its number, then its leads a, b, c… each with where it goes
  at the right ("go to 4", or the result). `state` is `:active` (the
  couplet to choose at), `:visited` (chosen at; `chosen` is the lead) or
  `:unvisited` (dimmed, still choosable). A choosable lead is a `button`
  (for the keyboard) inside a row that sends `select_lead`.
  """
  attr :number, :string, required: true
  attr :couplet, :map, required: true
  attr :key_slug, :string, required: true
  attr :state, :atom, required: true, values: [:active, :visited, :unvisited]
  attr :chosen, :integer, default: nil, doc: "the chosen lead's index, when visited"
  attr :image_url_map, :map, default: %{}
  attr :gall_names, :map, default: %{}

  def key_couplet(assigns) do
    ~H"""
    <li
      id={"couplet-#{@number}"}
      data-state={@state}
      class={[
        "flex scroll-mt-header gap-3 rounded-panel border px-3 py-1 transition-opacity",
        @state == :active && "border-line border-l-4 border-l-brand bg-surface shadow-float",
        @state == :visited && "border-line bg-surface-2",
        @state == :unvisited && "border-transparent opacity-60 hover:opacity-100"
      ]}
    >
      <span class={[
        "w-8 shrink-0 pt-1 text-right font-brand text-subsection tabular-nums",
        if(@state == :unvisited, do: "text-muted", else: "text-brand")
      ]}>
        {@number}
      </span>
      <ul class="flex min-w-0 flex-1 flex-col">
        <.lead
          :for={{lead, index} <- Enum.with_index(@couplet.leads)}
          lead={lead}
          number={@number}
          index={index}
          key_slug={@key_slug}
          state={lead_state(@state, @chosen, index)}
          image_url_map={@image_url_map}
          gall_names={@gall_names}
        />
      </ul>
    </li>
    """
  end

  defp lead_state(:active, _chosen, _index), do: :active
  defp lead_state(:visited, chosen, index) when chosen == index, do: :chosen
  defp lead_state(:visited, _chosen, _index), do: :unchosen
  defp lead_state(:unvisited, _chosen, _index), do: :inactive

  attr :lead, :map, required: true
  attr :number, :string, required: true
  attr :index, :integer, required: true
  attr :key_slug, :string, required: true
  attr :state, :atom, required: true
  attr :image_url_map, :map, required: true
  attr :gall_names, :map, required: true

  defp lead(assigns) do
    assigns = assign(assigns, :choosable, assigns.state in [:active, :inactive])

    ~H"""
    <li
      phx-click={@choosable && "select_lead"}
      phx-value-couplet={@number}
      phx-value-lead={@index}
      data-state={@state}
      class={[
        "flex flex-col gap-1 rounded-ctl px-2 py-1 sm:flex-row sm:items-start sm:gap-4",
        @choosable && "cursor-pointer hover:bg-sky-soft",
        @state == :chosen && "bg-ok-bg",
        @state == :unchosen && "text-muted"
      ]}
    >
      <div class="flex min-w-0 flex-1 gap-2">
        <span class={[
          "w-4 shrink-0 font-semibold",
          if(@state == :chosen, do: "text-ok", else: "text-muted")
        ]}>
          <.icon :if={@state == :chosen} name="ph-check" class="size-4" />
          <span data-part="letter" class={@state == :chosen && "sr-only"}>{letter(@index)}</span>
        </span>
        <div class="flex min-w-0 flex-col gap-1">
          <button
            :if={@choosable}
            type="button"
            class="text-left text-body text-ink"
            aria-label={"#{@number}#{letter(@index)}: #{@lead.text}"}
          >
            {@lead.text}
          </button>
          <p :if={!@choosable} class={["text-body", @state == :chosen && "text-ink"]}>{@lead.text}</p>
          <p :if={@lead[:notes]} class="text-meta text-muted">{@lead.notes}</p>
          <div :if={@lead.images != []} class="flex flex-wrap gap-2">
            <figure :for={image <- @lead.images} class="m-0">
              <img
                src={image_url(image, @key_slug, @image_url_map)}
                alt={image.caption || image.ref}
                class="max-h-32 rounded-ctl border border-line object-contain"
                loading="lazy"
              />
              <figcaption :if={image.ref} class="text-caption text-muted">{image.ref}</figcaption>
            </figure>
          </div>
        </div>
      </div>
      <div class="shrink-0 pl-6 text-ui sm:max-w-64 sm:pl-0 sm:text-right">
        <%= case @lead.destination.type do %>
          <% "couplet" -> %>
            <span class={["tabular-nums", @state != :unchosen && "text-ink-2"]}>
              <span :if={@lead.destination[:label]} class="font-semibold">
                {@lead.destination.label}
              </span>
              go to {@lead.destination.number}
            </span>
          <% "taxon" -> %>
            <span class="flex flex-col sm:items-end">
              <span class={["font-semibold", @state != :unchosen && "text-ink"]}>
                <.key_result destination={@lead.destination} gall_names={@gall_names} />
              </span>
              <span :if={@lead.destination[:context]} class="text-meta text-muted">
                {@lead.destination.context}
              </span>
            </span>
          <% _ -> %>
        <% end %>
      </div>
    </li>
    """
  end

  @doc """
  A result: the taxon's name, linked to its Gall; a result that covers
  several Galls names each one, linked (`gall_names`: Gall id => name).
  """
  attr :destination, :map, required: true
  attr :gall_names, :map, default: %{}

  def key_result(assigns) do
    assigns = assign(assigns, :ids, assigns.destination[:species_ids] || [])

    ~H"""
    <%= case @ids do %>
      <% [id] -> %>
        <a href={"/gall/#{id}"}><.taxon_name name={@destination.name} rank="auto" /></a>
      <% [_ | _] -> %>
        <span class="inline-flex flex-col sm:items-end">
          <.taxon_name name={@destination.name} rank="auto" />
          <span class="text-meta font-normal">
            <span :for={{id, i} <- Enum.with_index(@ids)}>
              {if i > 0, do: " · "}<a href={"/gall/#{id}"}><i>{@gall_names[id] || "Gall #{id}"}</i></a>
            </span>
          </span>
        </span>
      <% _ -> %>
        <.taxon_name name={@destination.name} rank="auto" />
    <% end %>
    """
  end

  # A lead's image: an uploaded content image, or a legacy file under the key.
  defp image_url(%{content_image_id: id}, _key_slug, image_url_map) when is_integer(id),
    do: Map.get(image_url_map, id, "")

  defp image_url(%{file: filename}, key_slug, _image_url_map) when is_binary(filename),
    do: ImageStorage.public_url("keys/#{key_slug}/#{filename}")

  defp image_url(_, _, _), do: ""
end
