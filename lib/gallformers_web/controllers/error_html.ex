defmodule GallformersWeb.ErrorHTML do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.

  See config/config.exs. The 403, 404 and 500 pages are design-system pages
  (`error_page/1`); they stand alone, without the site shell, because the
  shell's data may be what failed.
  """
  use GallformersWeb, :html

  embed_templates "error_html/*"

  @doc """
  A standalone error page: the head (title, description, Open Graph), the
  stylesheet, the wordmark linking home, the status, a title, what happened
  and the ways on.
  """
  attr :status, :string, required: true
  attr :title, :string, required: true, doc: "the page title and its head title"
  attr :description, :string, required: true, doc: "the head description"
  attr :heading, :string, default: nil, doc: "the page's h1, when it differs from the title"
  attr :back, :string, default: nil, doc: "where Go Back goes (`back_href/1`); nil for none"
  slot :inner_block, required: true, doc: "what happened"
  slot :figure, doc: "an image under the message"
  slot :actions, required: true

  def error_page(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" data-theme="light">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{@title} | Gallformers</title>
        <meta name="description" content={@description} />
        <meta property="og:title" content={"#{@title} | Gallformers"} />
        <meta property="og:description" content={@description} />
        <meta property="og:type" content="website" />
        <meta property="og:image" content="https://gallformers.org/images/cynipid_R.svg" />
        <meta property="og:site_name" content="Gallformers" />
        <link rel="icon" href="/favicon.ico" />
        <link rel="stylesheet" href={~p"/assets/css/app.css"} />
      </head>
      <body class="min-h-screen bg-paper text-ink">
        <header class="bg-sky">
          <div class="mx-auto flex h-16 max-w-page items-center px-4 sm:px-page-x">
            <a href="/" aria-label="Gallformers home">
              <img
                src="/branding/Wide Logo Versions/gallformers_logo_wide_color.png"
                alt="Gallformers logo: an oak gall wasp with a spherical oak gall and a white oak leaf"
                class="h-12 w-auto"
              />
            </a>
          </div>
        </header>
        <main class="mx-auto flex max-w-text flex-col items-center gap-4 px-4 py-16 text-center">
          <p class="font-brand text-page text-brand tabular-nums">{@status}</p>
          <h1 class="text-section">{@heading || @title}</h1>
          <p class="text-lead text-ink-2">{render_slot(@inner_block)}</p>
          {render_slot(@figure)}
          <div class="mt-2 flex flex-wrap justify-center gap-3">
            <.button :if={@back} href={@back} variant="primary">Go Back</.button>
            {render_slot(@actions)}
          </div>
        </main>
      </body>
    </html>
    """
  end

  @doc """
  Where Go Back goes: the page the visitor came from (the request's
  `Referer`), when it is a web address; nil otherwise (a bookmark, a typed
  address), and the page has no Go Back. A link, not `history.back()`, so
  the page runs no script (the CSP allows none inline).
  """
  @spec back_href(map()) :: String.t() | nil
  def back_href(%{conn: %Plug.Conn{} = conn}) do
    case Plug.Conn.get_req_header(conn, "referer") do
      [referer | _] -> if web_address?(referer), do: referer
      [] -> nil
    end
  end

  def back_href(_assigns), do: nil

  defp web_address?(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        true

      _ ->
        false
    end
  end
end
