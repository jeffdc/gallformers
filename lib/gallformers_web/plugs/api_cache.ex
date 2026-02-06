defmodule GallformersWeb.Plugs.ApiCache do
  @moduledoc """
  Plug that adds HTTP caching headers to API responses.

  Sets `Cache-Control` and `ETag` headers on successful responses.
  Handles `If-None-Match` to return 304 Not Modified when appropriate.
  Error responses (4xx/5xx) get `Cache-Control: no-store`.
  """

  import Plug.Conn

  @max_age 3600

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> check_if_none_match()
    |> register_before_send(&set_cache_headers/1)
  end

  defp check_if_none_match(conn) do
    case get_req_header(conn, "if-none-match") do
      [etag] -> assign(conn, :if_none_match, etag)
      _ -> conn
    end
  end

  defp set_cache_headers(conn) do
    if conn.status >= 400 do
      put_resp_header(conn, "cache-control", "no-store")
    else
      etag = compute_etag(conn)
      conn = put_resp_header(conn, "cache-control", "public, max-age=#{@max_age}")
      conn = put_resp_header(conn, "etag", etag)

      if match_etag?(conn, etag) do
        conn
        |> resp(304, "")
      else
        conn
      end
    end
  end

  defp compute_etag(conn) do
    hash =
      conn.resp_body
      |> :erlang.md5()
      |> Base.encode16(case: :lower)

    ~s("#{hash}")
  end

  defp match_etag?(conn, etag) do
    case conn.assigns[:if_none_match] do
      ^etag -> true
      _ -> false
    end
  end
end
