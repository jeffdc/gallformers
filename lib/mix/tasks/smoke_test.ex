defmodule Mix.Tasks.SmokeTest do
  @moduledoc """
  Run smoke tests against a Gallformers deployment.

  ## Usage

      mix smoke_test https://gallformers.fly.dev
      mix smoke_test https://gallformers.org

  ## Test Suite

  - Phase 1: Core health & API endpoints
  - Phase 2: Dynamic resource discovery (gall, host, genus IDs)
  - Phase 3: Public pages
  - Phase 4: Search functionality
  - Phase 5: Static assets

  Exits with code 0 if all tests pass, 1 if any fail.
  """

  use Mix.Task

  @shortdoc "Run smoke tests against a deployment"

  @timeout 10_000

  def run([base_url]) do
    execute(base_url)
  end

  def run(_) do
    print_usage()
  end

  @spec execute(String.t()) :: no_return()
  defp execute(base_url) do
    # Start necessary applications for HTTP requests
    {:ok, _} = Application.ensure_all_started(:req)

    IO.puts("Running smoke tests against #{base_url}")
    IO.puts("")

    client = Req.new(base_url: base_url, receive_timeout: @timeout, retry: false)

    # Run all checks and accumulate results
    results =
      []
      |> run_and_accumulate(client, "Health check", "/health", &check_health/1)
      |> run_and_accumulate(client, "API stats", "/api/v2/stats", &check_stats/1)

    # Phase 2: Resource discovery
    {results, gall_id} =
      run_and_accumulate_with_value(
        results,
        client,
        "Discover gall ID",
        "/api/v2/galls?limit=1",
        &discover_gall_id/1
      )

    {results, host_id} =
      run_and_accumulate_with_value(
        results,
        client,
        "Discover host ID",
        "/api/v2/hosts",
        &discover_host_id/1
      )

    {results, genus_id} =
      run_and_accumulate_with_value(
        results,
        client,
        "Discover genus ID",
        "/api/v2/families",
        &discover_genus_id(client, &1)
      )

    # Phase 3: Public pages
    results = run_and_accumulate(results, client, "Home page", "/", &check_home/1)

    results =
      if gall_id do
        run_and_accumulate(results, client, "Gall page", "/gall/#{gall_id}", &check_gall_page/1)
      else
        results
      end

    results =
      if host_id do
        run_and_accumulate(results, client, "Host page", "/host/#{host_id}", &check_host_page/1)
      else
        results
      end

    results =
      if genus_id do
        run_and_accumulate(
          results,
          client,
          "Genus page",
          "/genus/#{genus_id}",
          &check_genus_page/1
        )
      else
        results
      end

    # Phase 4: Search
    results =
      results
      |> run_and_accumulate(client, "Search API", "/api/v2/search?q=weldi", &check_search_api/1)
      |> run_and_accumulate(client, "Search UI", "/globalsearch?q=weldi", &check_search_ui/1)

    # Phase 5: Static assets - extract paths from home page
    results =
      case extract_asset_paths(client) do
        {:ok, css_path, js_path} ->
          results
          |> run_and_accumulate(client, "Static CSS", css_path, &check_css/1)
          |> run_and_accumulate(client, "Static JS", js_path, &check_js/1)

        {:error, _} ->
          # Fallback to checking if assets directory is accessible
          results
          |> run_and_accumulate(client, "Static assets", "/", &check_has_assets/1)
      end

    # Check image from gall page if we got one
    results =
      if gall_id do
        run_and_accumulate(
          results,
          client,
          "Image gallery",
          "/gall/#{gall_id}",
          &check_image_url/1
        )
      else
        results
      end

    print_summary(Enum.reverse(results))
    exit_with_code(results)
  end

  defp run_and_accumulate(results, client, name, path, check_fn) do
    {result, _value} = run_check(client, name, path, check_fn)
    [result | results]
  end

  defp run_and_accumulate_with_value(results, client, name, path, check_fn) do
    {result, value} = run_check(client, name, path, check_fn)
    {[result | results], value}
  end

  defp run_check(client, name, path, check_fn) do
    case Req.get(client, url: path) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        process_check_result(name, path, check_fn.(body))

      {:ok, %{status: status}} ->
        reason = "HTTP #{status}"
        IO.puts("✗ #{name} (#{path}) - #{reason}")
        {{:fail, name, reason}, nil}

      {:error, error} ->
        reason = format_error(error)
        IO.puts("✗ #{name} (#{path}) - #{reason}")
        {{:fail, name, reason}, nil}
    end
  end

  defp process_check_result(name, path, {:ok, value}) do
    IO.puts("✓ #{name} (#{path})#{if value, do: " → found #{format_value(value)}", else: ""}")
    {{:pass, name}, value}
  end

  defp process_check_result(name, path, {:error, reason}) do
    IO.puts("✗ #{name} (#{path}) - #{reason}")
    {{:fail, name, reason}, nil}
  end

  defp format_value(value) when is_integer(value), do: "ID #{value}"
  defp format_value(value), do: inspect(value)

  defp format_error(%{reason: :timeout}), do: "connection timeout"
  defp format_error(%{reason: :econnrefused}), do: "connection refused"
  defp format_error(%{reason: reason}), do: inspect(reason)
  defp format_error(error), do: inspect(error)

  # Check functions
  defp check_health(body) when is_binary(body) do
    if String.contains?(body, "ok") do
      {:ok, nil}
    else
      {:error, "body does not contain 'ok'"}
    end
  end

  defp check_stats(body) when is_map(body) do
    case body do
      %{"galls" => count} when is_integer(count) and count > 0 ->
        {:ok, nil}

      _ ->
        {:error, "missing or invalid galls count"}
    end
  end

  defp check_stats(_), do: {:error, "response is not JSON"}

  defp discover_gall_id(body) when is_map(body) do
    case body do
      %{"data" => [%{"id" => id} | _]} when is_integer(id) ->
        {:ok, id}

      _ ->
        {:error, "no galls found in response"}
    end
  end

  defp discover_gall_id(_), do: {:error, "response is not JSON"}

  defp discover_host_id(body) when is_map(body) do
    case body do
      %{"data" => [%{"id" => id} | _]} when is_integer(id) ->
        {:ok, id}

      _ ->
        {:error, "no hosts found in response"}
    end
  end

  defp discover_host_id(_), do: {:error, "response is not JSON"}

  defp discover_genus_id(client, body) when is_list(body) do
    case body do
      [%{"genera" => [%{"id" => genus_id} | _]} | _] when is_integer(genus_id) ->
        {:ok, genus_id}

      [%{"id" => family_id} | _] when is_integer(family_id) ->
        # First family has no genera, try fetching genera endpoint
        case Req.get(client, url: "/api/v2/genera?family_id=#{family_id}") do
          {:ok, %{status: 200, body: [%{"id" => genus_id} | _]}} when is_integer(genus_id) ->
            {:ok, genus_id}

          _ ->
            {:error, "could not fetch genus from family #{family_id}"}
        end

      _ ->
        {:error, "no families found in response"}
    end
  end

  defp discover_genus_id(_, _), do: {:error, "response is not JSON"}

  defp check_home(body) when is_binary(body) do
    if String.contains?(body, "Gallformers") do
      {:ok, nil}
    else
      {:error, "page does not contain 'Gallformers'"}
    end
  end

  defp check_gall_page(body) when is_binary(body) do
    if String.contains?(body, "Host") or String.contains?(body, "Description") do
      {:ok, nil}
    else
      {:error, "page does not contain expected content"}
    end
  end

  defp check_host_page(body) when is_binary(body) do
    # Look for scientific name pattern in title or meta description
    if body =~ ~r/[A-Z][a-z]+ [a-z]+/ and String.contains?(body, "Gallformers") do
      {:ok, nil}
    else
      {:error, "page does not contain expected content"}
    end
  end

  defp check_genus_page(body) when is_binary(body) do
    # Just verify it's not empty and contains some content
    if String.length(body) > 100 do
      {:ok, nil}
    else
      {:error, "page appears empty"}
    end
  end

  defp check_search_api(body) when is_map(body) do
    # Search API returns top-level keys like "galls", "hosts", "sources", etc.
    if Map.has_key?(body, "galls") or Map.has_key?(body, "hosts") or Map.has_key?(body, "sources") do
      {:ok, nil}
    else
      {:error, "missing expected search result keys"}
    end
  end

  defp check_search_api(_), do: {:error, "response is not JSON"}

  defp check_search_ui(body) when is_binary(body) do
    if String.length(body) > 100 do
      {:ok, nil}
    else
      {:error, "page appears empty"}
    end
  end

  defp check_css(body) when is_binary(body) do
    if String.length(body) > 100 do
      {:ok, nil}
    else
      {:error, "CSS file appears empty"}
    end
  end

  defp check_js(body) when is_binary(body) do
    if String.length(body) > 100 do
      {:ok, nil}
    else
      {:error, "JS file appears empty"}
    end
  end

  defp check_has_assets(body) when is_binary(body) do
    # Check if the page has asset links
    has_css = body =~ ~r/\/assets\/css\/app-[a-f0-9]+\.css/
    has_js = body =~ ~r/\/assets\/js\/app-[a-f0-9]+\.js/

    if has_css and has_js do
      {:ok, nil}
    else
      {:error, "page does not contain expected asset links"}
    end
  end

  defp extract_asset_paths(client) do
    case Req.get(client, url: "/") do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        css_path = Regex.run(~r/(\/assets\/css\/app-[a-f0-9]+\.css[^"']*)/, body)
        js_path = Regex.run(~r/(\/assets\/js\/app-[a-f0-9]+\.js[^"']*)/, body)

        case {css_path, js_path} do
          {[_, css], [_, js]} -> {:ok, css, js}
          _ -> {:error, "could not extract asset paths"}
        end

      _ ->
        {:error, "could not fetch home page"}
    end
  end

  defp check_image_url(body) when is_binary(body) do
    # Look for CloudFront or S3 image URL in the page
    case Regex.run(~r/https:\/\/[a-z0-9-]+\.cloudfront\.net\/[^\s"']+/, body) do
      [url | _] ->
        # Try to fetch the image
        case Req.get(url: url, receive_timeout: @timeout) do
          {:ok, %{status: 200}} ->
            {:ok, nil}

          {:ok, %{status: status}} ->
            {:error, "CloudFront URL returned HTTP #{status}"}

          {:error, error} ->
            {:error, "CloudFront URL failed: #{format_error(error)}"}
        end

      nil ->
        {:error, "no CloudFront image URL found in page"}
    end
  end

  defp print_summary(results) do
    IO.puts("")
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    total = length(results)

    passed =
      Enum.count(results, fn
        {:pass, _} -> true
        _ -> false
      end)

    failed = total - passed

    IO.puts("#{total} checks, #{passed} passed, #{failed} failed")
    IO.puts("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
  end

  @spec exit_with_code(list()) :: no_return()
  defp exit_with_code(results) do
    failed =
      Enum.any?(results, fn
        {:fail, _, _} -> true
        _ -> false
      end)

    if failed do
      System.halt(1)
    else
      System.halt(0)
    end
  end

  defp print_usage do
    IO.puts("""
    Usage: mix smoke_test <base_url>

    Example:
      mix smoke_test https://gallformers.fly.dev
      mix smoke_test https://gallformers.org
    """)
  end
end
