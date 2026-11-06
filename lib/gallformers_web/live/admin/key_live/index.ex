defmodule GallformersWeb.Admin.KeyLive.Index do
  @moduledoc """
  The identification keys admin list (design system matter bc0d, the admin
  list pattern): every key with its slug, version, couplet count and public
  page. Deleting is on the edit page.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Keys

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:current_user, session["current_user"])
     |> assign(:page_title, "Keys")
     |> assign(:keys, Keys.list_keys())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_user={@current_user}>
      <div class="flex flex-col gap-section">
        <.page_header>
          <:title>Keys</:title>
          <:meta label="Keys">{length(@keys)}</:meta>
          <:description>
            Dichotomous identification keys, each a set of couplets, shown on the site's Keys page.
          </:description>
          <:action>
            <.button navigate={~p"/admin/keys/new"} variant="primary" icon="ph-plus">
              New key
            </.button>
          </:action>
        </.page_header>

        <.data_table id="keys" rows={@keys} row_id={&"keys-#{&1.id}"}>
          <:col :let={key} label="Title" grow>
            <.link navigate={~p"/admin/keys/#{key.id}"} class="font-semibold">{key.title}</.link>
            <span :if={key.subtitle} class="ml-2 text-meta text-muted">{key.subtitle}</span>
          </:col>
          <:col :let={key} label="Slug" hide_below={:md}>
            <span class="font-mono text-meta text-ink-2">{key.slug}</span>
          </:col>
          <:col :let={key} label="Version" hide_below={:md}>
            <span class="text-meta text-ink-2">{key.version}</span>
          </:col>
          <:col :let={key} label="Couplets" numeric>
            <span data-couplets>{key.couplet_count}</span>
          </:col>
          <:col :let={key} label="On the site">
            <.link href={~p"/keys/#{key.slug}"} target="_blank">View ↗</.link>
          </:col>
          <:empty>No keys yet. Start one with New key.</:empty>
        </.data_table>
      </div>
    </Layouts.admin>
    """
  end
end
