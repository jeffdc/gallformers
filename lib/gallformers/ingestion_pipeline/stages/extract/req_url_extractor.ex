defmodule Gallformers.IngestionPipeline.Stages.Extract.ReqURLExtractor do
  @moduledoc """
  Default URL extractor for ingestion submissions.

  Fetches the URL with `Req` and reduces HTML to plain text when necessary.
  """
  alias Floki

  @behaviour Gallformers.IngestionPipeline.Stages.Extract.URLExtractor

  @user_agent "GallformersBot/1.0 (+https://gallformers.com)"

  @impl true
  def extract_text(url) when is_binary(url) do
    url = String.trim(url)

    with :ok <- validate_url(url),
         {:ok, %Req.Response{status: status, body: body, headers: headers}}
         when status in 200..299 <-
           req_client().get(url,
             headers: [{"user-agent", @user_agent}],
             receive_timeout: receive_timeout()
           ) do
      {:ok, %{text: response_text(body, headers)}}
    else
      {:ok, %Req.Response{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, %Req.TransportError{reason: reason}} ->
        {:error, {:request_failed, reason}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def extract_text(_), do: {:error, :invalid_url}

  defp validate_url(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        :ok

      _ ->
        {:error, :invalid_url}
    end
  end

  defp response_text(body, headers) when is_binary(body) do
    if html_response?(headers) do
      body
      |> remove_html_noise()
      |> strip_html_tags()
      |> normalize_whitespace()
    else
      normalize_whitespace(body)
    end
  end

  defp html_response?(headers) do
    headers
    |> List.wrap()
    |> Enum.any?(fn
      {"content-type", value} -> String.contains?(String.downcase(value), "html")
      {"Content-Type", value} -> String.contains?(String.downcase(value), "html")
      _ -> false
    end)
  end

  defp remove_html_noise(html) do
    # Floki.text/1 already ignores script, style, noscript content
    Floki.text(Floki.parse_document!(html))
  end

  defp strip_html_tags(html) do
    html
    |> Floki.text()
    |> normalize_whitespace()
  end

  defp normalize_whitespace(text) do
    text
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp req_client do
    :gallformers
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:req_client, Req)
  end

  defp receive_timeout do
    :gallformers
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:receive_timeout, 15_000)
  end
end
