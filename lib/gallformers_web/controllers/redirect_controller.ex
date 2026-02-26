defmodule GallformersWeb.RedirectController do
  @moduledoc """
  Handles 301 redirects from legacy URLs to their new canonical locations.
  """
  use GallformersWeb, :controller

  @doc """
  Redirects /refindex to /articles
  """
  def articles(conn, _params) do
    # Preserve any query params (e.g., ?tag=...)
    query_string = conn.query_string

    path =
      if query_string == "" do
        "/articles"
      else
        "/articles?#{query_string}"
      end

    conn
    |> put_status(:moved_permanently)
    |> redirect(to: path)
  end

  @doc """
  Redirects /ref/:slug to /articles/:slug
  """
  def article(conn, %{"slug" => slug}) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: "/articles/#{slug}")
  end

  @doc """
  Redirects /places to /explore?tab=places
  """
  def places(conn, _params) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: "/explore?tab=places")
  end
end
