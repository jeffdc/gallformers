defmodule Gallformers.Wcvp.LookupStub do
  @moduledoc """
  Test stub for Wcvp.Lookup that returns canned data without a database.

  Data:
    - "500" / "Zzyzx wcvponly" — no-match species for search tests (no distributions)
    - "600" / "Thymus alpinus" — matches seed host 6, with NWY native + ALB introduced
    - "700" / "Wcvptestus alpinus" — for tests that create their own host data
    - "800" / "Wcvpseedus rangeus" — regions that map to seeded places: California
      (US-CA) native, Alberta (CA-AB) introduced
    - "900" / "Wcvphybridus × crossus" — an artificial hybrid, accepted in itself
      (as WCVP holds the loganberry), native in California; "901" is its synonym
    - "902" / "Wcvpunplacedus vagus" — unplaced, with no accepted name; "903" is
      its synonym (as WCVP holds Rubus villosus var. frondosus)
    - "910" / "Wcvphomonymus dubius" — a name WCVP holds twice, with different
      authors: accepted "Smith" and "911", illegitimate "Jones"; and
      "Wcvphomonymus dubius var. minor" twice, both synonyms: "912" of 910
      ("Brown"), "913" of 700 ("Green") — for authorship by name
    - "920" / "Wcvpgenerus" — a genus record (as WCVP holds Stephanomeria),
      native in California

  Only "920" gives its `taxon_rank`; a record without one is read by its
  name's infraspecific marker.

  Like `Gallformers.Wcvp.Lookup`, `search/2` leaves out records that are not
  Accepted unless asked for synonyms, and `get_accepted_name/1` returns the
  accepted record without its distributions.
  """
  @behaviour Gallformers.Wcvp.LookupBehaviour

  alias Gallformers.Wcvp.WcvpName

  @names %{
    "500" => %WcvpName{
      plant_name_id: "500",
      taxon_name: "Zzyzx wcvponly",
      family: "Testaceae",
      genus: "Zzyzx",
      species: "wcvponly",
      taxon_authors: "Test",
      powo_id: nil,
      taxon_status: "Accepted",
      native_distribution: [],
      introduced_distribution: []
    },
    "600" => %WcvpName{
      plant_name_id: "600",
      taxon_name: "Thymus alpinus",
      family: "Lamiaceae",
      genus: "Thymus",
      species: "alpinus",
      taxon_authors: "L.",
      powo_id: "urn:lsid:ipni.org:names:test",
      taxon_status: "Accepted",
      native_distribution: ["NWY"],
      introduced_distribution: ["ALB"]
    },
    "700" => %WcvpName{
      plant_name_id: "700",
      taxon_name: "Wcvptestus alpinus",
      family: "Testaceae",
      genus: "Wcvptestus",
      species: "alpinus",
      taxon_authors: "Test",
      powo_id: "urn:lsid:ipni.org:names:test700",
      taxon_status: "Accepted",
      native_distribution: ["NWY"],
      introduced_distribution: ["ALB"]
    },
    "800" => %WcvpName{
      plant_name_id: "800",
      taxon_name: "Wcvpseedus rangeus",
      family: "Seedaceae",
      genus: "Wcvpseedus",
      species: "rangeus",
      taxon_authors: "Test",
      powo_id: "urn:lsid:ipni.org:names:test800",
      taxon_status: "Accepted",
      native_distribution: ["CAL"],
      introduced_distribution: ["ABT"]
    },
    "900" => %WcvpName{
      plant_name_id: "900",
      taxon_name: "Wcvphybridus × crossus",
      family: "Hybridaceae",
      genus: "Wcvphybridus",
      species: "crossus",
      taxon_authors: "Test",
      taxon_status: "Artificial Hybrid",
      accepted_plant_name_id: "900",
      native_distribution: ["CAL"],
      introduced_distribution: []
    },
    "901" => %WcvpName{
      plant_name_id: "901",
      taxon_name: "Wcvphybridus parentus var. crossus",
      family: "Hybridaceae",
      genus: "Wcvphybridus",
      species: "parentus",
      taxon_authors: "Test",
      taxon_status: "Synonym",
      accepted_plant_name_id: "900",
      native_distribution: [],
      introduced_distribution: []
    },
    "902" => %WcvpName{
      plant_name_id: "902",
      taxon_name: "Wcvpunplacedus vagus",
      family: "Hybridaceae",
      genus: "Wcvpunplacedus",
      species: "vagus",
      taxon_authors: "Test",
      taxon_status: "Unplaced",
      accepted_plant_name_id: "",
      native_distribution: [],
      introduced_distribution: []
    },
    "903" => %WcvpName{
      plant_name_id: "903",
      taxon_name: "Wcvpunplacedus vagus var. alter",
      family: "Hybridaceae",
      genus: "Wcvpunplacedus",
      species: "vagus",
      taxon_authors: "Test",
      taxon_status: "Synonym",
      accepted_plant_name_id: "902",
      native_distribution: [],
      introduced_distribution: []
    },
    "910" => %WcvpName{
      plant_name_id: "910",
      taxon_name: "Wcvphomonymus dubius",
      family: "Homonymaceae",
      genus: "Wcvphomonymus",
      species: "dubius",
      taxon_authors: "Smith",
      taxon_status: "Accepted",
      accepted_plant_name_id: "910",
      native_distribution: [],
      introduced_distribution: []
    },
    "911" => %WcvpName{
      plant_name_id: "911",
      taxon_name: "Wcvphomonymus dubius",
      family: "Homonymaceae",
      genus: "Wcvphomonymus",
      species: "dubius",
      taxon_authors: "Jones",
      taxon_status: "Illegitimate",
      accepted_plant_name_id: "",
      native_distribution: [],
      introduced_distribution: []
    },
    "912" => %WcvpName{
      plant_name_id: "912",
      taxon_name: "Wcvphomonymus dubius var. minor",
      family: "Homonymaceae",
      genus: "Wcvphomonymus",
      species: "dubius",
      taxon_authors: "Brown",
      taxon_status: "Synonym",
      accepted_plant_name_id: "910",
      native_distribution: [],
      introduced_distribution: []
    },
    "913" => %WcvpName{
      plant_name_id: "913",
      taxon_name: "Wcvphomonymus dubius var. minor",
      family: "Homonymaceae",
      genus: "Wcvphomonymus",
      species: "dubius",
      taxon_authors: "Green",
      taxon_status: "Synonym",
      accepted_plant_name_id: "700",
      native_distribution: [],
      introduced_distribution: []
    },
    "920" => %WcvpName{
      plant_name_id: "920",
      taxon_name: "Wcvpgenerus",
      taxon_rank: "Genus",
      family: "Generaceae",
      genus: "Wcvpgenerus",
      taxon_authors: "Nutt.",
      powo_id: "urn:lsid:ipni.org:names:test920",
      taxon_status: "Accepted",
      accepted_plant_name_id: "920",
      native_distribution: ["CAL"],
      introduced_distribution: []
    }
  }

  @impl true
  def available?, do: true

  @impl true
  def built_at, do: ~U[2026-01-01 00:00:00Z]

  @impl true
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    pattern = String.downcase(query)

    opts
    |> listed()
    |> Enum.filter(&String.starts_with?(String.downcase(&1.taxon_name), pattern))
    |> Enum.sort_by(& &1.taxon_name)
    |> Enum.take(limit)
  end

  @impl true
  def search_contains(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    terms = query |> String.split(~r/\s+/, trim: true) |> Enum.map(&String.downcase/1)

    opts
    |> listed()
    |> Enum.filter(fn name ->
      lower = String.downcase(name.taxon_name)
      Enum.all?(terms, &String.contains?(lower, &1))
    end)
    |> Enum.sort_by(& &1.taxon_name)
    |> Enum.take(limit)
  end

  # The records a search sees: Accepted ones, unless asked for synonyms.
  defp listed(opts) do
    names = Map.values(@names)

    if Keyword.get(opts, :include_synonyms),
      do: names,
      else: Enum.filter(names, &(&1.taxon_status == "Accepted"))
  end

  @impl true
  def match_by_name(name, _opts \\ []) do
    @names
    |> Map.values()
    |> Enum.find(&(&1.taxon_name == name))
  end

  @impl true
  def get(plant_name_id) do
    Map.get(@names, plant_name_id)
  end

  @impl true
  def get_accepted_name(plant_name_id) do
    case get(plant_name_id) do
      %{accepted_plant_name_id: accepted} when accepted in [nil, "", plant_name_id] ->
        nil

      %{accepted_plant_name_id: accepted} ->
        case get(accepted) do
          nil -> nil
          record -> %{record | native_distribution: [], introduced_distribution: []}
        end

      nil ->
        nil
    end
  end

  @impl true
  def get_names(plant_name_ids) do
    @names
    |> Map.take(plant_name_ids)
    |> Map.values()
    |> Enum.map(&%{&1 | native_distribution: [], introduced_distribution: []})
  end

  @impl true
  def find_names(names) do
    wanted = MapSet.new(names, &String.downcase/1)

    @names
    |> Map.values()
    |> Enum.filter(&MapSet.member?(wanted, String.downcase(&1.taxon_name)))
    |> Enum.map(&%{&1 | native_distribution: [], introduced_distribution: []})
  end
end
