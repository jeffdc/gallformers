defmodule Gallformers.Curation.FromObservation do
  @moduledoc """
  Add from observation (matter `ec2c`): one iNaturalist observation read
  into proposed tray items, for the curator to confirm
  (`Gallformers.Curation.from_observation/3`). Nothing is added to the
  tray here.

    * **The recorded occurrence:** iNaturalist's state or province (and
      country) of the observation, as our place
      (`Gallformers.Places.match_subdivision/2`), dated as seen (`when`,
      the observed date). Never a season Fact: when a Gall was seen is not
      when it forms.
    * **The Host:** the "Host Plant ID" observation field, and the plant
      names in the description (binomials of a plant genus the tree holds,
      and abbreviations such as "Q. alba"), resolved as intake resolves a
      batch's Hosts (`Gallformers.Import.resolve_host_names/2`). Each match
      is offered; with none, the curator is told to give the Host.
    * **The Gall:** the one given; otherwise the Galls of the observation's
      taxon as Inducer (its subtree), one pre-selected when it is the only
      one, or when the observation's "Gallformers Code" field names a Gall.
    * **Evidence:** the observation, for every item.
    * **Photos:** the observation's, with the parsed observation, for the
      iNaturalist image import (`GallformersWeb.Admin.InatImportComponent`).
  """
  alias Gallformers.Catalog
  alias Gallformers.Catalog.Gall
  alias Gallformers.Curation.Wording
  alias Gallformers.Facts
  alias Gallformers.Import
  alias Gallformers.INaturalist
  alias Gallformers.INaturalist.Observation
  alias Gallformers.Places
  alias Gallformers.Repo
  alias Gallformers.Taxa

  @plantae "Plantae"
  @host_field "Host Plant ID"
  @code_field "Gallformers Code"
  @country_level 0
  @state_level 10

  @binomial ~r/\b([A-Z][a-z]+)\s+(?:(?:×|x)\s+)?([a-z][a-z-]{2,})\b/u
  @abbreviated ~r/\b([A-Z])\.\s*([a-z][a-z-]{2,})\b/u

  @doc "See `Gallformers.Curation.from_observation/3`."
  @spec propose(String.t() | integer(), integer() | nil) :: {:ok, map()} | {:error, atom()}
  def propose(url_or_id, gall_id) do
    input = to_string(url_or_id)

    with {:ok, _id} <- INaturalist.parse_observation_id(input),
         :ok <- gall_exists(gall_id),
         {:ok, obs} <- fetch(input),
         {:ok, places} <- places(obs) do
      gall = gall(obs, gall_id)
      {occurrences, place_needs} = occurrences(obs, places, gall.gall_id)
      {hosts, host_needs} = hosts(obs, gall.gall_id)

      items =
        Enum.map(occurrences ++ hosts, &Map.put(&1, :held, held?(gall.gall_id, &1.spec.key)))

      {:ok,
       %{
         observation: %{
           id: obs.id,
           url: obs.url,
           taxon_name: obs.taxon_name,
           observed_on: obs.observed_on,
           place_guess: obs.place_guess,
           observer: INaturalist.format_creator(obs.observer_login, obs.observer_name)
         },
         inat_observation: obs,
         evidence: %{text: nil, observations: [evidence_observation(obs)], source_id: nil},
         gall: Map.take(gall, [:gall_id, :candidates, :why]),
         taxon: taxon(obs, gall.gall_id),
         items: items,
         needs: gall_needs(gall) ++ place_needs ++ host_needs,
         photos: obs.photos
       }}
    end
  end

  # The observation as the statements' evidence: with its quality grade
  # and its first photo's thumbnail, when it has them (87a1).
  defp evidence_observation(%Observation{} = obs) do
    %{provider: "inaturalist", id: to_string(obs.id)}
    |> put_present(:quality_grade, obs.quality_grade)
    |> put_present(:thumbnail_url, Enum.find_value(obs.photos, & &1.thumbnail_url))
  end

  defp put_present(map, _key, value) when value in [nil, ""], do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp gall_exists(nil), do: :ok

  defp gall_exists(id) when is_integer(id),
    do: if(Catalog.get_gall(id), do: :ok, else: {:error, :no_such_gall})

  defp gall_exists(_id), do: {:error, :no_such_gall}

  defp fetch(input) do
    case INaturalist.fetch_observation(input) do
      {:ok, obs} -> {:ok, obs}
      {:error, reason} when reason in [:invalid_input, :not_found] -> {:error, reason}
      {:error, _reason} -> {:error, :unavailable}
    end
  end

  # iNaturalist's country and state or province of the observation.
  defp places(%Observation{place_ids: ids}) do
    case INaturalist.fetch_places(ids) do
      {:ok, places} ->
        {:ok,
         %{
           country: level_name(places, @country_level),
           state: level_name(places, @state_level)
         }}

      {:error, _reason} ->
        {:error, :unavailable}
    end
  end

  defp level_name(places, level),
    do: Enum.find_value(places, &(&1.admin_level == level && &1.name))

  # -- the Gall ----------------------------------------------------------------

  defp gall(_obs, gall_id) when is_integer(gall_id) do
    card = card(Catalog.get_gall!(gall_id))
    %{gall_id: gall_id, candidates: [card], why: "The Gall you are adding to."}
  end

  defp gall(obs, nil) do
    inducers = inducers(obs.taxon_name)
    candidates = taxon_galls(inducers)

    coded = coded_gall(obs)

    candidates =
      if coded && not Enum.any?(candidates, &(&1.id == coded.id)),
        do: [card(coded) | candidates],
        else: candidates

    {gall_id, why} =
      cond do
        coded ->
          {coded.id, "The observation's #{@code_field} field is #{coded.gallformers_code}."}

        match?([_], candidates) ->
          {hd(candidates).id, "The only Gall of #{obs.taxon_name} in Gallformers."}

        true ->
          {nil, nil}
      end

    %{
      gall_id: gall_id,
      candidates: candidates,
      why: why,
      inducer: obs.taxon_name,
      inducer_found: inducers != []
    }
  end

  # The Galls the taxa (or a taxon under them) induce.
  defp taxon_galls([]), do: []

  defp taxon_galls(taxa) do
    taxa
    |> Enum.map(& &1.id)
    |> Taxa.subtree_ids()
    |> Map.values()
    |> List.flatten()
    |> Enum.uniq()
    |> Catalog.list_galls_for_inducers()
  end

  # Whether the observation's taxon is the Gall's Inducer (the Gall is one
  # its taxon, or a taxon under it, induces), and that taxon's other Galls:
  # an observation of another taxon is warned about, not refused (87a1). No
  # taxon, or no Gall yet, warns of nothing.
  defp taxon(%Observation{taxon_name: nil}, _gall_id), do: %{name: nil, matches?: true, galls: []}

  defp taxon(obs, gall_id) do
    galls = obs.taxon_name |> inducers() |> taxon_galls()

    %{
      name: obs.taxon_name,
      matches?: gall_id == nil or Enum.any?(galls, &(&1.id == gall_id)),
      galls: Enum.reject(galls, &(&1.id == gall_id))
    }
  end

  # Whether Gall `gall_id` holds the Fact `key` names already, current.
  defp held?(nil, _key), do: false

  defp held?(gall_id, key) do
    case Catalog.find_gall_fact(gall_id, key) do
      {:ok, fact_id} when is_integer(fact_id) -> Facts.get_fact!(fact_id).standing == :current
      _ -> false
    end
  end

  defp inducers(nil), do: []

  defp inducers(name) do
    case Taxa.resolve_name(name) do
      {:ok, taxon} -> [taxon]
      {:ambiguous, taxa} -> taxa
      :none -> []
    end
    |> Enum.reject(&(&1.kingdom == @plantae))
  end

  defp coded_gall(obs) do
    case INaturalist.field_value(obs, @code_field) do
      nil -> nil
      code -> Repo.get_by(Gall, gallformers_code: code)
    end
  end

  defp card(%Gall{} = gall),
    do: %{
      id: gall.id,
      name: Wording.subject_name({:gall, gall.id}),
      datacomplete: gall.datacomplete
    }

  defp gall_needs(%{gall_id: id}) when is_integer(id), do: []

  defp gall_needs(%{candidates: [_ | _] = candidates, inducer: inducer}) do
    [
      %{
        kind: :gall,
        text: "Choose the Gall: Gallformers has #{length(candidates)} Galls of #{inducer}."
      }
    ]
  end

  defp gall_needs(%{inducer: nil}),
    do: [%{kind: :gall, text: "The observation has no taxon: choose the Gall."}]

  defp gall_needs(%{inducer: inducer, inducer_found: true}),
    do: [
      %{
        kind: :gall,
        text: "No Gall in Gallformers has #{inducer} as its Inducer: choose the Gall."
      }
    ]

  defp gall_needs(%{inducer: inducer}),
    do: [%{kind: :gall, text: "#{inducer} is not in Gallformers: choose the Gall."}]

  # -- the recorded occurrence -------------------------------------------------

  defp occurrences(obs, %{state: state, country: country}, gall_id) do
    where = Enum.reject([state, country], &is_nil/1) |> Enum.join(", ")

    case if(where == "", do: [], else: Places.match_subdivision(state, country)) do
      [] when where == "" ->
        {[], [%{kind: :place, text: "The observation has no place: give where it was seen."}]}

      [] ->
        {[],
         [
           %{
             kind: :place,
             text: "#{where} is not a place Gallformers holds: give where it was seen."
           }
         ]}

      [place] ->
        {[occurrence(obs, place, where, gall_id, true)], []}

      places ->
        {Enum.map(places, &occurrence(obs, &1, where, gall_id, false)),
         [%{kind: :place, text: "#{where} could be #{length(places)} places: choose one."}]}
    end
  end

  defp occurrence(obs, place, where, gall_id, selected) do
    seen = obs.observed_on && Date.to_iso8601(obs.observed_on)

    spec =
      %{kind: :fact, gall_id: gall_id, action: :add, key: {:occurrence, place.id}}
      |> then(&if(seen, do: Map.put(&1, :when, seen), else: &1))

    why =
      "iNaturalist observation #{obs.id} was made in #{where}" <>
        if(seen, do: " on #{seen}.", else: " (no date given).")

    item(:occurrence, spec, why, selected)
  end

  # -- the Host ----------------------------------------------------------------

  defp hosts(obs, gall_id) do
    field = INaturalist.field_value(obs, @host_field)
    named = description_names(obs.description, field)

    names =
      [{field, :field} | Enum.map(named, &{&1, :description})]
      |> Enum.reject(fn {name, _from} -> is_nil(name) end)
      |> Enum.uniq_by(fn {name, _from} -> fold(name) end)

    statements =
      Import.resolve_host_names(Enum.map(names, &elem(&1, 0)),
        document_texts: List.wrap(obs.description)
      )

    items =
      names
      |> Enum.zip(statements)
      |> Enum.flat_map(fn {{name, from}, statement} ->
        host_items(name, from, statement, gall_id)
      end)
      |> Enum.uniq_by(& &1.spec.key)

    field_statement = if field, do: hd(statements)

    needs =
      cond do
        field_statement && field_statement.resolution == :unresolved ->
          [
            %{
              kind: :host,
              text:
                "The #{@host_field} field's #{field} is no plant in Gallformers: give the Host, " <>
                  "or add the plant first."
            }
          ]

        items == [] ->
          [%{kind: :host, text: "No Host found in the observation: give the Host."}]

        true ->
          []
      end

    {items, needs}
  end

  defp host_items(name, from, %{resolution: :resolved, taxon_id: id} = statement, gall_id),
    do: [host_item(id, gall_id, why(name, from, statement), true)]

  defp host_items(name, from, %{resolution: :ambiguous} = statement, gall_id) do
    proposed = statement.detail["proposed"]

    why =
      why(name, from, statement) <>
        " It names #{length(statement.candidate_ids)} plants: choose one."

    for id <- statement.candidate_ids, do: host_item(id, gall_id, why, id == proposed)
  end

  # A field's name the tree does not hold: its suggestions the tree holds,
  # none pre-selected. A description's: nothing (the words may be no plant).
  defp host_items(name, :field, %{resolution: :unresolved} = statement, gall_id) do
    for id <- statement.candidate_ids,
        do:
          host_item(
            id,
            gall_id,
            why(name, :field, statement) <> " A suggestion, not a match.",
            false
          )
  end

  defp host_items(_name, _from, _statement, _gall_id), do: []

  defp host_item(taxon_id, gall_id, why, selected) do
    item(
      :host,
      %{kind: :fact, gall_id: gall_id, action: :add, key: {:host, taxon_id}},
      why,
      selected
    )
  end

  defp why(name, from, statement) do
    where =
      case from do
        :field -> "The observation's #{@host_field} field: #{name}."
        :description -> "Named in the observation's description: #{name}."
      end

    case statement do
      %{resolution: :resolved, taxon_id: id} ->
        accepted = Taxa.accepted_name(id)
        if fold(accepted) == fold(name), do: where, else: where <> " Read as #{accepted}."

      _ ->
        where
    end
  end

  # Plant names in a description: binomials whose genus is a plant genus
  # the tree holds, and abbreviations ("Q. alba") of such a genus — one the
  # description or the Host Plant ID field writes in full.
  defp description_names(nil, _field), do: []

  defp description_names(text, field) do
    binomials = Regex.scan(@binomial, text)
    genera = binomials |> Enum.map(&Enum.at(&1, 1)) |> Enum.concat(genus(field)) |> Enum.uniq()
    plant_genera = Enum.filter(genera, &plant_genus?/1)
    initials = MapSet.new(plant_genera, &String.first/1)

    full = for [name, genus | _] <- binomials, genus in plant_genera, do: name

    abbreviated =
      for [name, initial | _] <- Regex.scan(@abbreviated, text),
          MapSet.member?(initials, initial),
          do: name

    Enum.uniq(full ++ abbreviated)
  end

  defp genus(nil), do: []
  defp genus(name), do: Enum.take(String.split(name), 1)

  defp plant_genus?(name), do: Taxa.resolve_name(name, rank: :genus, kingdom: @plantae) != :none

  defp item(role, spec, why, selected),
    do: %{role: role, spec: spec, text: Wording.item_text(spec), why: why, selected: selected}

  defp fold(name), do: name |> String.split() |> Enum.join(" ") |> String.downcase()
end
