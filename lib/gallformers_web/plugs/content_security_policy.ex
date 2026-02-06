defmodule GallformersWeb.Plugs.ContentSecurityPolicy do
  @moduledoc """
  Sets Content-Security-Policy-Report-Only header with per-request nonces.

  Generates a random nonce for each request and includes it in the CSP header's
  script-src directive. The nonce is stored in `conn.assigns.csp_nonce` for use
  in templates (e.g., `<script nonce={@csp_nonce}>`).

  In dev, adds `frame-src 'self'` to allow the Phoenix LiveReloader iframe.

  Running in report-only mode to identify violations without breaking anything.
  Once validated in production, switch to enforcing by changing the header name
  to "content-security-policy".
  """

  import Plug.Conn

  @cdn_url Application.compile_env(:gallformers, :images)[:cdn_url]
  @env Application.compile_env(:gallformers, :env)

  @base_directives [
    "default-src 'none'",
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' #{@cdn_url} data:",
    "font-src 'self'",
    "connect-src 'self' https://*.s3.amazonaws.com",
    "form-action 'self'",
    "frame-ancestors 'none'",
    "manifest-src 'self'",
    "base-uri 'self'",
    "object-src 'none'"
  ]

  @dev_directives if(@env == :dev, do: ["frame-src 'self'"], else: [])

  def init(opts), do: opts

  def call(conn, _opts) do
    nonce = generate_nonce()

    policy =
      [
        "script-src 'self' 'nonce-#{nonce}'"
        | @base_directives ++ @dev_directives
      ]
      |> Enum.join("; ")

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header("content-security-policy-report-only", policy)
  end

  defp generate_nonce do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
