defmodule Gallformers.Curation.Spec do
  @moduledoc """
  The specs `Gallformers.Curation.add_item/2` takes and the evidence
  `set_evidence/2` takes (matter `ec2c`, "Items", "Evidence"): checked and
  normalized, stored with string keys and read back.

    * **Fact item:** `%{kind: :fact, gall_id, action: :add | :withdraw |
      :correct, key, to}` — `to` (a key of the same kind) only for
      `:correct`; `when` (text: when it was seen, "2025-07-14") only on
      adding a recorded occurrence. The key must name a Fact the Gall could have
      (`Gallformers.Catalog.find_gall_fact/2`): a taxon, plant and place
      that exist, a Trait value the vocabulary holds.
    * **Note:** `%{kind: :note, gall_id, key, text}` — on a Fact the Gall
      has.
    * **Reading fix:** `%{kind: :reading, gall_id, source_id, key, to}`
      (matter `87a1`) — Source `source_id` states the Fact `key` with its
      quotes, and Gallformers read it wrongly: `to` (a key of the same
      kind, or several: a Trait's values) is what it says in its place,
      nil that it doesn't say this.
      Refused for a Source that doesn't state it (`:not_stated`), one of
      Gallformers' own (`:own_source`) and a statement with no quotes
      (`:no_quotes`).
    * **Editorial item:** `%{kind: :editorial, subject: {:gall, id} |
      {:plant, id}, field, value}`, plus `based_on` (text) on a plant's.
      Gall fields: `:completeness` (boolean), `:abundance` (an abundance
      ID or nil), `:code` (text or nil), `:name_parts` (a map of
      `:form_label`, `:descriptor`, `:host_qualifier_taxon_id`,
      `:name_override`), `:default_source_id` (a Source ID or nil). Plant
      fields: `:name` (text), `:authorship` (its accepted name's, text or
      nil), `:synonyms` (the synonyms it should have: names, or
      `%{name, sensu}`), `:range` (its Host range:
      `{place_id, precision, distribution_type}` entries).
  """
  alias Gallformers.Catalog
  alias Gallformers.Curation.Key
  alias Gallformers.Facts
  alias Gallformers.Places
  alias Gallformers.Repo
  alias Gallformers.Sources
  alias Gallformers.Taxa

  @gall_fields [:completeness, :abundance, :code, :name_parts, :default_source_id]
  @plant_fields [:name, :authorship, :synonyms, :range]
  @name_parts [:form_label, :descriptor, :host_qualifier_taxon_id, :name_override]
  @providers ["inaturalist", "bugguide"]

  @typedoc "A checked item: what `change_set_items` stores of it."
  @type checked :: %{
          required(:kind) => :fact | :note | :editorial | :photo | :reading,
          required(:subject) => {:gall | :plant, integer()},
          required(:key) => Key.t(),
          required(:stored) => map(),
          optional(:source_id) => integer()
        }

  @doc "The editorial fields of a Gall and of a plant."
  @spec fields(:gall | :plant) :: [atom()]
  def fields(:gall), do: @gall_fields
  def fields(:plant), do: @plant_fields

  # -- items ---------------------------------------------------------------------

  @doc "Checks a spec: `{:ok, checked}` or `{:error, reason}`."
  @spec check(map()) :: {:ok, checked()} | {:error, atom()}
  def check(%{kind: :fact, gall_id: gall_id, action: action, key: key} = spec)
      when action in [:add, :withdraw, :correct] do
    to = spec[:to]

    with :ok <- gall(gall_id),
         :ok <- fact_key(gall_id, key),
         :ok <- correction(action, key, to),
         {:ok, seen_when} <- seen_when(action, key, Map.get(spec, :when)) do
      {:ok,
       %{
         kind: :fact,
         subject: {:gall, gall_id},
         key: key,
         stored:
           %{"action" => Atom.to_string(action), "to" => to && Key.encode(to)}
           |> put_present("when", seen_when)
       }}
    end
  end

  def check(%{kind: :note, gall_id: gall_id, key: key, text: text}) when is_binary(text) do
    with :ok <- gall(gall_id),
         :ok <- fact_key(gall_id, key),
         :ok <- present(text),
         {:ok, fact_id} when is_integer(fact_id) <- Catalog.find_gall_fact(gall_id, key) do
      {:ok,
       %{kind: :note, subject: {:gall, gall_id}, key: key, stored: %{"text" => String.trim(text)}}}
    else
      {:ok, nil} -> {:error, :no_fact}
      {:error, reason} -> {:error, reason}
    end
  end

  def check(%{kind: :editorial, subject: {type, id}, field: field} = spec)
      when type in [:gall, :plant] and is_integer(id) do
    value = Map.get(spec, :value)

    with :ok <- subject(type, id),
         :ok <- field(type, field),
         {:ok, stored_value} <- value(field, value),
         {:ok, based_on} <- based_on(type, spec[:based_on]) do
      {:ok,
       %{
         kind: :editorial,
         subject: {type, id},
         key: {:editorial, field},
         stored: %{
           "field" => Atom.to_string(field),
           "value" => stored_value,
           "based_on" => based_on
         }
       }}
    end
  end

  # Fixing how Gallformers read a Source's statement of a Fact (matter
  # `87a1`): what it does say in its place (`to`, a key of the same kind),
  # or nil, that it doesn't say this.
  def check(%{kind: :reading} = spec), do: check_reading(spec, tray: true)

  # An iNaturalist observation's photo for a Gall (matter `87a1`).
  def check(%{kind: :photo, gall_id: gall_id, observation_id: obs_id, photo_id: photo_id})
      when is_integer(gall_id) and is_integer(obs_id) and is_integer(photo_id) do
    with :ok <- subject(:gall, gall_id) do
      {:ok,
       %{
         kind: :photo,
         subject: {:gall, gall_id},
         key: {:photo, obs_id, photo_id},
         stored: %{"observation_id" => obs_id, "photo_id" => photo_id}
       }}
    end
  end

  def check(_spec), do: {:error, :invalid_spec}

  @doc """
  Checks a reading fix's spec: `{:ok, checked}` or `{:error, reason}`. In
  the tray (`tray: true`, `check/1`'s) the Source must not be one of
  Gallformers' own (`:own_source`: its statements change as Gallformers'
  do) and must quote what it says (`:no_quotes`); fixed at once, from the
  admin Source page (`tray: false`), any Source that states the Fact.
  """
  @spec check_reading(map(), keyword()) :: {:ok, checked()} | {:error, atom()}
  def check_reading(%{kind: :reading, gall_id: gall_id, source_id: source_id, key: key} = spec,
        tray: tray?
      ) do
    to = spec[:to]

    with :ok <- gall(gall_id),
         :ok <- fact_key(gall_id, key),
         :ok <- reading_to(gall_id, key, to),
         :ok <- states(gall_id, source_id, key, tray?) do
      {:ok,
       %{
         kind: :reading,
         subject: {:gall, gall_id},
         key: key,
         source_id: source_id,
         stored: %{"source_id" => source_id, "to" => encode_to(to)}
       }}
    end
  end

  def check_reading(_spec, _opts), do: {:error, :invalid_spec}

  defp gall(id) when is_integer(id),
    do: if(Catalog.get_gall(id), do: :ok, else: {:error, :no_such_gall})

  defp gall(_id), do: {:error, :no_such_gall}

  defp subject(:gall, id), do: gall(id)

  defp subject(:plant, id) do
    case Taxa.get_taxon(id) do
      %{kingdom: "Plantae"} -> :ok
      _ -> {:error, :no_such_plant}
    end
  end

  defp field(type, field), do: if(field in fields(type), do: :ok, else: {:error, :unknown_field})

  defp fact_key(gall_id, key) do
    with true <- Key.fact?(key) || {:error, :invalid_key},
         :ok <- exists(key) do
      case Catalog.find_gall_fact(gall_id, key) do
        {:ok, _fact_id} -> :ok
        {:error, _reason} -> {:error, :invalid_key}
      end
    end
  end

  defp exists({role, taxon_id}) when role in [:inducer, :host],
    do: if(Taxa.get_taxon(taxon_id), do: :ok, else: {:error, :no_such_taxon})

  defp exists({:range, _adjustment, place_id}), do: place(place_id)
  defp exists({:occurrence, place_id}), do: place(place_id)
  defp exists({:alias, name}), do: present(name)
  defp exists(_key), do: :ok

  defp place(id), do: if(Places.get_place(id), do: :ok, else: {:error, :no_such_place})

  defp present(text) do
    if is_binary(text) and String.trim(text) != "", do: :ok, else: {:error, :invalid_spec}
  end

  defp reading_to(_gall_id, _key, nil), do: :ok

  # Several values: what the Source says, the misread one among them when
  # it says that too.
  defp reading_to(gall_id, key, [_, _ | _] = tos) do
    Enum.reduce_while(List.delete(tos, key), :ok, fn to, :ok ->
      case reading_to(gall_id, key, to) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp reading_to(gall_id, key, to) do
    with :ok <- correction(:correct, key, to), do: fact_key(gall_id, to)
  end

  defp encode_to(nil), do: nil
  defp encode_to(tos) when is_list(tos), do: Enum.map(tos, &Key.encode/1)
  defp encode_to(to), do: Key.encode(to)

  # The Source states the Fact, quoting what it says, and is not one of
  # Gallformers' own (their statements are changed as Gallformers changes).
  defp states(gall_id, source_id, key, tray?) when is_integer(source_id) do
    with {:ok, fact_id} when is_integer(fact_id) <- Catalog.find_gall_fact(gall_id, key),
         %{} = attribution <- Facts.get_attribution(fact_id, source_id) do
      cond do
        not tray? -> :ok
        source_id in Sources.own_source_ids() -> {:error, :own_source}
        Repo.preload(attribution, :evidence).evidence == [] -> {:error, :no_quotes}
        true -> :ok
      end
    else
      _ -> {:error, :not_stated}
    end
  end

  defp states(_gall_id, _source_id, _key, _tray?), do: {:error, :invalid_spec}

  defp correction(:correct, key, to) do
    if Key.fact?(to) and elem(to, 0) == elem(key, 0) and to != key,
      do: :ok,
      else: {:error, :invalid_spec}
  end

  defp correction(_action, _key, nil), do: :ok
  defp correction(_action, _key, _to), do: {:error, :invalid_spec}

  # When a recorded occurrence was seen, as written ("2025-07-14", "July
  # 1961"): only on adding one.
  defp seen_when(_action, _key, nil), do: {:ok, nil}

  defp seen_when(:add, {:occurrence, _place_id}, text) when is_binary(text) do
    case blank_nil(text) do
      nil -> {:error, :invalid_spec}
      trimmed -> {:ok, trimmed}
    end
  end

  defp seen_when(_action, _key, _when), do: {:error, :invalid_spec}

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp value(:completeness, value) when is_boolean(value), do: {:ok, value}
  defp value(field, nil) when field in [:abundance, :code, :default_source_id], do: {:ok, nil}

  defp value(field, id) when field in [:abundance, :default_source_id] and is_integer(id),
    do: {:ok, id}

  defp value(:code, code) when is_binary(code), do: {:ok, String.trim(code)}

  defp value(:name_parts, parts) when is_map(parts) do
    parts = Map.new(parts, fn {k, v} -> {to_string(k), v} end)
    allowed = Enum.map(@name_parts, &Atom.to_string/1)

    if parts != %{} and Enum.all?(Map.keys(parts), &(&1 in allowed)),
      do: {:ok, parts},
      else: {:error, :invalid_value}
  end

  defp value(:name, name) when is_binary(name) do
    if String.trim(name) == "", do: {:error, :invalid_value}, else: {:ok, String.trim(name)}
  end

  defp value(:authorship, nil), do: {:ok, nil}
  defp value(:authorship, text) when is_binary(text), do: {:ok, blank_nil(text)}

  defp value(:synonyms, synonyms) when is_list(synonyms) do
    normalized =
      Enum.map(synonyms, fn
        name when is_binary(name) ->
          %{"name" => String.trim(name), "sensu" => nil}

        %{} = s ->
          %{
            "name" => String.trim(to_string(s[:name] || s["name"])),
            "sensu" => blank_nil(s[:sensu] || s["sensu"])
          }
      end)

    if Enum.all?(normalized, &(&1["name"] != "")),
      do: {:ok, Enum.uniq_by(normalized, &{&1["name"], &1["sensu"]})},
      else: {:error, :invalid_value}
  end

  defp value(:range, entries) when is_list(entries) do
    if Enum.all?(
         entries,
         &match?({id, p, d} when is_integer(id) and is_binary(p) and is_binary(d), &1)
       ),
       do: {:ok, Enum.map(entries, &Tuple.to_list/1)},
       else: {:error, :invalid_value}
  end

  defp value(_field, _value), do: {:error, :invalid_value}

  defp based_on(:plant, text) when is_binary(text), do: {:ok, blank_nil(text)}
  defp based_on(_type, nil), do: {:ok, nil}
  defp based_on(_type, _text), do: {:error, :invalid_spec}

  defp blank_nil(nil), do: nil

  defp blank_nil(text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  @doc "The spec an item stored (`subject`, `key` and `stored` spec), as `add_item/2` takes it."
  @spec decode(
          :fact | :note | :editorial | :photo | :reading,
          {atom(), integer()},
          Key.t(),
          map()
        ) ::
          map()
  def decode(:fact, {:gall, gall_id}, key, stored) do
    to = decode_key(stored["to"])

    %{
      kind: :fact,
      gall_id: gall_id,
      action: String.to_existing_atom(stored["action"]),
      key: key,
      to: to
    }
    |> put_present(:when, stored["when"])
  end

  def decode(:reading, {:gall, gall_id}, key, stored) do
    %{
      kind: :reading,
      gall_id: gall_id,
      source_id: stored["source_id"],
      key: key,
      to: decode_to(stored["to"])
    }
  end

  def decode(:photo, {:gall, gall_id}, _key, stored),
    do: %{
      kind: :photo,
      gall_id: gall_id,
      observation_id: stored["observation_id"],
      photo_id: stored["photo_id"]
    }

  def decode(:note, {:gall, gall_id}, key, stored),
    do: %{kind: :note, gall_id: gall_id, key: key, text: stored["text"]}

  def decode(:editorial, subject, {:editorial, field}, stored) do
    %{
      kind: :editorial,
      subject: subject,
      field: field,
      value: decode_value(field, stored["value"]),
      based_on: stored["based_on"]
    }
  end

  defp decode_key(text) when is_binary(text) do
    case Key.load(text) do
      {:ok, key} -> key
      :error -> nil
    end
  end

  defp decode_key(_text), do: nil

  defp decode_to(texts) when is_list(texts), do: Enum.map(texts, &decode_key/1)
  defp decode_to(text), do: decode_key(text)

  defp decode_value(:name_parts, parts),
    do: Map.new(parts, fn {k, v} -> {String.to_existing_atom(k), v} end)

  defp decode_value(:synonyms, synonyms),
    do: Enum.map(synonyms, &%{name: &1["name"], sensu: &1["sensu"]})

  defp decode_value(:range, entries), do: Enum.map(entries, &List.to_tuple/1)
  defp decode_value(_field, value), do: value

  # -- evidence ------------------------------------------------------------------

  @doc """
  Checks evidence (`t:Gallformers.Curation.evidence/0`, atom or string
  keys): `{:ok, stored}` (string keys) or `{:error, :invalid_evidence}`.
  An Observation's provider is `"inaturalist"` or `"bugguide"`; a Source
  must exist.
  """
  @spec check_evidence(map()) :: {:ok, map()} | {:error, :invalid_evidence}
  def check_evidence(evidence) when is_map(evidence) do
    get = fn key -> Map.get(evidence, key, Map.get(evidence, Atom.to_string(key))) end
    text = get.(:text)
    observations = get.(:observations) || []
    source_id = get.(:source_id)

    with true <- is_nil(text) or is_binary(text),
         true <- is_list(observations),
         {:ok, observations} <- observations(observations),
         true <-
           is_nil(source_id) or (is_integer(source_id) and Sources.get_source(source_id) != nil) do
      {:ok,
       %{"text" => blank_nil(text), "observations" => observations, "source_id" => source_id}}
    else
      _ -> {:error, :invalid_evidence}
    end
  end

  def check_evidence(_evidence), do: {:error, :invalid_evidence}

  defp observations(list) do
    checked =
      for o <- list do
        provider = to_string(o[:provider] || o["provider"])
        id = o[:id] || o["id"]

        if provider in @providers and (is_binary(id) or is_integer(id)) and to_string(id) != "",
          do: observation_extras(%{"provider" => provider, "id" => to_string(id)}, o),
          else: :error
      end

    if :error in checked, do: :error, else: {:ok, Enum.uniq(checked)}
  end

  # An iNaturalist observation's quality grade and thumbnail, when given
  # (matter `87a1`): kept with it, as text.
  defp observation_extras(stored, o) do
    for key <- [:quality_grade, :thumbnail_url],
        value = o[key] || o[Atom.to_string(key)],
        is_binary(value) and value != "",
        reduce: stored,
        do: (acc -> Map.put(acc, Atom.to_string(key), value))
  end

  @doc "Stored evidence as `t:Gallformers.Curation.evidence/0`, or nil."
  @spec decode_evidence(map() | nil) :: map() | nil
  def decode_evidence(nil), do: nil

  def decode_evidence(stored) do
    %{
      text: stored["text"],
      observations: for(o <- stored["observations"] || [], do: decode_observation(o)),
      source_id: stored["source_id"]
    }
  end

  defp decode_observation(o) do
    base = %{provider: o["provider"], id: o["id"]}

    for {key, field} <- [quality_grade: "quality_grade", thumbnail_url: "thumbnail_url"],
        o[field],
        reduce: base,
        do: (acc -> Map.put(acc, key, o[field]))
  end
end
