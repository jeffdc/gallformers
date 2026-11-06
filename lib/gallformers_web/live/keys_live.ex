defmodule GallformersWeb.KeysLive do
  @moduledoc """
  The identification keys list (design system, matter bc0d): each key's
  title, scope, couplet count, authors and description.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Keys

  @impl true
  def mount(_params, _session, socket) do
    keys = Keys.list_keys()

    {:ok,
     assign(socket,
       page_title: "Identification Keys",
       page_description: "Dichotomous identification keys for gall-associated organisms.",
       page_url: "/keys",
       page_image: nil,
       page_json_ld: nil,
       keys: keys
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-section">
        <.page_header>
          <:title>Identification keys</:title>
          <:description>
            Step-by-step keys: at each couplet, choose the lead that fits what you have.
          </:description>
        </.page_header>

        <.empty_state :if={@keys == []} title="No keys yet" />

        <ol :if={@keys != []} class="flex max-w-text flex-col divide-y divide-line">
          <li :for={key <- @keys} class="flex flex-col gap-1 py-4 first:pt-0">
            <h2 class="text-subsection">
              <.link navigate={~p"/keys/#{key.slug}"}>{key.title}</.link>
            </h2>
            <p class="text-meta text-muted">
              {Enum.join(
                Enum.reject(
                  [
                    key.subtitle,
                    "#{key.couplet_count} couplets",
                    key.authors != [] && Enum.join(key.authors, ", ")
                  ],
                  &(&1 in [nil, false])
                ),
                " · "
              )}
            </p>
            <p :if={key.description} class="line-clamp-2 text-ui text-ink-2">{key.description}</p>
          </li>
        </ol>
      </div>
    </Layouts.app>
    """
  end
end
