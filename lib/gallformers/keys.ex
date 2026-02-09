defmodule Gallformers.Keys do
  @moduledoc """
  Context for loading and querying dichotomous identification keys.

  Keys are stored as JSON files in `priv/keys/`. Each file represents
  one key with metadata and a set of numbered couplets. Files are read
  at compile time and cached as module attributes.
  """

  @keys_dir Path.join(:code.priv_dir(:gallformers), "keys")

  # Parse functions used at compile time — must be defined before @keys attribute
  defmodule Parser do
    @moduledoc false

    def parse_key(data) do
      %{
        slug: data["slug"],
        title: data["title"],
        subtitle: data["subtitle"],
        authors: data["authors"] || [],
        citation: data["citation"],
        citation_url: data["citation_url"],
        description: data["description"],
        version: data["version"],
        couplets: parse_couplets(data["couplets"] || %{})
      }
    end

    defp parse_couplets(couplets_map) do
      Map.new(couplets_map, fn {number, couplet_data} ->
        {number, parse_couplet(couplet_data)}
      end)
    end

    defp parse_couplet(data) do
      %{
        leads: Enum.map(data["leads"] || [], &parse_lead/1)
      }
    end

    defp parse_lead(data) do
      %{
        text: data["text"],
        images: Enum.map(data["images"] || [], &parse_image/1),
        destination: parse_destination(data["destination"])
      }
    end

    defp parse_image(data) do
      %{
        ref: data["ref"],
        file: data["file"],
        caption: data["caption"]
      }
    end

    defp parse_destination(nil), do: nil

    defp parse_destination(data) do
      base = %{type: data["type"]}

      case data["type"] do
        "couplet" ->
          base
          |> Map.put(:number, data["number"])
          |> Map.put(:label, data["label"])

        "taxon" ->
          base
          |> Map.put(:name, data["name"])
          |> Map.put(:context, data["context"])

        _ ->
          base
      end
    end
  end

  @keys @keys_dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.map(fn filename ->
          path = Path.join(@keys_dir, filename)
          json = File.read!(path)
          data = Jason.decode!(json)
          Parser.parse_key(data)
        end)
        |> Map.new(&{&1.slug, &1})

  @doc """
  Returns a list of all available keys (metadata only, no couplet data).
  """
  def list_keys do
    @keys
    |> Map.values()
    |> Enum.map(fn key ->
      Map.drop(key, [:couplets])
    end)
    |> Enum.sort_by(& &1.title)
  end

  @doc """
  Returns the full key data for the given slug, including all couplets.
  """
  def get_key(slug) do
    case Map.fetch(@keys, slug) do
      {:ok, key} -> {:ok, key}
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Returns the couplet numbers for a key, sorted numerically.
  """
  def couplet_numbers(key) do
    key.couplets
    |> Map.keys()
    |> Enum.sort_by(&String.to_integer/1)
  end
end
