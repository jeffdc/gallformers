defmodule Gallformers.INaturalist do
  @moduledoc """
  Context for interacting with the iNaturalist API.

  Handles observation fetching, photo downloading, URL parsing, and
  license mapping between iNat and Gallformers formats.
  """
  use Boundary, deps: [], exports: :all

  require Logger

  alias Gallformers.INaturalist.{Observation, Photo}

  @api_base "https://api.inaturalist.org/v1"
  @user_agent "Gallformers/1.0 (gallformers.org)"

  @license_map %{
    "cc0" => "Public Domain / CC0",
    "cc-by" => "CC-BY",
    "cc-by-sa" => "CC-BY-SA",
    "cc-by-nc" => "CC-BY-NC",
    "cc-by-nc-sa" => "CC-BY-NC-SA",
    "cc-by-nd" => "CC-BY-ND",
    "cc-by-nc-nd" => "CC-BY-NC-ND"
  }

  @observation_url_pattern ~r{https?://(?:www\.)?inaturalist\.org/observations/(\d+)}

  @doc """
  Maps an iNat `license_code` to a Gallformers license string.
  Returns "All Rights Reserved" for nil (no license).
  """
  @spec map_license(String.t() | nil) :: String.t()
  def map_license(nil), do: "All Rights Reserved"
  def map_license(code), do: Map.get(@license_map, code, "All Rights Reserved")

  @doc """
  Parses an iNaturalist observation URL or bare ID into an observation ID.
  """
  @spec parse_observation_id(String.t()) :: {:ok, String.t()} | {:error, :invalid_input}
  def parse_observation_id(input) when is_binary(input) do
    input = String.trim(input)

    cond do
      input == "" ->
        {:error, :invalid_input}

      Regex.match?(~r/^\d+$/, input) ->
        {:ok, input}

      match = Regex.run(@observation_url_pattern, input) ->
        {:ok, Enum.at(match, 1)}

      true ->
        {:error, :invalid_input}
    end
  end

  @doc """
  Fetches an iNaturalist observation by URL or ID.
  Returns `{:ok, Observation.t()}` or `{:error, reason}`.
  """
  @spec fetch_observation(String.t()) :: {:ok, Observation.t()} | {:error, atom()}
  def fetch_observation(input) do
    with {:ok, id} <- parse_observation_id(input),
         {:ok, json} <- do_fetch_observation(id) do
      parse_observation_response(json)
    end
  end

  @doc """
  Downloads a photo from the given URL. Returns `{:ok, binary}` or `{:error, reason}`.
  """
  @spec download_photo(String.t()) :: {:ok, binary()} | {:error, term()}
  def download_photo(url) do
    case Req.get(url, request_options()) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Parses a raw iNat API observation response into an Observation struct.
  """
  @spec parse_observation_response(map()) :: {:ok, Observation.t()} | {:error, :not_found}
  def parse_observation_response(%{"results" => [raw | _]}) do
    photos =
      (raw["photos"] || [])
      |> Enum.map(fn p ->
        license_code = p["license_code"]
        mapped = map_license(license_code)

        %Photo{
          id: p["id"],
          thumbnail_url: photo_size_url(p["url"], "medium"),
          original_url: photo_size_url(p["url"], "original"),
          license_code: license_code,
          mapped_license: mapped,
          all_rights_reserved?: license_code == nil
        }
      end)

    obs = %Observation{
      id: raw["id"],
      taxon_id: get_in(raw, ["taxon", "id"]),
      taxon_name: get_in(raw, ["taxon", "name"]),
      observer_login: get_in(raw, ["user", "login"]),
      observer_name: get_in(raw, ["user", "name"]),
      url: "https://www.inaturalist.org/observations/#{raw["id"]}",
      observed_on: observed_on(raw["observed_on"]),
      place_guess: raw["place_guess"],
      place_ids: Enum.filter(raw["place_ids"] || [], &is_integer/1),
      description: raw["description"],
      quality_grade: raw["quality_grade"],
      field_values: Enum.map(raw["ofvs"] || [], &field_value/1),
      photos: photos
    }

    {:ok, obs}
  end

  def parse_observation_response(%{"results" => []}), do: {:error, :not_found}
  def parse_observation_response(_), do: {:error, :invalid_response}

  defp observed_on(text) when is_binary(text) do
    case Date.from_iso8601(String.slice(text, 0, 10)) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp observed_on(_text), do: nil

  # An observation field value: a taxon field ("Host Plant ID") gives its
  # taxon's name.
  defp field_value(ofv) do
    %{
      name: ofv["name"],
      value: ofv["value"] && to_string(ofv["value"]),
      taxon_name: get_in(ofv, ["taxon", "name"])
    }
  end

  @doc """
  The value of an observation's field `name` (compared ignoring case and
  surrounding space), or nil: for a taxon field, its taxon's name.
  """
  @spec field_value(Observation.t(), String.t()) :: String.t() | nil
  def field_value(%Observation{field_values: values}, name) do
    wanted = name |> String.trim() |> String.downcase()

    Enum.find_value(values, fn field ->
      if is_binary(field.name) and String.downcase(String.trim(field.name)) == wanted,
        do: blank_nil(field.taxon_name) || blank_nil(field.value)
    end)
  end

  defp blank_nil(nil), do: nil

  defp blank_nil(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  @doc """
  Fetches iNaturalist places by ID (an observation's `place_ids`), each as
  `%{id, name, admin_level}` — `admin_level` 0 for a country, 10 for a
  state or province, 20 for a county, nil for a place no government
  draws. `{:error, reason}` as `fetch_observation/1`.
  """
  @spec fetch_places([integer()]) ::
          {:ok, [%{id: integer(), name: String.t(), admin_level: integer() | nil}]}
          | {:error, term()}
  def fetch_places([]), do: {:ok, []}

  def fetch_places(ids) when is_list(ids) do
    case get_json("places/#{Enum.join(Enum.take(ids, 500), ",")}") do
      {:ok, %{"results" => results}} when is_list(results) ->
        {:ok,
         for(
           %{"id" => id, "name" => name} = place <- results,
           do: %{id: id, name: name, admin_level: place["admin_level"]}
         )}

      {:ok, _body} ->
        {:error, :invalid_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Formats the creator field from iNat user login and display name.
  """
  @spec format_creator(String.t(), String.t() | nil) :: String.t()
  def format_creator(login, nil), do: login
  def format_creator(login, ""), do: login
  def format_creator(login, name), do: "#{login} - #{name}"

  # Replace "square" (or any size) in a photo URL with the requested size.
  defp photo_size_url(url, size) when is_binary(url) do
    String.replace(url, ~r{/square\.(jpe?g|png)}, "/#{size}.\\1")
  end

  defp do_fetch_observation(id), do: get_json("observations/#{id}")

  @doc """
  GETs `path` of iNaturalist's API (`"taxa/autocomplete"`, under `/v1`)
  with query `params`, as JSON: `{:ok, body}`, `{:error, :not_found}` for a
  404, `{:error, {:http_error, status}}` or `{:error, reason}`. Every
  request names the app, never a person, and goes through the configured
  `:req_options` (a `Req.Test` stub in tests).
  """
  @spec get_json(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_json(path, params \\ []) do
    options = if params == [], do: request_options(), else: [params: params] ++ request_options()

    case Req.get("#{@api_base}/#{path}", options) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        Logger.warning("iNat API returned status #{status} for #{path}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("iNat API request failed for #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # The user agent, and the configured `:req_options` (tests route requests
  # to a `Req.Test` stub).
  defp request_options do
    [headers: [{"user-agent", @user_agent}]] ++
      Keyword.get(Application.get_env(:gallformers, __MODULE__, []), :req_options, [])
  end
end
