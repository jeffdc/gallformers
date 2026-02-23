defmodule Mix.Tasks.Gallformers.Wcvp.BackfillIds do
  @moduledoc """
  Backfills wcvp_id and powo_id into host_traits for existing host species
  by matching against the WCVP names database.

  ## Usage

      mix gallformers.wcvp.backfill_ids           # dry run
      mix gallformers.wcvp.backfill_ids --commit   # write to database
  """

  use Mix.Task
  import Ecto.Query
  require Logger

  alias Gallformers.Plants
  alias Gallformers.Repo
  alias Gallformers.Wcvp.Lookup

  @shortdoc "Backfill WCVP/POWO IDs for existing host species"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, strict: [commit: :boolean])
    commit? = opts[:commit] || false

    unless Lookup.available?() do
      Logger.error("WCVP database not available. Run mix gallformers.wcvp.build_db first.")
      exit(:shutdown)
    end

    # Get all host species without host_traits (or with nil wcvp_id)
    hosts =
      from(s in "species",
        left_join: ht in "host_traits",
        on: s.id == ht.species_id,
        where: s.taxoncode == "plant" and is_nil(ht.wcvp_id),
        select: %{id: s.id, name: type(s.name, :string)}
      )
      |> Repo.all()

    Logger.info("Found #{length(hosts)} hosts without WCVP IDs")

    matched =
      Enum.reduce(hosts, 0, fn host, count ->
        case Lookup.search(host.name, limit: 1) do
          [match] when match.taxon_name == host.name ->
            maybe_commit_wcvp(commit?, host.id, match.plant_name_id)
            Logger.info("  Matched: #{host.name} -> WCVP #{match.plant_name_id}")
            count + 1

          _ ->
            count
        end
      end)

    Logger.info("Matched #{matched}/#{length(hosts)} hosts")

    unless commit? do
      Logger.info("Dry run complete. Use --commit to write changes.")
    end
  end

  defp maybe_commit_wcvp(false, _host_id, _plant_name_id), do: :ok

  defp maybe_commit_wcvp(true, host_id, plant_name_id) do
    wcvp_data = Lookup.get(plant_name_id)

    Plants.upsert_host_traits(host_id, %{
      wcvp_id: plant_name_id,
      powo_id: wcvp_data && wcvp_data.powo_id
    })
  end
end
