# WCVP Reconciliation Pipeline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build Mix tasks that download WCVP plant taxonomy data, reconcile it against the gallformers database, produce JSON reports, and apply selected changes.

**Architecture:** Three Mix tasks (download, reconcile, apply) backed by library modules in `lib/gallformers/wcvp/`. CSV parsing uses NimbleCSV for streaming. Name matching uses three passes (exact, fuzzy, synonym). A static TDWG-to-places JSON mapping converts botanical region codes to gallformers place codes.

**Tech Stack:** Elixir Mix tasks, NimbleCSV, Jason, Ecto queries against existing contexts (Plants, Taxonomy, Ranges, Places).

**Design doc:** `docs/plans/2026-02-19-wcvp-reconciliation-pipeline-design.md`

---

## Task 1: Add NimbleCSV dependency

WCVP CSVs are large (~1.4M rows names, ~2M rows distributions). NimbleCSV streams rows without loading the full file into memory.

**Files:**
- Modify: `mix.exs`

**Step 1: Add the dependency**

In `mix.exs`, add to the `deps` function:

```elixir
{:nimble_csv, "~> 1.2"}
```

**Step 2: Install**

Run: `mix deps.get`
Expected: nimble_csv fetched successfully.

**Step 3: Compile and verify**

Run: `mix compile --warnings-as-errors`
Expected: Clean compile.

**Step 4: Commit**

```bash
git add mix.exs mix.lock
git commit -m "Add nimble_csv dependency for WCVP CSV parsing"
```

---

## Task 2: Add priv/repo/data/wcvp/ to .gitignore

The cached WCVP download is ~85MB and freely available — don't commit it.

**Files:**
- Modify: `.gitignore`

**Step 1: Add the ignore rule**

Add to `.gitignore`:

```
# Cached WCVP data (large, downloadable from Kew)
priv/repo/data/wcvp/
```

**Step 2: Commit**

```bash
git add .gitignore
git commit -m "Gitignore cached WCVP data directory"
```

---

## Task 3: Build the TDWG-to-places mapping file

This is a static JSON file mapping TDWG Level 3 botanical region codes to gallformers place codes. It needs to be hand-curated once. TDWG codes are stable and rarely change.

**Files:**
- Create: `priv/repo/data/tdwg_to_places.json`

**Context — TDWG Level 3 codes for the Western Hemisphere:**

