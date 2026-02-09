defmodule GallformersWeb.KeyComponents do
  @moduledoc """
  Components for rendering dichotomous identification keys.
  """
  use Phoenix.Component

  alias Gallformers.Storage

  @doc """
  Renders the path tracker showing the user's navigation history through the key.

  Shows breadcrumb-style steps: "1 → 2 → Ichneumonoidea → 4 → Ichneumonidae".
  Each step is clickable to jump back to that point.
  """
  attr :path, :list, required: true, doc: "list of {couplet_number, lead_index, label} tuples"
  attr :terminal, :map, default: nil, doc: "terminal taxon if reached"

  def path_tracker(assigns) do
    ~H"""
    <div
      :if={@path != []}
      class="sticky top-[78px] z-40 bg-white/95 backdrop-blur-sm border-b border-gray-200 px-4 py-2"
    >
      <div class="mx-auto max-w-4xl flex items-center gap-1 flex-wrap text-sm">
        <span class="text-gray-500 font-medium mr-1">Path:</span>

        <span :for={{step, index} <- Enum.with_index(@path)} class="flex items-center gap-1">
          <span :if={index > 0} class="text-gray-400">→</span>
          <button
            phx-click="jump_to"
            phx-value-index={index}
            class="text-gf-maroon hover:underline font-medium"
          >
            {step_label(step)}
          </button>
        </span>

        <span :if={@terminal} class="flex items-center gap-1">
          <span class="text-gray-400">→</span>
          <span class={[
            "font-bold text-gf-maroon",
            if(italicize_taxon?(@terminal.name), do: "italic")
          ]}>
            {@terminal.name}
          </span>
        </span>

        <button
          phx-click="reset"
          class="ml-auto text-xs text-gray-500 hover:text-gf-maroon hover:underline"
        >
          Start over
        </button>
      </div>
    </div>
    """
  end

  defp step_label({couplet_number, _lead_index, label}) when is_binary(label) do
    "#{label} — #{couplet_number}"
  end

  defp step_label({couplet_number, _lead_index, _label}) do
    couplet_number
  end

  @doc """
  Renders a single couplet with its leads.
  """
  attr :number, :string, required: true
  attr :couplet, :map, required: true
  attr :key_slug, :string, required: true
  attr :state, :atom, required: true, doc: ":active | :visited | :unvisited"
  attr :chosen_lead_index, :integer, default: nil

  def couplet(assigns) do
    ~H"""
    <div
      id={"couplet-#{@number}"}
      class={[
        "rounded-lg border transition-all duration-300",
        couplet_classes(@state)
      ]}
    >
      <div class="flex items-start gap-4 p-4">
        <span class={[
          "text-2xl font-bold shrink-0 w-10 text-right",
          if(@state == :unvisited, do: "text-gray-400", else: "text-gf-maroon")
        ]}>
          {@number}.
        </span>

        <div class="flex-1 space-y-4">
          <.lead
            :for={{lead, index} <- Enum.with_index(@couplet.leads)}
            lead={lead}
            couplet_number={@number}
            lead_index={index}
            key_slug={@key_slug}
            state={lead_state(@state, @chosen_lead_index, index)}
          />
        </div>
      </div>
    </div>
    """
  end

  # Genus and species names are italicized; family (-idae), subfamily (-inae),
  # superfamily (-oidea), and tribe (-ini/-ina) names are not.
  defp italicize_taxon?(name) do
    first_word = name |> String.split(~r/[\s(]/, parts: 2) |> hd()

    not String.match?(first_word, ~r/(oidea|idae|inae|ini|ina)$/i)
  end

  defp couplet_classes(:active), do: "border-gf-maroon border-l-4 bg-white shadow-md"
  defp couplet_classes(:visited), do: "border-gray-200 bg-gray-50"
  defp couplet_classes(:unvisited), do: "border-gray-200 bg-white opacity-50"

  defp lead_state(:active, _chosen, _index), do: :active
  defp lead_state(:visited, chosen, index) when chosen == index, do: :chosen
  defp lead_state(:visited, _chosen, _index), do: :unchosen
  defp lead_state(:unvisited, _chosen, _index), do: :inactive

  @doc """
  Renders a single lead (choice) within a couplet.
  """
  attr :lead, :map, required: true
  attr :couplet_number, :string, required: true
  attr :lead_index, :integer, required: true
  attr :key_slug, :string, required: true
  attr :state, :atom, required: true, doc: ":active | :chosen | :unchosen | :inactive"

  def lead(assigns) do
    ~H"""
    <div
      class={[
        "rounded-md p-3 transition-all duration-200",
        lead_classes(@state)
      ]}
      phx-click={if @state in [:active, :inactive], do: "select_lead"}
      phx-value-couplet={@couplet_number}
      phx-value-lead={@lead_index}
    >
      <div class="flex flex-col lg:flex-row lg:items-start gap-3">
        <%!-- Lead text and destination --%>
        <div class="flex-1">
          <div class="flex items-start gap-2">
            <span class={[
              "mt-1 shrink-0",
              if(@state == :chosen, do: "text-green-600", else: "text-gray-400")
            ]}>
              <%= if @state == :chosen do %>
                ✓
              <% else %>
                –
              <% end %>
            </span>

            <div class="flex-1">
              <p class={[
                "leading-relaxed",
                if(@state == :unchosen, do: "text-gray-400", else: "text-gray-800")
              ]}>
                {@lead.text}
              </p>
            </div>
          </div>

          <%!-- Destination indicator --%>
          <div class="mt-2 ml-6">
            <.destination_badge destination={@lead.destination} state={@state} />
          </div>
        </div>

        <%!-- Images --%>
        <.lead_images
          :if={@lead.images != []}
          images={@lead.images}
          key_slug={@key_slug}
          state={@state}
        />
      </div>
    </div>
    """
  end

  defp lead_classes(:active), do: "hover:bg-gray-100 cursor-pointer"
  defp lead_classes(:chosen), do: "bg-green-50 border border-green-200"
  defp lead_classes(:unchosen), do: "opacity-50"
  defp lead_classes(:inactive), do: "hover:bg-gray-50 cursor-pointer"

  @doc """
  Renders the destination badge for a lead.
  """
  attr :destination, :map, required: true
  attr :state, :atom, required: true

  def destination_badge(assigns) do
    ~H"""
    <%= case @destination.type do %>
      <% "couplet" -> %>
        <span class={[
          "inline-flex items-center gap-1 text-sm",
          if(@state == :unchosen, do: "text-gray-400", else: "text-gray-600")
        ]}>
          <%= if @destination[:label] do %>
            <span class="font-medium">{@destination.label}</span> —
          <% end %>
          → {@destination.number}
        </span>
      <% "taxon" -> %>
        <span class={[
          "inline-flex items-center gap-1 font-bold",
          if(@state == :unchosen, do: "text-gray-400", else: "text-gf-maroon")
        ]}>
          <span class={if(italicize_taxon?(@destination.name), do: "italic")}>
            {@destination.name}
          </span>
          <span :if={@destination[:context]} class="text-sm font-normal text-gray-500">
            ({@destination.context})
          </span>
        </span>
      <% _ -> %>
        <span></span>
    <% end %>
    """
  end

  @doc """
  Renders images for a lead.
  """
  attr :images, :list, required: true
  attr :key_slug, :string, required: true
  attr :state, :atom, required: true

  def lead_images(assigns) do
    ~H"""
    <div class={[
      "flex gap-2 shrink-0",
      if(@state == :unchosen, do: "opacity-40")
    ]}>
      <div :for={image <- @images} class="relative">
        <img
          src={key_image_url(@key_slug, image.file)}
          alt={image.caption || image.ref}
          class="max-w-[150px] max-h-[120px] rounded shadow-sm object-contain"
          loading="lazy"
        />
        <span
          :if={image.ref}
          class="absolute bottom-0 left-0 bg-black/60 text-white text-xs px-1 rounded-tr"
        >
          {image.ref}
        </span>
      </div>
    </div>
    """
  end

  defp key_image_url(key_slug, filename) do
    "#{Storage.cdn_url()}/keys/#{key_slug}/#{filename}"
  end
end
