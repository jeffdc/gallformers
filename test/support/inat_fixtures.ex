defmodule Gallformers.INaturalistFixtures do
  @moduledoc """
  iNaturalist's taxa, as its public API gave them on 2026-11-08, trimmed to
  the fields Gallformers reads (`test/support/fixtures/inaturalist/`), and a
  `Req.Test` stub serving them (matter `cb28`): no test reaches the network.

    * taxa: Arguti 1449402 (a section of *Rubus*), *Rubus frondosus* 168056,
      Syrphidae 49995, Alleghenienses 1449411 (iNaturalist's rank
      "complex"), and the inactive *Rubus pensilvanicus* 78894, replaced by
      Arguti;
    * searches: "Rubus pensilvanicus" (Arguti, through the synonym),
      "Syrphidae", "Rubus villosus var. frondosus" (nothing), "Rubus
      frondosus", "Arguti", "Alleghenienses".
  """
  alias Gallformers.INaturalist

  @dir Path.expand("fixtures/inaturalist", __DIR__)

  @searches %{
    "rubus pensilvanicus" => "auto_rubus_pensilvanicus.json",
    "syrphidae" => "auto_syrphidae.json",
    "rubus villosus var. frondosus" => "auto_rubus_villosus.json",
    "rubus frondosus" => "auto_rubus_frondosus.json",
    "arguti" => "auto_arguti.json",
    "alleghenienses" => "auto_alleghenienses.json"
  }

  @taxa [1_449_402, 168_056, 49_995, 1_449_411, 78_894]

  @doc "The IDs of the taxa recorded."
  def inat_taxon_ids, do: @taxa

  @doc "The recorded response for taxon `id` (`/v1/taxa/:id?all_names=true`)."
  def inat_taxon_json(id), do: read("taxon_#{id}.json")

  @doc "The recorded taxon `id`, parsed (`Gallformers.INaturalist.Taxa.parse_taxon/1`)."
  def inat_taxon(id) do
    %{"results" => [raw]} = inat_taxon_json(id)
    INaturalist.Taxa.parse_taxon(raw)
  end

  @doc """
  Serves the recorded responses to `Gallformers.INaturalist`'s requests: a
  taxon by ID, a search by its query (any other: no results). Pass
  `test_pid` to send it `{:inat_request, path, query}` for each request.
  """
  def stub_inat_taxa(test_pid \\ nil) do
    Req.Test.stub(INaturalist, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      if test_pid, do: send(test_pid, {:inat_request, conn.request_path, conn.query_params})
      respond(conn)
    end)
  end

  @doc "Makes every iNaturalist request fail, as when iNaturalist can't be reached."
  def stub_inat_down, do: Req.Test.stub(INaturalist, &Req.Test.transport_error(&1, :econnrefused))

  defp respond(%{request_path: "/v1/taxa/autocomplete"} = conn) do
    q = conn.query_params["q"] |> to_string() |> String.trim() |> String.downcase()

    case Map.fetch(@searches, q) do
      {:ok, file} -> Req.Test.json(conn, read(file))
      :error -> Req.Test.json(conn, %{"total_results" => 0, "results" => []})
    end
  end

  defp respond(%{request_path: "/v1/taxa/" <> id} = conn) do
    case Integer.parse(id) do
      {id, ""} when id in @taxa ->
        Req.Test.json(conn, inat_taxon_json(id))

      _ ->
        Req.Test.json(conn, %{"total_results" => 0, "results" => []})
    end
  end

  defp respond(conn), do: conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{})

  defp read(file), do: @dir |> Path.join(file) |> File.read!() |> Jason.decode!()
end