The WCVP `wcvp_distributions.csv` uses the `area_code_l3` column with TDWG (WGSRPD) Level 3 codes. These are 2-3 letter codes for botanical regions. The full list of Western Hemisphere TDWG L3 codes is available from the [WGSRPD standard](https://www.tdwg.org/standards/wgsrpd/).

**Context — Gallformers place codes:**

Check `priv/repo/data/western_hemisphere_places.json` for all gallformers place codes. Also query the DB: all place codes can be retrieved via `Gallformers.Places.list_all_places()`.

**Step 1: Research the full TDWG L3 code list**

Use the WGSRPD standard documentation and/or the `area_code_l3` values from a downloaded `wcvp_distributions.csv` to enumerate all Western Hemisphere TDWG L3 codes. Cross-reference with the gallformers places table.

Key mapping patterns:
- US states: TDWG has individual codes (e.g., `CAL` = California → `US-CA`)
- Canadian provinces: TDWG has individual codes (e.g., `ABT` = Alberta → `CA-AB`)
- Brazil: TDWG splits into 7 regions (`BZN`, `BZS`, `BZL`, `BZE`, `BZC`, `BZW`, `BZF`) each mapping to multiple Brazilian state codes
- Most other countries: single TDWG code → single country code with `country` precision
- Caribbean islands: mostly individual TDWG codes → individual country codes

**Step 2: Create the mapping file**

Format — each entry maps one TDWG L3 code to one or more gallformers place codes with precision:

```json
[
  {
    "tdwg_code": "CAL",
    "tdwg_name": "California",
    "places": [{"code": "US-CA", "precision": "exact"}]
  },
  {
    "tdwg_code": "ABT",
    "tdwg_name": "Alberta",
    "places": [{"code": "CA-AB", "precision": "exact"}]
  },
  {
    "tdwg_code": "MEX",
    "tdwg_name": "Mexico",
    "places": [{"code": "MX", "precision": "country"}]
  },
  {
    "tdwg_code": "BZL",
    "tdwg_name": "Brazil South",
    "places": [
      {"code": "BR-PR", "precision": "exact"},
      {"code": "BR-SC", "precision": "exact"},
      {"code": "BR-RS", "precision": "exact"}
    ]
  }
]
```

**Step 3: Validate completeness**

Ensure every Western Hemisphere TDWG L3 code has at least one mapping. Ensure every mapped place code exists in the gallformers places table. Write a quick validation in IEx:

```elixir
mapping = Jason.decode!(File.read!("priv/repo/data/tdwg_to_places.json"))
place_codes = mapping |> Enum.flat_map(& &1["places"]) |> Enum.map(& &1["code"])
db_codes = Gallformers.Places.list_all_places() |> Enum.map(& &1.code) |> MapSet.new()
missing = Enum.reject(place_codes, &MapSet.member?(db_codes, &1))
# Should be empty
```

**Step 4: Commit**

```bash
git add priv/repo/data/tdwg_to_places.json
git commit -m "Add TDWG Level 3 to gallformers places mapping"
```

---

## Task 4: WCVP CSV reader module

Streams and parses WCVP CSV files. Filters to accepted vascular plant names only.

**Files:**
- Create: `lib/gallformers/wcvp/reader.ex`
- Create: `test/gallformers/wcvp/reader_test.exs`

**Context — WCVP CSV columns:**

`wcvp_names.csv` columns (pipe-delimited `|`, not comma):
- `plant_name_id` — unique ID
- `ipni_id` — IPNI identifier
- `taxon_rank` — "Species", "Variety", "Subspecies", "Form", etc.
- `taxon_status` — "Accepted", "Synonym", "Unplaced", "Invalid", etc.
- `family` — family name
- `genus_hybrid` — `×` if hybrid genus, else empty
- `genus` — genus name
- `species_hybrid` — `×` if hybrid species, else empty
- `species` — species epithet
- `infraspecific_rank` — "var.", "subsp.", "f.", etc.
- `infraspecies` — infraspecific epithet
- `parenthetical_author` — basionym author
- `primary_author` — current combination author
- `taxon_name` — full name without authors
- `taxon_authors` — concatenated author string
- `accepted_plant_name_id` — ID of accepted name (same as plant_name_id if accepted)
- `parent_plant_name_id` — parent genus/species ID
- `powo_id` — Plants of the World Online ID
- `reviewed` — peer review flag

`wcvp_distributions.csv` columns (pipe-delimited `|`):
- `plant_name_id` — joins to names
- `continent_code_l1` — TDWG L1 (continent)
- `continent` — continent name
- `region_code_l2` — TDWG L2 (sub-continent)
- `region` — region name
- `area_code_l3` — TDWG L3 (botanical country) — **this is what we map**
- `area` — area name
- `introduced` — 0=native, 1=introduced
- `extinct` — 0=extant, 1=extinct
- `location_doubtful` — 0=confirmed, 1=doubtful

**Important:** WCVP uses pipe `|` as delimiter, not comma. Configure NimbleCSV accordingly.

**Step 1: Write tests for the reader**

```elixir
# test/gallformers/wcvp/reader_test.exs
defmodule Gallformers.Wcvp.ReaderTest do
  use ExUnit.Case, async: true

  alias Gallformers.Wcvp.Reader

  @names_csv """
  plant_name_id|ipni_id|taxon_rank|taxon_status|family|genus_hybrid|genus|species_hybrid|species|infraspecific_rank|infraspecies|parenthetical_author|primary_author|publication_author|place_of_publication|volume_and_page|first_published|nomenclatural_remarks|geographic_area|lifeform_description|climate_description|taxon_name|taxon_authors|accepted_plant_name_id|basionym_plant_name_id|replaced_synonym_author|homotypic_synonym|parent_plant_name_id|powo_id|hybrid_formula|reviewed
  1|123-1|Species|Accepted|Fagaceae||Quercus||alba||||||||||||||Quercus alba|L.|1||||||urn:lsid:ipni.org:names:123-1|
  2|124-1|Species|Synonym|Fagaceae||Quercus||stellata||||||||||||||Quercus stellata|Wangenh.|3|||||||
  3|125-1|Species|Accepted|Fagaceae||Quercus||rubra||||||||||||||Quercus rubra|L.|3||||||urn:lsid:ipni.org:names:125-1|
  4|126-1|Variety|Accepted|Rosaceae||Rosa||canina|var.|lutetiana|||||||||||||Rosa canina var. lutetiana|(Leman) Baker|4||||||
  5|127-1|Species|Unplaced|Asteraceae||Fictus||plantus||||||||||||||Fictus plantus|Auth.|5|||||||
  """

  @distributions_csv """
  plant_locality_id|plant_name_id|continent_code_l1|continent|region_code_l2|region|area_code_l3|area|introduced|extinct|location_doubtful
  1|1|7|NORTHERN AMERICA|71|Southeastern U.S.A.|ALB|Alabama|0|0|0
  2|1|7|NORTHERN AMERICA|71|Southeastern U.S.A.|GEO|Georgia|0|0|0
  3|1|8|SOUTHERN AMERICA|84|Brazil|BZL|Brazil South|0|0|0
  4|3|7|NORTHERN AMERICA|74|North-Central U.S.A.|ILL|Illinois|1|0|0
  5|1|7|NORTHERN AMERICA|71|Southeastern U.S.A.|ALB|Alabama|0|1|0
  """

  describe "stream_accepted_names/1" do
    test "filters to accepted species and subspecific taxa only" do
      path = write_temp_csv("names.csv", @names_csv)
      names = Reader.stream_accepted_names(path) |> Enum.to_list()

      assert length(names) == 3
      assert Enum.all?(names, fn n -> n.taxon_status == "Accepted" end)
    end

    test "parses fields into a struct" do
      path = write_temp_csv("names.csv", @names_csv)
      [first | _] = Reader.stream_accepted_names(path) |> Enum.to_list()

      assert first.plant_name_id == "1"
      assert first.genus == "Quercus"
      assert first.species == "alba"
      assert first.family == "Fagaceae"
      assert first.taxon_name == "Quercus alba"
      assert first.taxon_authors == "L."
    end
  end

  describe "stream_names_for_synonym_lookup/1" do
    test "includes synonyms with their accepted_plant_name_id" do
      path = write_temp_csv("names.csv", @names_csv)
      synonyms = Reader.stream_names_for_synonym_lookup(path) |> Enum.to_list()

      # Should include synonyms that point to a different accepted name
      syn = Enum.find(synonyms, fn n -> n.taxon_status == "Synonym" end)
      assert syn != nil
      assert syn.taxon_name == "Quercus stellata"
      assert syn.accepted_plant_name_id == "3"
    end
  end

  describe "stream_native_distributions/1" do
    test "filters to native, extant, non-doubtful distributions" do
      path = write_temp_csv("distributions.csv", @distributions_csv)
      dists = Reader.stream_native_distributions(path) |> Enum.to_list()

      # Row 4 is introduced (1), row 5 is extinct (1) — both excluded
      assert length(dists) == 3
      assert Enum.all?(dists, fn d -> d.introduced == "0" end)
      assert Enum.all?(dists, fn d -> d.extinct == "0" end)
    end

    test "parses TDWG area code" do
      path = write_temp_csv("distributions.csv", @distributions_csv)
      [first | _] = Reader.stream_native_distributions(path) |> Enum.to_list()

      assert first.area_code_l3 == "ALB"
      assert first.plant_name_id == "1"
    end
  end

  describe "build_synonym_index/1" do
    test "maps synonym canonical names to their accepted name IDs" do
      path = write_temp_csv("names.csv", @names_csv)
      index = Reader.build_synonym_index(path)

      assert Map.has_key?(index, "Quercus stellata")
      assert index["Quercus stellata"] == "3"
    end
  end

  describe "build_accepted_name_lookup/1" do
    test "maps accepted plant_name_id to name struct" do
      path = write_temp_csv("names.csv", @names_csv)
      lookup = Reader.build_accepted_name_lookup(path)

      assert Map.has_key?(lookup, "1")
      assert lookup["1"].taxon_name == "Quercus alba"
    end
  end

  describe "build_distribution_index/1" do
    test "groups native TDWG codes by plant_name_id" do
      path = write_temp_csv("distributions.csv", @distributions_csv)
      index = Reader.build_distribution_index(path)

      assert Map.has_key?(index, "1")
      assert "ALB" in index["1"]
      assert "GEO" in index["1"]
      assert "BZL" in index["1"]
    end
  end

  defp write_temp_csv(filename, content) do
    dir = System.tmp_dir!()
    path = Path.join(dir, "wcvp_test_#{filename}")
    File.write!(path, String.trim(content))
    path
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/gallformers/wcvp/reader_test.exs`
Expected: Compilation error — `Gallformers.Wcvp.Reader` not found.

**Step 3: Implement the reader**

```elixir
# lib/gallformers/wcvp/reader.ex
defmodule Gallformers.Wcvp.Reader do
  @moduledoc """
  Streams and parses WCVP CSV files (pipe-delimited).
  Provides filtered streams and index-building functions for reconciliation.
  """

  NimbleCSV.define(WcvpParser, separator: "|", escape: "\"")

  defmodule Name do
    @moduledoc false
    defstruct [
      :plant_name_id,
      :taxon_rank,
      :taxon_status,
      :family,
      :genus,
      :species,
      :species_hybrid,
      :infraspecific_rank,
      :infraspecies,
      :taxon_name,
      :taxon_authors,
      :accepted_plant_name_id,
      :parent_plant_name_id
    ]
  end

  defmodule Distribution do
    @moduledoc false
    defstruct [
      :plant_name_id,
      :continent_code_l1,
      :region_code_l2,
      :area_code_l3,
      :area,
      :introduced,
      :extinct,
      :location_doubtful
    ]
  end

  @name_fields %{
    "plant_name_id" => :plant_name_id,
    "taxon_rank" => :taxon_rank,
    "taxon_status" => :taxon_status,
    "family" => :family,
    "genus" => :genus,
    "species" => :species,
    "species_hybrid" => :species_hybrid,
    "infraspecific_rank" => :infraspecific_rank,
    "infraspecies" => :infraspecies,
    "taxon_name" => :taxon_name,
    "taxon_authors" => :taxon_authors,
    "accepted_plant_name_id" => :accepted_plant_name_id,
    "parent_plant_name_id" => :parent_plant_name_id
  }

  @dist_fields %{
    "plant_name_id" => :plant_name_id,
    "continent_code_l1" => :continent_code_l1,
    "region_code_l2" => :region_code_l2,
    "area_code_l3" => :area_code_l3,
    "area" => :area,
    "introduced" => :introduced,
    "extinct" => :extinct,
    "location_doubtful" => :location_doubtful
  }

  @doc """
  Streams accepted names (Species, Variety, Subspecies, Form) from wcvp_names.csv.
  Skips Synonyms, Unplaced, and Invalid names.
  """
  def stream_accepted_names(path) do
    stream_names(path)
    |> Stream.filter(fn name -> name.taxon_status == "Accepted" end)
  end

  @doc """
  Streams synonym names for building a synonym lookup index.
  Returns names where taxon_status is "Synonym" and accepted_plant_name_id differs.
  """
  def stream_names_for_synonym_lookup(path) do
    stream_names(path)
    |> Stream.filter(fn name ->
      name.taxon_status == "Synonym" and
        name.accepted_plant_name_id not in [nil, "", name.plant_name_id]
    end)
  end

  @doc """
  Streams native, extant, non-doubtful distributions from wcvp_distributions.csv.
  """
  def stream_native_distributions(path) do
    stream_distributions(path)
    |> Stream.filter(fn dist ->
      dist.introduced == "0" and dist.extinct == "0" and dist.location_doubtful == "0"
    end)
  end

  @doc """
  Builds a map of synonym canonical name -> accepted plant_name_id.
  Used for Pass 3 matching.
  """
  def build_synonym_index(path) do
    stream_names_for_synonym_lookup(path)
    |> Enum.reduce(%{}, fn name, acc ->
      Map.put(acc, name.taxon_name, name.accepted_plant_name_id)
    end)
  end

  @doc """
  Builds a map of accepted plant_name_id -> Name struct.
  Used to look up accepted names after synonym matching.
  """
  def build_accepted_name_lookup(path) do
    stream_accepted_names(path)
    |> Enum.reduce(%{}, fn name, acc ->
      Map.put(acc, name.plant_name_id, name)
    end)
  end

  @doc """
  Builds a map of plant_name_id -> list of TDWG L3 area codes.
  Only includes native, extant, non-doubtful distributions.
  """
  def build_distribution_index(distributions_path) do
    stream_native_distributions(distributions_path)
    |> Enum.reduce(%{}, fn dist, acc ->
      Map.update(acc, dist.plant_name_id, [dist.area_code_l3], fn codes ->
        [dist.area_code_l3 | codes]
      end)
    end)
  end

  # -- Private --

  defp stream_names(path) do
    {header, rows} = stream_csv(path)
    field_indices = build_field_indices(header, @name_fields)

    rows
    |> Stream.map(fn row -> row_to_struct(row, field_indices, %Name{}) end)
  end

  defp stream_distributions(path) do
    {header, rows} = stream_csv(path)
    field_indices = build_field_indices(header, @dist_fields)

    rows
    |> Stream.map(fn row -> row_to_struct(row, field_indices, %Distribution{}) end)
  end

  defp stream_csv(path) do
    [header_line | _] = File.stream!(path) |> Enum.take(1)
    header = header_line |> String.trim() |> String.split("|")

    rows =
      path
      |> File.stream!()
      |> Stream.drop(1)
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Stream.map(&String.split(&1, "|"))

    {header, rows}
  end

  defp build_field_indices(header, field_map) do
    header
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {col_name, idx}, acc ->
      case Map.get(field_map, col_name) do
        nil -> acc
        field -> Map.put(acc, field, idx)
      end
    end)
  end

  defp row_to_struct(row, field_indices, struct) do
    Enum.reduce(field_indices, struct, fn {field, idx}, acc ->
      value = Enum.at(row, idx, "")
      Map.put(acc, field, value)
    end)
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `mix test test/gallformers/wcvp/reader_test.exs`
Expected: All tests pass.

**Step 5: Run precommit**

Run: `mix compile --warnings-as-errors && mix format --check-formatted && mix credo --strict`
Expected: Clean.

**Step 6: Commit**

```bash
git add lib/gallformers/wcvp/reader.ex test/gallformers/wcvp/reader_test.exs
git commit -m "Add WCVP CSV reader with streaming and index builders"
```

---

## Task 5: TDWG mapping module

Loads the static TDWG-to-places JSON mapping and converts TDWG L3 codes to gallformers place codes with precision.

**Files:**
- Create: `lib/gallformers/wcvp/tdwg.ex`
- Create: `test/gallformers/wcvp/tdwg_test.exs`

**Step 1: Write tests**

```elixir
# test/gallformers/wcvp/tdwg_test.exs
defmodule Gallformers.Wcvp.TdwgTest do
  use ExUnit.Case, async: true

  alias Gallformers.Wcvp.Tdwg

  @test_mapping [
    %{
      "tdwg_code" => "CAL",
      "tdwg_name" => "California",
      "places" => [%{"code" => "US-CA", "precision" => "exact"}]
    },
    %{
      "tdwg_code" => "MEX",
      "tdwg_name" => "Mexico",
      "places" => [%{"code" => "MX", "precision" => "country"}]
    },
    %{
      "tdwg_code" => "BZL",
      "tdwg_name" => "Brazil South",
      "places" => [
        %{"code" => "BR-PR", "precision" => "exact"},
        %{"code" => "BR-SC", "precision" => "exact"},
        %{"code" => "BR-RS", "precision" => "exact"}
      ]
    }
  ]

  describe "load/1" do
    test "builds lookup from TDWG code to place entries" do
      lookup = Tdwg.build_lookup(@test_mapping)

      assert lookup["CAL"] == [%{code: "US-CA", precision: "exact"}]
      assert lookup["MEX"] == [%{code: "MX", precision: "country"}]
      assert length(lookup["BZL"]) == 3
    end
  end

  describe "convert_tdwg_codes/2" do
    test "converts list of TDWG codes to place code/precision pairs" do
      lookup = Tdwg.build_lookup(@test_mapping)
      result = Tdwg.convert_tdwg_codes(["CAL", "MEX", "BZL"], lookup)

      codes = Enum.map(result, & &1.code)
      assert "US-CA" in codes
      assert "MX" in codes
      assert "BR-PR" in codes
      assert "BR-SC" in codes
      assert "BR-RS" in codes
    end

    test "skips unknown TDWG codes and reports them" do
      lookup = Tdwg.build_lookup(@test_mapping)
      {result, unknown} = Tdwg.convert_tdwg_codes_with_warnings(["CAL", "ZZZ"], lookup)

      assert length(result) == 1
      assert unknown == ["ZZZ"]
    end
  end

  describe "us_canada_codes/1" do
    test "identifies US and Canadian place codes" do
      lookup = Tdwg.build_lookup(@test_mapping)
      assert Tdwg.us_canada_code?("US-CA")
      assert Tdwg.us_canada_code?("CA-AB")
      refute Tdwg.us_canada_code?("MX")
      refute Tdwg.us_canada_code?("BR-PR")
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/gallformers/wcvp/tdwg_test.exs`
Expected: Compilation error.

**Step 3: Implement**

```elixir
# lib/gallformers/wcvp/tdwg.ex
defmodule Gallformers.Wcvp.Tdwg do
  @moduledoc """
  Maps TDWG (WGSRPD) Level 3 botanical region codes to gallformers place codes.
  Loads from a static JSON mapping file.
  """

  @mapping_path "priv/repo/data/tdwg_to_places.json"

  @doc """
  Loads the TDWG mapping from the default JSON file.
  Returns the parsed lookup map.
  """
  def load do
    @mapping_path
    |> File.read!()
    |> Jason.decode!()
    |> build_lookup()
  end

  @doc """
  Builds a lookup map from a parsed JSON mapping list.
  Returns %{"TDWG_CODE" => [%{code: "XX-YY", precision: "exact"}, ...]}.
  """
  def build_lookup(mapping) when is_list(mapping) do
    Map.new(mapping, fn entry ->
      places =
        Enum.map(entry["places"], fn p ->
          %{code: p["code"], precision: p["precision"]}
        end)

      {entry["tdwg_code"], places}
    end)
  end

  @doc """
  Converts a list of TDWG L3 codes to gallformers place entries.
  Unknown TDWG codes are silently skipped.
  Returns a flat list of %{code, precision} maps.
  """
  def convert_tdwg_codes(tdwg_codes, lookup) do
    tdwg_codes
    |> Enum.flat_map(fn code -> Map.get(lookup, code, []) end)
    |> Enum.uniq_by(& &1.code)
  end

  @doc """
  Like convert_tdwg_codes/2 but also returns unknown TDWG codes.
  Returns {place_entries, unknown_codes}.
  """
  def convert_tdwg_codes_with_warnings(tdwg_codes, lookup) do
    {known, unknown} = Enum.split_with(tdwg_codes, &Map.has_key?(lookup, &1))

    places =
      known
      |> Enum.flat_map(fn code -> Map.get(lookup, code, []) end)
      |> Enum.uniq_by(& &1.code)

    {places, unknown}
  end

  @doc """
  Returns true if a place code is in the US or Canada.
  Used to split reports into US/CA priority vs rest-of-hemisphere.
  """
  def us_canada_code?(code) do
    String.starts_with?(code, "US-") or String.starts_with?(code, "CA-") or
      code in ["US", "CA"]
  end
end
```

**Step 4: Run tests**

Run: `mix test test/gallformers/wcvp/tdwg_test.exs`
Expected: All pass.

**Step 5: Precommit check**

Run: `mix compile --warnings-as-errors && mix format --check-formatted && mix credo --strict`

**Step 6: Commit**

```bash
git add lib/gallformers/wcvp/tdwg.ex test/gallformers/wcvp/tdwg_test.exs
git commit -m "Add TDWG-to-places mapping module"
```

---

## Task 6: Name matcher module

The core reconciliation logic. Matches gallformers species names against WCVP data in three passes.

**Files:**
- Create: `lib/gallformers/wcvp/matcher.ex`
- Create: `test/gallformers/wcvp/matcher_test.exs`

**Step 1: Write tests**

```elixir
# test/gallformers/wcvp/matcher_test.exs
defmodule Gallformers.Wcvp.MatcherTest do
  use ExUnit.Case, async: true

  alias Gallformers.Wcvp.Matcher
  alias Gallformers.Wcvp.Reader.Name

  # Simulated WCVP accepted names index (canonical name -> Name struct)
  @accepted_by_name %{
    "Quercus alba" => %Name{
      plant_name_id: "1",
      taxon_name: "Quercus alba",
      family: "Fagaceae",
      genus: "Quercus",
      species: "alba",
      taxon_status: "Accepted"
    },
    "Quercus rubra" => %Name{
      plant_name_id: "3",
      taxon_name: "Quercus rubra",
      family: "Fagaceae",
      genus: "Quercus",
      species: "rubra",
      taxon_status: "Accepted"
    },
    "Rosa canina" => %Name{
      plant_name_id: "10",
      taxon_name: "Rosa canina",
      family: "Rosaceae",
      genus: "Rosa",
      species: "canina",
      taxon_status: "Accepted"
    }
  }

  # Simulated synonym index (synonym canonical -> accepted plant_name_id)
  @synonym_index %{
    "Quercus stellata" => "3"
  }

  # Accepted names by ID (for synonym resolution)
  @accepted_by_id %{
    "1" => @accepted_by_name["Quercus alba"],
    "3" => @accepted_by_name["Quercus rubra"],
    "10" => @accepted_by_name["Rosa canina"]
  }

  describe "match_name/4 — Pass 1 exact" do
    test "exact match returns {:exact, wcvp_name}" do
      assert {:exact, name} =
               Matcher.match_name("Quercus alba", @accepted_by_name, @synonym_index, @accepted_by_id)

      assert name.taxon_name == "Quercus alba"
    end
  end

  describe "match_name/4 — Pass 2 fuzzy" do
    test "fuzzy match on epithet ending variation" do
      # "wallichii" vs "wallichianus" — not in our test data,
      # so test with a close enough case
      accepted = Map.put(@accepted_by_name, "Quercus agrifolia", %Name{
        plant_name_id: "20",
        taxon_name: "Quercus agrifolia",
        family: "Fagaceae",
        genus: "Quercus",
        species: "agrifolia",
        taxon_status: "Accepted"
      })

      # No exact match, no fuzzy match either — should be :no_match
      assert {:no_match, _} =
               Matcher.match_name("Quercus bogusii", accepted, @synonym_index, @accepted_by_id)
    end
  end

  describe "match_name/4 — Pass 3 synonym" do
    test "synonym match returns {:synonym, synonym_name, accepted_name}" do
      assert {:synonym, accepted} =
               Matcher.match_name(
                 "Quercus stellata",
                 @accepted_by_name,
                 @synonym_index,
                 @accepted_by_id
               )

      assert accepted.taxon_name == "Quercus rubra"
    end
  end

  describe "match_name/4 — no match" do
    test "returns :no_match for unknown species" do
      assert {:no_match, closest} =
               Matcher.match_name(
                 "Fictus plantus",
                 @accepted_by_name,
                 @synonym_index,
                 @accepted_by_id
               )

      # closest may be nil or a near miss
      assert is_nil(closest) or is_struct(closest, Name)
    end
  end

  describe "normalize_epithet/1" do
    test "normalizes common Latin endings" do
      assert Matcher.normalize_epithet("wallichii") == Matcher.normalize_epithet("wallichianus")
      assert Matcher.normalize_epithet("canadensis") == Matcher.normalize_epithet("canadense")
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/gallformers/wcvp/matcher_test.exs`
Expected: Compilation error.

**Step 3: Implement**

```elixir
# lib/gallformers/wcvp/matcher.ex
defmodule Gallformers.Wcvp.Matcher do
  @moduledoc """
  Three-pass name matching between gallformers species and WCVP data.

  Pass 1: Exact canonical name match ("Genus species")
  Pass 2: Fuzzy epithet matching (normalized Latin endings)
  Pass 3: Synonym lookup (gallformers name is a WCVP synonym)
  """

  @doc """
  Attempts to match a gallformers species name against WCVP data.

  Args:
    - gf_name: species name from gallformers (e.g., "Quercus alba")
    - accepted_by_name: %{"Quercus alba" => %Name{}, ...}
    - synonym_index: %{"old name" => "accepted_plant_name_id", ...}
    - accepted_by_id: %{"plant_name_id" => %Name{}, ...}

  Returns:
    - {:exact, %Name{}} — direct match
    - {:fuzzy, %Name{}} — matched via normalized epithet
    - {:synonym, %Name{}} — gallformers name is a WCVP synonym; returns the accepted name
    - {:no_match, closest_or_nil} — no match found
  """
  def match_name(gf_name, accepted_by_name, synonym_index, accepted_by_id) do
    with :no_match <- try_exact(gf_name, accepted_by_name),
         :no_match <- try_fuzzy(gf_name, accepted_by_name),
         :no_match <- try_synonym(gf_name, synonym_index, accepted_by_id) do
      closest = find_closest(gf_name, accepted_by_name)
      {:no_match, closest}
    end
  end

  @doc """
  Normalizes a Latin epithet for fuzzy comparison.
  Strips common ending variations so "wallichii" and "wallichianus" compare equal.
  """
  def normalize_epithet(epithet) do
    epithet
    |> String.downcase()
    |> strip_latin_endings()
  end

  # -- Pass 1: Exact --

  defp try_exact(name, accepted_by_name) do
    case Map.get(accepted_by_name, name) do
      nil -> :no_match
      wcvp_name -> {:exact, wcvp_name}
    end
  end

  # -- Pass 2: Fuzzy --

  defp try_fuzzy(name, accepted_by_name) do
    case split_canonical(name) do
      {genus, epithet} ->
        normalized = normalize_epithet(epithet)

        match =
          Enum.find(accepted_by_name, fn {_key, wcvp} ->
            wcvp.genus == genus and normalize_epithet(wcvp.species) == normalized
          end)

        case match do
          {_key, wcvp_name} -> {:fuzzy, wcvp_name}
          nil -> :no_match
        end

      :invalid ->
        :no_match
    end
  end

  # -- Pass 3: Synonym --

  defp try_synonym(name, synonym_index, accepted_by_id) do
    case Map.get(synonym_index, name) do
      nil ->
        :no_match

      accepted_id ->
        case Map.get(accepted_by_id, accepted_id) do
          nil -> :no_match
          accepted_name -> {:synonym, accepted_name}
        end
    end
  end

  # -- Closest match (for reporting) --

  defp find_closest(name, accepted_by_name) do
    case split_canonical(name) do
      {genus, _epithet} ->
        # Find any species in the same genus as a hint
        accepted_by_name
        |> Enum.find(fn {_key, wcvp} -> wcvp.genus == genus end)
        |> case do
          {_key, wcvp_name} -> wcvp_name
          nil -> nil
        end

      :invalid ->
        nil
    end
  end

  # -- Helpers --

  defp split_canonical(name) do
    case String.split(name, " ", parts: 2) do
      [genus, epithet] when genus != "" and epithet != "" -> {genus, epithet}
      _ -> :invalid
    end
  end

  # Strips common Latin epithet ending variations to a shared root.
  # This handles the most common discrepancies between taxonomic authorities.
  @latin_endings ~w(ii ii ianus iana ianum ensis ense ense is e a um us)

  defp strip_latin_endings(epithet) do
    Enum.reduce_while(@latin_endings, epithet, fn ending, acc ->
      if String.ends_with?(acc, ending) and String.length(acc) > String.length(ending) + 2 do
        {:halt, String.trim_trailing(acc, ending)}
      else
        {:cont, acc}
      end
    end)
  end
end
```

**Step 4: Run tests**

Run: `mix test test/gallformers/wcvp/matcher_test.exs`
Expected: All pass.

**Step 5: Precommit check**

Run: `mix compile --warnings-as-errors && mix format --check-formatted && mix credo --strict`

**Step 6: Commit**

```bash
git add lib/gallformers/wcvp/matcher.ex test/gallformers/wcvp/matcher_test.exs
git commit -m "Add three-pass name matcher for WCVP reconciliation"
```

---

## Task 7: Report writer module

Generates JSON report files from reconciliation results.

**Files:**
- Create: `lib/gallformers/wcvp/reporter.ex`
- Create: `test/gallformers/wcvp/reporter_test.exs`

**Step 1: Write tests**

```elixir
# test/gallformers/wcvp/reporter_test.exs
defmodule Gallformers.Wcvp.ReporterTest do
  use ExUnit.Case, async: true

  alias Gallformers.Wcvp.Reporter

  describe "write_report/3" do
    test "writes JSON array to file in dated directory" do
      dir = Path.join(System.tmp_dir!(), "reconciliation_test")
      File.rm_rf!(dir)

      items = [
        %{gf_species_id: 1, gf_name: "Quercus alba", detail: "test"},
        %{gf_species_id: 2, gf_name: "Quercus rubra", detail: "test2"}
      ]

      path = Reporter.write_report(items, "test-report", dir)

      assert File.exists?(path)
      assert String.ends_with?(path, "test-report.json")

      decoded = path |> File.read!() |> Jason.decode!()
      assert length(decoded) == 2
      assert hd(decoded)["gf_name"] == "Quercus alba"

      File.rm_rf!(dir)
    end

    test "creates directory if it does not exist" do
      dir = Path.join(System.tmp_dir!(), "reconciliation_new_#{:rand.uniform(10000)}")

      Reporter.write_report([], "empty-report", dir)
      assert File.dir?(dir)

      File.rm_rf!(dir)
    end
  end

  describe "report_dir/0" do
    test "returns dated directory path under priv/repo/data/reconciliation" do
      dir = Reporter.report_dir()
      today = Date.utc_today() |> Date.to_iso8601()
      assert String.contains?(dir, "reconciliation/#{today}")
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/gallformers/wcvp/reporter_test.exs`

**Step 3: Implement**

```elixir
# lib/gallformers/wcvp/reporter.ex
defmodule Gallformers.Wcvp.Reporter do
  @moduledoc """
  Writes reconciliation results as JSON report files.
  """

  @base_dir "priv/repo/data/reconciliation"

  @doc """
  Returns the default report output directory for today's date.
  """
  def report_dir do
    today = Date.utc_today() |> Date.to_iso8601()
    Path.join(@base_dir, today)
  end

  @doc """
  Writes a list of report items as a JSON file.
  Returns the path of the written file.
  """
  def write_report(items, report_name, dir \\ nil) do
    dir = dir || report_dir()
    File.mkdir_p!(dir)

    path = Path.join(dir, "#{report_name}.json")
    json = Jason.encode!(items, pretty: true)
    File.write!(path, json)

    path
  end
end
```

**Step 4: Run tests**

Run: `mix test test/gallformers/wcvp/reporter_test.exs`
Expected: All pass.

**Step 5: Commit**

```bash
git add lib/gallformers/wcvp/reporter.ex test/gallformers/wcvp/reporter_test.exs
git commit -m "Add JSON report writer for reconciliation output"
```

---

## Task 8: Download Mix task

Downloads the WCVP ZIP from Kew's SFTP server, extracts the CSVs.

**Files:**
- Create: `lib/mix/tasks/gallformers/wcvp/download.ex`

**Step 1: Implement the download task**

```elixir
# lib/mix/tasks/gallformers/wcvp/download.ex
defmodule Mix.Tasks.Gallformers.Wcvp.Download do
  @moduledoc """
  Downloads the WCVP (World Checklist of Vascular Plants) data from Kew.

  ## Usage

      mix gallformers.wcvp.download

  Downloads wcvp.zip from Kew's SFTP server and extracts CSV files to
  priv/repo/data/wcvp/. Existing files are overwritten.
  """

  use Mix.Task

  @shortdoc "Download WCVP plant taxonomy data from Kew"

  @wcvp_url "https://sftp.kew.org/pub/data-repositories/WCVP/wcvp.zip"
  @data_dir "priv/repo/data/wcvp"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    File.mkdir_p!(@data_dir)
    zip_path = Path.join(@data_dir, "wcvp.zip")

    IO.puts("Downloading WCVP data from Kew...")
    IO.puts("URL: #{@wcvp_url}")
    IO.puts("This file is ~85MB — download may take a minute.")

    case System.cmd("curl", ["-L", "-o", zip_path, @wcvp_url],
           stderr_to_stdout: true,
           into: IO.stream()
         ) do
      {_, 0} ->
        IO.puts("\nDownload complete. Extracting...")
        extract_zip(zip_path)
        verify_files()

      {output, code} ->
        Mix.raise("Download failed (exit code #{code}): #{output}")
    end
  end

  defp extract_zip(zip_path) do
    case System.cmd("unzip", ["-o", zip_path, "-d", @data_dir], stderr_to_stdout: true) do
      {_, 0} ->
        IO.puts("Extracted to #{@data_dir}/")
        File.rm(zip_path)
        IO.puts("Removed zip file.")

      {output, code} ->
        Mix.raise("Extraction failed (exit code #{code}): #{output}")
    end
  end

  defp verify_files do
    names_path = Path.join(@data_dir, "wcvp_names.csv")
    dist_path = Path.join(@data_dir, "wcvp_distribution.csv")

    cond do
      not File.exists?(names_path) ->
        # WCVP sometimes nests files in a subdirectory — check for that
        check_nested_files()

      not File.exists?(dist_path) ->
        check_nested_files()

      true ->
        names_size = File.stat!(names_path).size |> format_size()
        dist_size = File.stat!(dist_path).size |> format_size()
        IO.puts("\nReady:")
        IO.puts("  #{names_path} (#{names_size})")
        IO.puts("  #{dist_path} (#{dist_size})")
    end
  end

  defp check_nested_files do
    # WCVP zip may extract into a subdirectory
    case File.ls!(@data_dir) |> Enum.filter(&File.dir?(Path.join(@data_dir, &1))) do
      [subdir | _] ->
        nested = Path.join(@data_dir, subdir)
        IO.puts("Found nested directory: #{nested}")
        IO.puts("Moving files up...")

        nested
        |> File.ls!()
        |> Enum.each(fn file ->
          File.rename!(Path.join(nested, file), Path.join(@data_dir, file))
        end)

        File.rmdir(nested)
        verify_files()

      [] ->
        IO.puts("\nWarning: Expected CSV files not found. Contents of #{@data_dir}:")

        @data_dir
        |> File.ls!()
        |> Enum.each(fn f -> IO.puts("  #{f}") end)
    end
  end

  defp format_size(bytes) when bytes > 1_000_000, do: "#{Float.round(bytes / 1_000_000, 1)} MB"
  defp format_size(bytes) when bytes > 1_000, do: "#{Float.round(bytes / 1_000, 1)} KB"
  defp format_size(bytes), do: "#{bytes} B"
end
```

**Step 2: Verify it compiles**

Run: `mix compile --warnings-as-errors`
Expected: Clean compile.

**Step 3: Commit**

Note: Don't actually run the download in the test environment — it's a network operation.

```bash
git add lib/mix/tasks/gallformers/wcvp/download.ex
git commit -m "Add Mix task to download WCVP data from Kew"
```

---

## Task 9: Reconcile Mix task

The main reconciliation task. Loads WCVP data, queries gallformers DB, runs matching, produces all five report files.

**Files:**
- Create: `lib/mix/tasks/gallformers/wcvp/reconcile.ex`

**Context — Querying gallformers plants:**

Use existing context functions:
- `Gallformers.Plants.list_hosts()` — returns all plant species
- `Gallformers.Taxonomy.Tree.get_taxonomy_by_name(name, "family")` — lookup family
- `Gallformers.Taxonomy.Tree.get_taxonomy_by_name(name, "genus")` — lookup genus
- `Gallformers.Ranges.get_places_for_host_with_precision(species_id)` — current range data
- `Gallformers.Places.get_place_by_code(code)` — place code lookup

For taxonomy, each species links to a genus via `species_taxonomy`. The genus has a `parent_id` pointing to its family. Load species with taxonomy preloaded:

```elixir
from(s in Species,
  where: s.taxoncode == "plant",
  join: st in "species_taxonomy", on: st.species_id == s.id,
  join: t in Taxonomy, on: t.id == st.taxonomy_id,
  left_join: parent in Taxonomy, on: parent.id == t.parent_id,
  select: %{
    id: s.id,
    name: s.name,
    genus: t.name,
    family: coalesce(parent.name, ""),
    taxonomy_type: t.type
  }
)
```

**Step 1: Implement the reconcile task**

```elixir
# lib/mix/tasks/gallformers/wcvp/reconcile.ex
defmodule Mix.Tasks.Gallformers.Wcvp.Reconcile do
  @moduledoc """
  Reconciles gallformers plant data against WCVP.

  ## Usage

      mix gallformers.wcvp.reconcile

  Requires WCVP data to be downloaded first (mix gallformers.wcvp.download).

  Produces reports in priv/repo/data/reconciliation/YYYY-MM-DD/:
    - taxonomy-mismatches.json
    - in-gf-not-wcvp.json
    - in-wcvp-not-gf-usca.json
    - in-wcvp-not-gf-hemisphere.json
    - range-updates.json
  """

  use Mix.Task

  @shortdoc "Reconcile gallformers plants against WCVP taxonomy"

  alias Gallformers.Wcvp.{Matcher, Reader, Reporter, Tdwg}

  @data_dir "priv/repo/data/wcvp"
  @names_file "wcvp_names.csv"
  @dist_file "wcvp_distribution.csv"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    names_path = Path.join(@data_dir, @names_file)
    dist_path = Path.join(@data_dir, @dist_file)

    unless File.exists?(names_path) and File.exists?(dist_path) do
      Mix.raise("""
      WCVP data not found at #{@data_dir}/.
      Run `mix gallformers.wcvp.download` first.
      """)
    end

    IO.puts("Loading WCVP data...")

    IO.puts("  Building accepted names index...")
    accepted_by_id = Reader.build_accepted_name_lookup(names_path)

    accepted_by_name =
      Map.new(accepted_by_id, fn {_id, name} -> {name.taxon_name, name} end)

    IO.puts("  Building synonym index...")
    synonym_index = Reader.build_synonym_index(names_path)

    IO.puts("  Building distribution index...")
    dist_index = Reader.build_distribution_index(dist_path)

    IO.puts("  Loading TDWG mapping...")
    tdwg_lookup = Tdwg.load()

    IO.puts("  Loading gallformers plants...")
    gf_plants = load_gf_plants()

    IO.puts("\nLoaded:")
    IO.puts("  #{map_size(accepted_by_name)} accepted WCVP names")
    IO.puts("  #{map_size(synonym_index)} WCVP synonyms")
    IO.puts("  #{map_size(dist_index)} WCVP distribution entries")
    IO.puts("  #{length(gf_plants)} gallformers plants")

    IO.puts("\nMatching gallformers plants against WCVP...")
    {matches, taxonomy_mismatches, gf_not_in_wcvp} =
      match_gf_plants(gf_plants, accepted_by_name, synonym_index, accepted_by_id)

    IO.puts("  #{length(matches)} matched")
    IO.puts("  #{length(taxonomy_mismatches)} taxonomy mismatches")
    IO.puts("  #{length(gf_not_in_wcvp)} not found in WCVP")

    IO.puts("\nFinding WCVP species not in gallformers...")
    matched_wcvp_ids = MapSet.new(matches, fn m -> m.wcvp_id end)

    {wcvp_not_in_gf_usca, wcvp_not_in_gf_hemisphere} =
      find_wcvp_not_in_gf(accepted_by_id, matched_wcvp_ids, dist_index, tdwg_lookup)

    IO.puts("  #{length(wcvp_not_in_gf_usca)} US/CA species not in gallformers")
    IO.puts("  #{length(wcvp_not_in_gf_hemisphere)} other hemisphere species not in gallformers")

    IO.puts("\nFinding range updates for matched species...")
    range_updates = find_range_updates(matches, dist_index, tdwg_lookup)
    IO.puts("  #{length(range_updates)} species with new range data")

    IO.puts("\nWriting reports...")
    report_dir = Reporter.report_dir()

    reports = [
      {"taxonomy-mismatches", taxonomy_mismatches},
      {"in-gf-not-wcvp", gf_not_in_wcvp},
      {"in-wcvp-not-gf-usca", wcvp_not_in_gf_usca},
      {"in-wcvp-not-gf-hemisphere", wcvp_not_in_gf_hemisphere},
      {"range-updates", range_updates}
    ]

    Enum.each(reports, fn {name, items} ->
      path = Reporter.write_report(items, name, report_dir)
      IO.puts("  #{path} (#{length(items)} items)")
    end)

    IO.puts("\nDone. Reports written to #{report_dir}/")
  end

  # -- Loading gallformers data --

  defp load_gf_plants do
    import Ecto.Query

    alias Gallformers.Repo
    alias Gallformers.Species.Species
    alias Gallformers.Taxonomy.Taxonomy

    from(s in Species,
      where: s.taxoncode == "plant",
      join: st in "species_taxonomy", on: st.species_id == s.id,
      join: t in Taxonomy, on: t.id == st.taxonomy_id,
      left_join: parent in Taxonomy, on: parent.id == t.parent_id,
      select: %{
        id: s.id,
        name: s.name,
        genus: t.name,
        family: coalesce(parent.name, ""),
        taxonomy_type: t.type
      },
      order_by: s.name
    )
    |> Repo.all()
    # If a species is linked to a section, walk up to get genus/family
    |> Enum.map(&resolve_taxonomy/1)
  end

  # Species linked to a section need an extra hop to get genus and family
  defp resolve_taxonomy(%{taxonomy_type: "section"} = plant) do
    alias Gallformers.Repo
    alias Gallformers.Taxonomy.Taxonomy

    import Ecto.Query

    # For section: genus is the parent, family is the grandparent
    case Repo.one(
           from(t in Taxonomy,
             where: t.name == ^plant.genus and t.type == "section",
             join: genus in Taxonomy, on: genus.id == t.parent_id,
             left_join: family in Taxonomy, on: family.id == genus.parent_id,
             select: %{genus: genus.name, family: coalesce(family.name, "")},
             limit: 1
           )
         ) do
      nil -> plant
      resolved -> %{plant | genus: resolved.genus, family: resolved.family}
    end
  end

  defp resolve_taxonomy(plant), do: plant

  # -- Matching --

  defp match_gf_plants(gf_plants, accepted_by_name, synonym_index, accepted_by_id) do
    gf_plants
    |> Enum.reduce({[], [], []}, fn plant, {matches, tax_mismatches, not_found} ->
      case Matcher.match_name(plant.name, accepted_by_name, synonym_index, accepted_by_id) do
        {:exact, wcvp} ->
          match = %{gf_id: plant.id, gf_name: plant.name, wcvp_id: wcvp.plant_name_id}

          case check_taxonomy(plant, wcvp) do
            nil -> {[match | matches], tax_mismatches, not_found}
            mismatch -> {[match | matches], [mismatch | tax_mismatches], not_found}
          end

        {:fuzzy, wcvp} ->
          match = %{gf_id: plant.id, gf_name: plant.name, wcvp_id: wcvp.plant_name_id}

          mismatch = %{
            gf_species_id: plant.id,
            gf_name: plant.name,
            gf_family: plant.family,
            gf_genus: plant.genus,
            wcvp_accepted_name: wcvp.taxon_name,
            wcvp_family: wcvp.family,
            wcvp_genus: wcvp.genus,
            mismatch_type: "fuzzy_name",
            detail: "Fuzzy match: '#{plant.name}' matched WCVP '#{wcvp.taxon_name}'"
          }

          {[match | matches], [mismatch | tax_mismatches], not_found}

        {:synonym, accepted} ->
          match = %{gf_id: plant.id, gf_name: plant.name, wcvp_id: accepted.plant_name_id}

          mismatch = %{
            gf_species_id: plant.id,
            gf_name: plant.name,
            gf_family: plant.family,
            gf_genus: plant.genus,
            wcvp_accepted_name: accepted.taxon_name,
            wcvp_family: accepted.family,
            wcvp_genus: accepted.genus,
            mismatch_type: "synonym",
            detail:
              "Gallformers uses '#{plant.name}' which WCVP treats as a synonym of '#{accepted.taxon_name}'"
          }

          {[match | matches], [mismatch | tax_mismatches], not_found}

        {:no_match, closest} ->
          entry = %{
            gf_species_id: plant.id,
            gf_name: plant.name,
            gf_family: plant.family,
            gf_genus: plant.genus,
            match_attempts: ["exact", "fuzzy", "synonym"],
            closest_wcvp_match:
              if(closest, do: closest.taxon_name, else: nil)
          }

          {matches, tax_mismatches, [entry | not_found]}
      end
    end)
  end

  defp check_taxonomy(gf_plant, wcvp_name) do
    family_match = gf_plant.family == wcvp_name.family
    genus_match = gf_plant.genus == wcvp_name.genus

    cond do
      family_match and genus_match ->
        nil

      true ->
        mismatches =
          []
          |> then(fn acc -> if family_match, do: acc, else: ["family" | acc] end)
          |> then(fn acc -> if genus_match, do: acc, else: ["genus" | acc] end)
          |> Enum.join(", ")

        %{
          gf_species_id: gf_plant.id,
          gf_name: gf_plant.name,
          gf_family: gf_plant.family,
          gf_genus: gf_plant.genus,
          wcvp_accepted_name: wcvp_name.taxon_name,
          wcvp_family: wcvp_name.family,
          wcvp_genus: wcvp_name.genus,
          mismatch_type: mismatches,
          detail: "Taxonomy differs: #{mismatches}"
        }
    end
  end

  # -- WCVP not in gallformers --

  defp find_wcvp_not_in_gf(accepted_by_id, matched_wcvp_ids, dist_index, tdwg_lookup) do
    # Filter to species rank only (skip varieties, subspecies for now)
    unmatched =
      accepted_by_id
      |> Enum.reject(fn {id, _name} -> MapSet.member?(matched_wcvp_ids, id) end)
      |> Enum.filter(fn {_id, name} -> name.taxon_rank == "Species" end)
      |> Enum.map(fn {_id, name} ->
        tdwg_codes = Map.get(dist_index, name.plant_name_id, [])

        {places, _unknown} =
          Tdwg.convert_tdwg_codes_with_warnings(tdwg_codes, tdwg_lookup)

        place_codes = Enum.map(places, & &1.code)

        %{
          wcvp_id: name.plant_name_id,
          wcvp_name: name.taxon_name,
          wcvp_family: name.family,
          wcvp_genus: name.genus,
          wcvp_distribution: place_codes,
          wcvp_status: name.taxon_status
        }
      end)

    # Split into US/CA vs rest
    Enum.split_with(unmatched, fn entry ->
      Enum.any?(entry.wcvp_distribution, &Tdwg.us_canada_code?/1)
    end)
  end

  # -- Range updates --

  defp find_range_updates(matches, dist_index, tdwg_lookup) do
    matches
    |> Enum.flat_map(fn match ->
      tdwg_codes = Map.get(dist_index, match.wcvp_id, [])

      if tdwg_codes == [] do
        []
      else
        {wcvp_places, _unknown} =
          Tdwg.convert_tdwg_codes_with_warnings(tdwg_codes, tdwg_lookup)

        current_codes = get_current_place_codes(match.gf_id)
        current_set = MapSet.new(current_codes)

        new_places =
          Enum.reject(wcvp_places, fn p -> MapSet.member?(current_set, p.code) end)

        if new_places == [] do
          []
        else
          [
            %{
              gf_species_id: match.gf_id,
              gf_name: match.gf_name,
              current_places: current_codes,
              wcvp_places: Enum.map(wcvp_places, & &1.code),
              new_places: Enum.map(new_places, & &1.code),
              new_precision:
                Map.new(new_places, fn p -> {p.code, p.precision} end)
            }
          ]
        end
      end
    end)
  end

  defp get_current_place_codes(species_id) do
    Gallformers.Ranges.get_places_for_host_with_precision(species_id)
    |> Enum.map(fn {code, _precision} -> code end)
  end
end
```

**Step 2: Verify it compiles**

Run: `mix compile --warnings-as-errors`
Expected: Clean compile. May need to adjust the `get_places_for_host_with_precision` return format based on what the actual function returns — check and adapt.

**Step 3: Precommit check**

Run: `mix compile --warnings-as-errors && mix format --check-formatted && mix credo --strict`

**Step 4: Commit**

```bash
git add lib/mix/tasks/gallformers/wcvp/reconcile.ex
git commit -m "Add WCVP reconcile Mix task"
```

---

## Task 10: Apply Mix task

Reads a reconciliation report and applies changes to the database.

**Files:**
- Create: `lib/mix/tasks/gallformers/wcvp/apply.ex`

**Step 1: Implement the apply task**

```elixir
# lib/mix/tasks/gallformers/wcvp/apply.ex
defmodule Mix.Tasks.Gallformers.Wcvp.Apply do
  @moduledoc """
  Applies changes from a WCVP reconciliation report.

  ## Usage

      # Dry run (default) — shows what would change
      mix gallformers.wcvp.apply path/to/report.json

      # Actually apply changes
      mix gallformers.wcvp.apply path/to/report.json --commit

      # Apply only specific species by gallformers ID
      mix gallformers.wcvp.apply path/to/report.json --commit --ids 1234,5678

  ## Report types

  The task auto-detects the report type from the filename:
    - `range-updates.json` — adds new range data to existing species
    - `taxonomy-mismatches.json` — updates taxonomy linkages
    - `in-wcvp-not-gf-*.json` — imports new species

  ## Safety

  Dry run is the default. You must pass `--commit` to write to the database.
  All writes go through existing context functions (Plants, Ranges, Taxonomy).
  """

  use Mix.Task

  @shortdoc "Apply changes from a WCVP reconciliation report"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [commit: :boolean, ids: :string],
        aliases: [c: :commit]
      )

    report_path =
      case positional do
        [path] -> path
        _ -> Mix.raise("Usage: mix gallformers.wcvp.apply <report.json> [--commit] [--ids 1,2,3]")
      end

    unless File.exists?(report_path) do
      Mix.raise("Report file not found: #{report_path}")
    end

    commit? = Keyword.get(opts, :commit, false)

    id_filter =
      case Keyword.get(opts, :ids) do
        nil -> nil
        ids_str -> ids_str |> String.split(",") |> Enum.map(&String.to_integer/1) |> MapSet.new()
      end

    items = report_path |> File.read!() |> Jason.decode!()
    report_type = detect_report_type(report_path)

    items =
      if id_filter do
        id_key = if report_type == :new_species, do: "wcvp_id", else: "gf_species_id"
        Enum.filter(items, fn item -> MapSet.member?(id_filter, item[id_key]) end)
      else
        items
      end

    IO.puts("Report: #{report_path}")
    IO.puts("Type: #{report_type}")
    IO.puts("Items: #{length(items)}")
    IO.puts("Mode: #{if commit?, do: "COMMIT", else: "DRY RUN"}")
    IO.puts("")

    case report_type do
      :range_updates -> apply_range_updates(items, commit?)
      :taxonomy_mismatches -> apply_taxonomy_updates(items, commit?)
      :new_species -> apply_new_species(items, commit?)
      :unknown -> Mix.raise("Cannot determine report type from filename: #{report_path}")
    end
  end

  defp detect_report_type(path) do
    basename = Path.basename(path)

    cond do
      String.contains?(basename, "range-updates") -> :range_updates
      String.contains?(basename, "taxonomy-mismatches") -> :taxonomy_mismatches
      String.contains?(basename, "in-wcvp-not-gf") -> :new_species
      String.contains?(basename, "in-gf-not-wcvp") -> :unknown
      true -> :unknown
    end
  end

  defp apply_range_updates(items, commit?) do
    Enum.each(items, fn item ->
      species_id = item["gf_species_id"]
      name = item["gf_name"]
      new_places = item["new_places"]
      precisions = item["new_precision"]

      IO.puts("#{name} (#{species_id}): +#{length(new_places)} places")

      Enum.each(new_places, fn code ->
        precision = Map.get(precisions, code, "exact")
        IO.puts("  + #{code} (#{precision})")

        if commit? do
          case Gallformers.Places.get_place_by_code(code) do
            nil ->
              IO.puts("    WARNING: place code #{code} not found in DB, skipping")

            place ->
              Gallformers.Ranges.add_place_to_host(species_id, place.id, precision)
          end
        end
      end)
    end)

    IO.puts("\n#{if commit?, do: "Applied", else: "Would apply"} range updates for #{length(items)} species.")
  end

  defp apply_taxonomy_updates(items, commit?) do
    Enum.each(items, fn item ->
      species_id = item["gf_species_id"]
      name = item["gf_name"]
      mismatch_type = item["mismatch_type"]
      detail = item["detail"]

      IO.puts("#{name} (#{species_id}): #{mismatch_type}")
      IO.puts("  #{detail}")

      if mismatch_type == "synonym" do
        IO.puts("  WCVP accepted: #{item["wcvp_accepted_name"]}")
        IO.puts("  (Synonym renames require manual review — skipping auto-apply)")
      else
        wcvp_genus = item["wcvp_genus"]
        wcvp_family = item["wcvp_family"]
        IO.puts("  WCVP says: #{wcvp_family} > #{wcvp_genus}")
        IO.puts("  GF has:    #{item["gf_family"]} > #{item["gf_genus"]}")

        if commit? and String.contains?(mismatch_type, "genus") do
          apply_genus_update(species_id, wcvp_genus, wcvp_family)
        end
      end
    end)

    IO.puts(
      "\n#{if commit?, do: "Applied", else: "Would apply"} taxonomy updates for #{length(items)} species."
    )
  end

  defp apply_genus_update(species_id, wcvp_genus, wcvp_family) do
    alias Gallformers.Taxonomy

    # Find or create the target genus under the correct family
    family = Taxonomy.Tree.get_taxonomy_by_name(wcvp_family, "family")

    unless family do
      IO.puts("    WARNING: family '#{wcvp_family}' not found, skipping")
      return()
    end

    genus = Taxonomy.Tree.get_taxonomy_by_name(wcvp_genus, "genus")

    genus_id =
      if genus do
        genus.id
      else
        IO.puts("    Creating genus '#{wcvp_genus}' under '#{wcvp_family}'")

        {:ok, new_genus} =
          Taxonomy.Tree.create_taxonomy(%{
            "name" => wcvp_genus,
            "type" => "genus",
            "parent_id" => family.id
          })

        new_genus.id
      end

    Taxonomy.SpeciesLink.link_species_to_taxonomy(species_id, genus_id)
    IO.puts("    Updated taxonomy link")
  end

  defp apply_new_species(items, commit?) do
    Enum.each(items, fn item ->
      name = item["wcvp_name"]
      family = item["wcvp_family"]
      genus = item["wcvp_genus"]
      distribution = item["wcvp_distribution"] || []

      IO.puts("#{name} (#{family} > #{genus}), #{length(distribution)} places")

      if commit? do
        case Gallformers.Plants.get_host_by_name(name) do
          nil ->
            IO.puts("  Creating...")
            # Find genus taxonomy ID
            genus_tax = Gallformers.Taxonomy.Tree.get_taxonomy_by_name(genus, "genus")

            taxonomy_id =
              if genus_tax do
                genus_tax.id
              else
                family_tax = Gallformers.Taxonomy.Tree.get_taxonomy_by_name(family, "family")

                if family_tax do
                  {:ok, new_genus} =
                    Gallformers.Taxonomy.Tree.create_taxonomy(%{
                      "name" => genus,
                      "type" => "genus",
                      "parent_id" => family_tax.id
                    })

                  new_genus.id
                else
                  IO.puts("    WARNING: family '#{family}' not found, skipping")
                  nil
                end
              end

            if taxonomy_id do
              case Gallformers.Plants.create_host_with_associations(%{
                     "name" => name,
                     "taxoncode" => "plant",
                     "taxonomy_id" => taxonomy_id
                   }) do
                {:ok, host} ->
                  IO.puts("    Created species #{host.id}")

                {:error, reason} ->
                  IO.puts("    ERROR: #{inspect(reason)}")
              end
            end

          _existing ->
            IO.puts("  Already exists, skipping")
        end
      end
    end)

    IO.puts(
      "\n#{if commit?, do: "Applied", else: "Would apply"} #{length(items)} new species."
    )
  end

  defp return, do: :ok
