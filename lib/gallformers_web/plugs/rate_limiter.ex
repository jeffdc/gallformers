defmodule GallformersWeb.Plugs.RateLimiter do
  @moduledoc """
  Rate limiting plug for API routes.

  Limits requests to 100 per minute per IP address (`:limit` in the
  plug's config; the tests, all from one address, raise it).
  Returns 429 Too Many Requests with Retry-After header when exceeded.
  """

  import Plug.Conn

  @rate_limit Application.compile_env(:gallformers, [__MODULE__, :limit], 100)
  @scale_ms :timer.minutes(1)

  def init(opts), do: opts

  def call(conn, _opts) do
    client_ip = get_client_ip(conn)

    case check_rate(client_ip) do
      {:allow, _count} ->
        conn

      {:deny, _limit} ->
        conn
        |> put_resp_header("retry-after", "60")
        |> put_resp_content_type("application/json")
        |> send_resp(429, Jason.encode!(%{error: "Rate limit exceeded. Try again later."}))
        |> halt()
    end
  end

  defp get_client_ip(conn) do
    # Check for forwarded headers first (for reverse proxy setups)
    forwarded_for =
      conn
      |> get_req_header("x-forwarded-for")
      |> List.first()

    case forwarded_for do
      nil ->
        conn.remote_ip |> :inet.ntoa() |> to_string()

      forwarded ->
        forwarded
        |> String.split(",")
        |> List.first()
        |> String.trim()
    end
  end

  defp check_rate(client_ip) do
    bucket = "api:#{client_ip}"

    case Hammer.check_rate(bucket, @scale_ms, @rate_limit) do
      {:allow, count} -> {:allow, count}
      {:deny, limit} -> {:deny, limit}
    end
  end
end