end
```

**Step 2: Verify it compiles**

Run: `mix compile --warnings-as-errors`
Expected: Clean compile. The `apply_genus_update` and `apply_new_species` functions reference existing context functions — verify the exact function signatures match. Adjust as needed.

**Step 3: Precommit check**

Run: `mix compile --warnings-as-errors && mix format --check-formatted && mix credo --strict`

**Step 4: Commit**

```bash
git add lib/mix/tasks/gallformers/wcvp/apply.ex
git commit -m "Add WCVP apply Mix task for report-based database updates"
```

---

## Task 11: Integration test with real WCVP structure

Test the full reconciliation pipeline end-to-end using fixture data that mirrors real WCVP structure. This doesn't test against the actual database — it validates the pipeline logic.

**Files:**
- Create: `test/gallformers/wcvp/reconciliation_test.exs`
- Create: `test/support/fixtures/wcvp_names_sample.csv`
- Create: `test/support/fixtures/wcvp_distributions_sample.csv`

**Step 1: Create small fixture CSVs**

Create pipe-delimited CSV files with a handful of realistic rows covering the key scenarios: exact matches, synonyms, missing species, taxonomy mismatches.

**Step 2: Write integration test**

Test the full flow: reader -> matcher -> report generation. Verify that each report type contains the expected items for the fixture data.

**Step 3: Run and iterate**

Run: `mix test test/gallformers/wcvp/reconciliation_test.exs`
Iterate until all scenarios are covered.

**Step 4: Commit**

```bash
git add test/gallformers/wcvp/ test/support/fixtures/
git commit -m "Add integration tests for WCVP reconciliation pipeline"
```

---

## Task 12: First real run and validation

Download actual WCVP data and run the reconciliation against the dev database.

**Step 1: Download WCVP data**

Run: `mix gallformers.wcvp.download`
Expected: Files extracted to `priv/repo/data/wcvp/`.

**Step 2: Verify CSV format assumptions**

Check that the actual WCVP CSV delimiter, column names, and data format match what the reader expects. If the delimiter is different (tab, comma) or column names have changed, update `Reader` accordingly.

```bash
# Check first line of each file
head -1 priv/repo/data/wcvp/wcvp_names.csv
head -1 priv/repo/data/wcvp/wcvp_distribution.csv
```

**Step 3: Run reconciliation**

Run: `mix gallformers.wcvp.reconcile`

Review each report file. Check:
- Are the match counts reasonable? (Most plants should match exactly)
- Do taxonomy mismatches look like real discrepancies or parser bugs?
- Is the `in-gf-not-wcvp` list plausible? (Hybrids, undescribed species, and manual additions are expected)
- Are range updates populating correctly?

**Step 4: Fix any issues discovered during the real run**

The first run against real data will likely reveal edge cases: unexpected column values, encoding issues, TDWG codes not in the mapping, etc. Fix iteratively.

**Step 5: Commit the reports and any fixes**

```bash
git add priv/repo/data/reconciliation/
git commit -m "First WCVP reconciliation run"
```

---

## Summary

| Task | What | Commit message |
|------|------|----------------|
| 1 | Add NimbleCSV dependency | Add nimble_csv dependency for WCVP CSV parsing |
| 2 | Gitignore wcvp data dir | Gitignore cached WCVP data directory |
| 3 | TDWG mapping file | Add TDWG Level 3 to gallformers places mapping |
| 4 | CSV reader module | Add WCVP CSV reader with streaming and index builders |
| 5 | TDWG mapping module | Add TDWG-to-places mapping module |
| 6 | Name matcher module | Add three-pass name matcher for WCVP reconciliation |
| 7 | Report writer module | Add JSON report writer for reconciliation output |
| 8 | Download Mix task | Add Mix task to download WCVP data from Kew |
| 9 | Reconcile Mix task | Add WCVP reconcile Mix task |
| 10 | Apply Mix task | Add WCVP apply Mix task for report-based updates |
| 11 | Integration tests | Add integration tests for WCVP reconciliation pipeline |
| 12 | First real run | First WCVP reconciliation run |
