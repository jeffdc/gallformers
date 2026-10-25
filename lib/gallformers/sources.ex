defmodule Gallformers.Sources do
  @moduledoc """
  The Sources context.

  Provides functions for working with scientific references and citations.
  """
  use Boundary,
    deps: [
      Gallformers.Audit,
      Gallformers.Repo,
      Gallformers.ChangesetHelpers,
      Gallformers.SchemaFields,
      Gallformers.Species,
      Gallformers.Licenses,
      Gallformers.Storage
    ],
    exports: :all

  import Ecto.Query
  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Repo
  alias Gallformers.Sources.Docling
  alias Gallformers.Sources.DocumentItem
  alias Gallformers.Sources.QuoteLocator
  alias Gallformers.Sources.Source
  alias Gallformers.Sources.SourceDocument
  alias Gallformers.Species.Species
  alias Gallformers.Species.SpeciesSource
  alias Gallformers.Storage.Private

  @doc """
  Returns all sources ordered by title.
  """
  @spec list_sources() :: [Source.t()]
  def list_sources do
    from(s in Source,
      order_by: s.title
    )
    |> Repo.all()
  end

  @doc """
  Returns paginated sources.
  """
  @spec list_sources_paginated(integer(), integer()) :: [Source.t()]
  def list_sources_paginated(limit, offset) do
    from(s in Source,
      order_by: s.title,
      limit: ^limit,
      offset: ^offset
    )
    |> Repo.all()
  end

  @doc """
  Returns the count of all sources.
  """
  @spec count_sources() :: integer()
  def count_sources do
    from(s in Source,
      select: count(s.id)
    )
    |> Repo.one()
  end

  @doc """
  Gets a source by ID.
  """
  @spec get_source(integer()) :: Source.t() | nil
  def get_source(id) do
    Repo.get(Source, id)
  end

  @doc """
  Gets a source by ID, raising if not found.
  """
  @spec get_source!(integer()) :: Source.t()
  def get_source!(id) do
    Repo.get!(Source, id)
  end

  @doc """
  Gets a source by title.
  """
  @spec get_source_by_title(String.t()) :: Source.t() | nil
  def get_source_by_title(title) do
    from(s in Source,
      where: s.title == ^title
    )
    |> Repo.one()
  end

  @doc """
  Searches sources by title or author.
  """
  @spec search_sources(String.t()) :: [Source.t()]
  def search_sources(query) do
    search_term = "%#{String.downcase(query)}%"

    from(s in Source,
      where:
        ilike(s.title, ^search_term) or
          ilike(s.author, ^search_term),
      order_by: s.title
    )
    |> Repo.all()
  end

  # Gallformers Notes source ID - should appear second after default
  @gallformers_notes_source_id 58

  @doc """
  Gets all sources for a species.

  Sources are sorted with:
  1. Default source first (if any)
  2. Gallformers Notes second (unless it's the default)
  3. Remaining sources alphabetically by title
  """
  @spec get_sources_for_species(integer()) :: [map()]
  def get_sources_for_species(species_id) do
    from(ss in SpeciesSource,
      join: s in Source,
      on: ss.source_id == s.id,
      where: ss.species_id == ^species_id,
      select: %{
        id: s.id,
        title: s.title,
        author: s.author,
        pubyear: s.pubyear,
        link: s.link,
        citation: s.citation,
        license: s.license,
        licenselink: s.licenselink,
        description: ss.description,
        useasdefault: ss.useasdefault,
        externallink: ss.externallink
      }
    )
    |> Repo.all()
    |> sort_sources_with_priority()
  end

  # Sort sources: default first, Gallformers Notes second, then alphabetically
  defp sort_sources_with_priority(sources) do
    Enum.sort_by(sources, fn source ->
      cond do
        source.useasdefault -> {0, source.title}
        source.id == @gallformers_notes_source_id -> {1, source.title}
        true -> {2, source.title}
      end
    end)
  end

  @doc """
  Gets all species associated with a source.
  """
  @spec get_species_for_source(integer()) :: [map()]
  def get_species_for_source(source_id) do
    from(ss in SpeciesSource,
      join: sp in Species,
      on: ss.species_id == sp.id,
      where: ss.source_id == ^source_id,
      order_by: sp.name,
      select: %{
        id: sp.id,
        name: sp.name,
        taxoncode: sp.taxoncode,
        description: ss.description,
        externallink: ss.externallink
      }
    )
    |> Repo.all()
  end

  @doc """
  Gets the count of species associated with a source.
  """
  @spec count_species_for_source(integer()) :: integer()
  def count_species_for_source(source_id) do
    from(ss in SpeciesSource,
      where: ss.source_id == ^source_id,
      select: count(ss.id)
    )
    |> Repo.one()
  end

  # Admin functions

  @doc """
  Returns a changeset for tracking source changes.
  """
  @spec change_source(Source.t(), map()) :: Ecto.Changeset.t()
  def change_source(%Source{} = source, attrs \\ %{}) do
    Source.changeset(source, attrs)
  end

  @doc """
  Creates a source.
  """
  @spec create_source(map()) :: {:ok, Source.t()} | {:error, Ecto.Changeset.t()}
  def create_source(attrs \\ %{}) do
    %Source{}
    |> Source.changeset(attrs)
    |> Repo.insert()
    |> broadcast(:source_created)
  end

  @doc """
  Updates a source.
  """
  @spec update_source(Source.t(), map()) :: {:ok, Source.t()} | {:error, Ecto.Changeset.t()}
  def update_source(%Source{} = source, attrs) do
    source
    |> Source.changeset(attrs)
    |> Repo.update()
    |> broadcast(:source_updated)
  end

  @doc """
  Sets a Source's descriptive fields: `kind`, `authors`, `authored` (a partial
  date, `"1897"`, `"1897-05"` or `"1897-05-14"`), `authored_as_written`,
  `doi`, `url`, `isbn`, `license_value` and `license_as_written`.

  Today's columns (`author`, `pubyear`, ...) are left as they are.
  """
  @spec update_source_details(Source.t(), map()) ::
          {:ok, Source.t()} | {:error, Ecto.Changeset.t()}
  def update_source_details(%Source{} = source, attrs) do
    source
    |> Source.details_changeset(attrs)
    |> Repo.update()
    |> broadcast(:source_updated)
  end

  @doc """
  Marks `source` as retracted by the retraction notice `notice` (another
  Source) on `retracted_on`. A retraction cancels all of the Source's stances;
  the Source stays, marked.
  """
  @spec retract_source(Source.t(), Source.t(), Date.t()) ::
          {:ok, Source.t()} | {:error, Ecto.Changeset.t()}
  def retract_source(%Source{} = source, %Source{} = notice, %Date{} = retracted_on) do
    source
    |> Source.retract_changeset(notice, retracted_on)
    |> Repo.update()
    |> broadcast(:source_updated)
  end

  @doc "The IDs of the retracted Sources among `source_ids`, in ID order."
  @spec retracted_source_ids([integer()]) :: [integer()]
  def retracted_source_ids([]), do: []

  def retracted_source_ids(source_ids) when is_list(source_ids) do
    from(s in Source,
      where: s.id in ^source_ids and not is_nil(s.retracted_by_id),
      order_by: s.id,
      select: s.id
    )
    |> Repo.all()
  end

  @doc "The Gallformers Source (the one Source of kind `gallformers`), or nil."
  @spec get_gallformers_source() :: Source.t() | nil
  def get_gallformers_source, do: Repo.get_by(Source, kind: :gallformers)

  @doc """
  Finds the Sources an import package's Source block may be (`9449` Task 13),
  by a conservative rule; the caller sends anything but one clear match to a
  curator:

    1. **DOI** (`:doi`, compared without case and without a
       `https://doi.org/` or `doi:` prefix): the Sources with that DOI. One
       is `{:match, source}`; several are `{:ambiguous, sources}`.
    2. Otherwise the **citation** (`:citation`, compared with whitespace
       collapsed and without case): one Source is a match, unless it records
       a different DOI than the package gives (then ambiguous); several are
       ambiguous.
    3. Otherwise the **title** (`:title`, compared the same way): a Source
       with the same title but another citation may be the same work cited
       differently, and titles are unique, so it is ambiguous.
    4. Otherwise `:none`: the Source is new.
  """
  @spec match_source(map()) :: {:match, Source.t()} | {:ambiguous, [Source.t()]} | :none
  def match_source(attrs) when is_map(attrs) do
    doi = normalize_doi(attrs[:doi])

    with [] <- by_doi(doi),
         [] <- by_text(:citation, attrs[:citation]),
         [] <- by_text(:title, attrs[:title]) do
      :none
    else
      [%Source{} = source] = found ->
        cond do
          doi != nil and normalize_doi(source.doi) == doi -> {:match, source}
          doi != nil and source.doi not in [nil, ""] -> {:ambiguous, found}
          by_text?(source, :citation, attrs[:citation]) -> {:match, source}
          true -> {:ambiguous, found}
        end

      several ->
        {:ambiguous, several}
    end
  end

  defp by_doi(nil), do: []

  defp by_doi(doi) do
    forms =
      [doi, "doi:" <> doi] ++
        for scheme <- ["https://", "http://"],
            host <- ["doi.org/", "dx.doi.org/"],
            do: scheme <> host <> doi

    Repo.all(
      from(s in Source,
        where: fragment("lower(trim(?))", s.doi) in ^forms,
        order_by: s.id
      )
    )
  end

  defp by_text(_field, nil), do: []

  defp by_text(field, text) do
    wanted = normalize_text(text)

    Repo.all(
      from(s in Source,
        where:
          fragment("lower(regexp_replace(trim(?), '\\s+', ' ', 'g'))", field(s, ^field)) ==
            ^wanted,
        order_by: s.id
      )
    )
  end

  defp by_text?(source, field, text),
    do:
      is_binary(text) and normalize_text(Map.fetch!(source, field) || "") == normalize_text(text)

  defp normalize_text(text),
    do: text |> String.trim() |> String.replace(~r/\s+/u, " ") |> String.downcase()

  defp normalize_doi(nil), do: nil
  defp normalize_doi(""), do: nil

  defp normalize_doi(doi) do
    doi
    |> String.trim()
    |> String.replace(~r{\A(https?://(dx\.)?doi\.org/|doi:)}i, "")
    |> String.downcase()
  end

  @doc """
  Creates a Source from an import package's Source block, already mapped to
  attributes (`Gallformers.Sources.Source.import_changeset/2`).
  """
  @spec create_imported_source(map()) :: {:ok, Source.t()} | {:error, Ecto.Changeset.t()}
  def create_imported_source(attrs) when is_map(attrs) do
    %Source{}
    |> Source.import_changeset(attrs)
    |> Repo.insert()
    |> broadcast(:source_created)
  end

  @doc """
  The Source titled `attrs.title`, created from `attrs` if there is none
  (`Gallformers.Sources.Source.record_changeset/2`: today's columns, which
  may be empty, and the descriptive fields; no authored date needed). An
  existing Source is returned as it is. Nothing is broadcast: the data
  migration calls this without the application running.
  """
  @spec ensure_source(map()) :: {:ok, Source.t()} | {:error, Ecto.Changeset.t()}
  def ensure_source(%{title: title} = attrs) when is_binary(title) do
    case get_source_by_title(title) do
      %Source{} = source -> {:ok, source}
      nil -> %Source{} |> Source.record_changeset(attrs) |> Repo.insert()
    end
  end

  @doc "Whether a Source already has `title` (titles are unique)."
  @spec title_taken?(String.t()) :: boolean()
  def title_taken?(title) when is_binary(title),
    do: Repo.exists?(from(s in Source, where: s.title == ^String.trim(title)))

  @doc """
  Deletes a source.
  """
  @spec delete_source(Source.t()) :: {:ok, Source.t()} | {:error, Ecto.Changeset.t()}
  def delete_source(%Source{} = source) do
    Repo.delete(source)
    |> broadcast(:source_deleted)
  end

  @doc """
  Subscribes to source changes.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(Gallformers.PubSub, "sources")
  end

  defp broadcast({:ok, source}, event) do
    Phoenix.PubSub.broadcast(Gallformers.PubSub, "sources", {event, source})
    {:ok, source}
  end

  defp broadcast({:error, changeset}, _event) do
    {:error, changeset}
  end

  # ============================================
  # SpeciesSource (mapping) functions
  # ============================================

  @doc """
  Returns a changeset for tracking species-source mapping changes.
  """
  @spec change_species_source(SpeciesSource.t(), map()) :: Ecto.Changeset.t()
  def change_species_source(%SpeciesSource{} = species_source, attrs \\ %{}) do
    SpeciesSource.changeset(species_source, attrs)
  end

  @doc """
  Gets a species-source mapping by ID.
  """
  @spec get_species_source(integer()) :: SpeciesSource.t() | nil
  def get_species_source(id) do
    Repo.get(SpeciesSource, id)
  end

  @doc """
  Gets a species-source mapping by ID, raising if not found.
  """
  @spec get_species_source!(integer()) :: SpeciesSource.t()
  def get_species_source!(id) do
    Repo.get!(SpeciesSource, id)
  end

  @doc """
  Gets a species-source mapping by species_id and source_id.
  """
  @spec get_species_source_by_ids(integer(), integer()) :: SpeciesSource.t() | nil
  def get_species_source_by_ids(species_id, source_id) do
    from(ss in SpeciesSource,
      where: ss.species_id == ^species_id and ss.source_id == ^source_id
    )
    |> Repo.one()
  end

  @doc """
  Creates a species-source mapping.

  If useasdefault is set to 1, clears all other defaults for that species first.
  """
  @spec create_species_source(map()) :: {:ok, SpeciesSource.t()} | {:error, Ecto.Changeset.t()}
  def create_species_source(attrs \\ %{}) do
    changeset = SpeciesSource.changeset(%SpeciesSource{}, attrs)

    result =
      if setting_as_default?(attrs) do
        species_id = get_species_id_from_attrs(attrs)
        insert_with_default_transaction(changeset, species_id)
      else
        Repo.insert(changeset)
      end

    result |> broadcast(:species_source_created)
  end

  @doc """
  Updates a species-source mapping.

  If useasdefault is set to 1, clears all other defaults for that species first.
  """
  @spec update_species_source(SpeciesSource.t(), map()) ::
          {:ok, SpeciesSource.t()} | {:error, Ecto.Changeset.t()}
  def update_species_source(%SpeciesSource{} = species_source, attrs) do
    changeset = SpeciesSource.changeset(species_source, attrs)

    result =
      if setting_as_default?(attrs) do
        update_with_default_transaction(changeset, species_source.species_id, species_source.id)
      else
        Repo.update(changeset)
      end

    result |> broadcast(:species_source_updated)
  end

  # Inserts a species-source mapping with transaction to clear other defaults
  defp insert_with_default_transaction(changeset, species_id) do
    Repo.transaction(fn ->
      clear_other_defaults(species_id, nil)
      insert_or_rollback(changeset)
    end)
  end

  # Updates a species-source mapping with transaction to clear other defaults
  defp update_with_default_transaction(changeset, species_id, exclude_id) do
    Repo.transaction(fn ->
      clear_other_defaults(species_id, exclude_id)
      update_or_rollback(changeset)
    end)
  end

  defp insert_or_rollback(changeset) do
    case Repo.insert(changeset) do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp update_or_rollback(changeset) do
    case Repo.update(changeset) do
      {:ok, record} -> record
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp setting_as_default?(attrs) do
    useasdefault = attrs["useasdefault"] || attrs[:useasdefault]
    useasdefault in [true, "true"]
  end

  # Gets species_id from attrs (handles both string and atom keys)
  defp get_species_id_from_attrs(attrs) do
    species_id = attrs["species_id"] || attrs[:species_id]

    case species_id do
      id when is_integer(id) -> id
      id when is_binary(id) -> String.to_integer(id)
      _ -> nil
    end
  end

  # Clears useasdefault flag on all other mappings for a species
  defp clear_other_defaults(species_id, exclude_id) when not is_nil(species_id) do
    query =
      from(ss in SpeciesSource,
        where: ss.species_id == ^species_id and ss.useasdefault == true
      )

    query =
      if exclude_id do
        from(ss in query, where: ss.id != ^exclude_id)
      else
        query
      end

    Repo.update_all(query, set: [useasdefault: false])
  end

  defp clear_other_defaults(_, _), do: :ok

  @doc """
  Deletes a species-source mapping.
  """
  @spec delete_species_source(SpeciesSource.t()) ::
          {:ok, SpeciesSource.t()} | {:error, Ecto.Changeset.t()}
  def delete_species_source(%SpeciesSource{} = species_source) do
    Repo.delete(species_source)
    |> broadcast(:species_source_deleted)
  end

  @doc """
  Returns whether a species has any sources linked to it.
  """
  @spec has_sources?(integer()) :: boolean()
  def has_sources?(species_id) do
    from(ss in SpeciesSource, where: ss.species_id == ^species_id)
    |> Repo.exists?()
  end

  @doc """
  Checks if a species is already linked to a source.
  """
  @spec species_source_exists?(integer(), integer()) :: boolean()
  def species_source_exists?(species_id, source_id) do
    from(ss in SpeciesSource,
      where: ss.species_id == ^species_id and ss.source_id == ^source_id
    )
    |> Repo.exists?()
  end

  @doc """
  Searches species-source mappings by species name, source title, or description.
  Returns mappings with full species and source info for display.
  """
  @spec search_species_source_mappings(String.t(), integer()) :: [map()]
  def search_species_source_mappings(query, limit \\ 50) do
    search_term = "%#{String.downcase(query)}%"

    from(ss in SpeciesSource,
      join: sp in Species,
      on: ss.species_id == sp.id,
      join: src in Source,
      on: ss.source_id == src.id,
      where:
        ilike(sp.name, ^search_term) or
          ilike(src.title, ^search_term) or
          ilike(src.author, ^search_term) or
          ilike(ss.description, ^search_term),
      order_by: [asc: sp.name, asc: src.title],
      limit: ^limit,
      select: %{
        id: ss.id,
        species_id: sp.id,
        species_name: sp.name,
        species_taxoncode: sp.taxoncode,
        source_id: src.id,
        source_title: src.title,
        source_author: src.author,
        source_pubyear: src.pubyear,
        description: ss.description,
        externallink: ss.externallink,
        useasdefault: ss.useasdefault
      }
    )
    |> Repo.all()
  end

  @doc """
  Gets all species-source mappings for a specific species.
  Returns mappings in the same format as search_species_source_mappings for display.
  """
  @spec get_species_source_mappings_for_species(integer()) :: [map()]
  def get_species_source_mappings_for_species(species_id) do
    from(ss in SpeciesSource,
      join: sp in Species,
      on: ss.species_id == sp.id,
      join: src in Source,
      on: ss.source_id == src.id,
      where: ss.species_id == ^species_id,
      order_by: [asc: src.title],
      select: %{
        id: ss.id,
        species_id: sp.id,
        species_name: sp.name,
        species_taxoncode: sp.taxoncode,
        source_id: src.id,
        source_title: src.title,
        source_author: src.author,
        source_pubyear: src.pubyear,
        description: ss.description,
        externallink: ss.externallink,
        useasdefault: ss.useasdefault
      }
    )
    |> Repo.all()
  end

  @doc """
  Gets a species-source mapping with full details for editing.
  """
  @spec get_species_source_for_edit(integer()) :: map() | nil
  def get_species_source_for_edit(id) do
    from(ss in SpeciesSource,
      join: sp in Species,
      on: ss.species_id == sp.id,
      join: src in Source,
      on: ss.source_id == src.id,
      where: ss.id == ^id,
      select: %{
        id: ss.id,
        species_id: sp.id,
        species_name: sp.name,
        species_taxoncode: sp.taxoncode,
        source_id: src.id,
        source_title: src.title,
        source_author: src.author,
        source_pubyear: src.pubyear,
        description: ss.description,
        externallink: ss.externallink,
        useasdefault: ss.useasdefault
      }
    )
    |> Repo.one()
  end

  # ============================================
  # Stored documents
  # ============================================

  @item_insert_chunk 1_000

  @doc """
  Stores a Source's `document.json` (a DoclingDocument, as its raw bytes).

  The bytes go to the private bucket under a key named by their sha256; a
  `source_documents` row (kind `:docling`) records the key and digest, and one
  `document_items` row is written per text, table and picture item
  (`Gallformers.Sources.Docling`). The rows are written in one transaction
  audited as `actor`.

  Idempotent: storing the same bytes for the same Source again returns the
  existing document and writes nothing.
  """
  @spec store_document(Actor.t(), Source.t(), binary()) ::
          {:ok, SourceDocument.t()}
          | {:error, :invalid_json | :not_a_docling_document | Ecto.Changeset.t() | term()}
  def store_document(%Actor{} = actor, %Source{id: source_id}, json)
      when is_integer(source_id) and is_binary(json) do
    sha256 = :crypto.hash(:sha256, json) |> Base.encode16(case: :lower)

    case get_docling_document(source_id, sha256) do
      %SourceDocument{} = existing -> {:ok, existing}
      nil -> store_new_document(actor, source_id, sha256, json)
    end
  end

  @doc """
  Stores a version of Gall `gall_id`'s Gallformers note (`20e5`): `text`,
  verbatim, as one `:note` document of `source` (the Gallformers Source),
  dated `version_date` — nil for a legacy note, which has no date.

  The text goes to the private bucket as UTF-8 plain text under a key named
  by its sha256, and the document gets **one** item (`"#/texts/0"`) holding
  the whole text, so Facts extracted from the note later can quote it and
  have their quotes located like any Source document's. The rows are
  written in one transaction audited as `actor`.

  Idempotent: the same text for the same Gall and Source again returns the
  existing document.
  """
  @spec store_note(Actor.t(), Source.t(), integer(), String.t(), Date.t() | nil) ::
          {:ok, SourceDocument.t()} | {:error, Ecto.Changeset.t() | term()}
  def store_note(%Actor{} = actor, %Source{id: source_id}, gall_id, text, version_date \\ nil)
      when is_integer(source_id) and is_integer(gall_id) and is_binary(text) do
    sha256 = :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)

    case Repo.get_by(SourceDocument,
           source_id: source_id,
           gall_id: gall_id,
           sha256: sha256,
           kind: :note
         ) do
      %SourceDocument{} = existing ->
        {:ok, existing}

      nil ->
        key = "sources/#{source_id}/notes/#{gall_id}/#{sha256}.txt"

        attrs = %{
          source_id: source_id,
          kind: :note,
          s3_key: key,
          sha256: sha256,
          gall_id: gall_id,
          version_date: version_date
        }

        item = %{ref: "#/texts/0", label: "text", text: text, page_no: nil, position: 0}

        with :ok <- Private.put(key, text, content_type: "text/plain; charset=utf-8") do
          Audit.transaction(actor, "sources.store_note", fn -> insert_document(attrs, [item]) end)
        end
    end
  end

  @doc "Gall `gall_id`'s Gallformers note versions, the newest first (undated last)."
  @spec list_gall_notes(integer()) :: [SourceDocument.t()]
  def list_gall_notes(gall_id) when is_integer(gall_id) do
    from(d in SourceDocument,
      where: d.kind == :note and d.gall_id == ^gall_id,
      order_by: [desc_nulls_last: d.version_date, desc: d.id]
    )
    |> Repo.all()
  end

  @doc "A stored document's items in reading order."
  @spec list_document_items(SourceDocument.t()) :: [DocumentItem.t()]
  def list_document_items(%SourceDocument{id: id}) do
    from(i in DocumentItem, where: i.source_document_id == ^id, order_by: i.position)
    |> Repo.all()
  end

  @doc "A stored document's item by reference (`\"#/texts/42\"`), or nil."
  @spec get_document_item(SourceDocument.t(), String.t()) :: DocumentItem.t() | nil
  def get_document_item(%SourceDocument{id: id}, ref) when is_binary(ref) do
    Repo.get_by(DocumentItem, source_document_id: id, ref: ref)
  end

  @doc """
  Locates `quote` in the stored document item `document_item_id`
  (`Gallformers.Sources.QuoteLocator`), returning its span in the item's
  text: `{start, length}` in codepoints.
  """
  @spec locate_quote(integer(), String.t()) ::
          {:ok, QuoteLocator.span()} | {:error, :item_not_found | :quote_not_found}
  def locate_quote(document_item_id, quote)
      when is_integer(document_item_id) and is_binary(quote) do
    text = from(i in DocumentItem, where: i.id == ^document_item_id, select: i.text) |> Repo.one()

    case text && QuoteLocator.locate(text, quote) do
      nil -> {:error, :item_not_found}
      {:ok, span} -> {:ok, span}
      :error -> {:error, :quote_not_found}
    end
  end

  defp store_new_document(actor, source_id, sha256, json) do
    key = "sources/#{source_id}/documents/#{sha256}.json"

    with {:ok, doc} <- decode_docling(json),
         :ok <- Private.put(key, json, content_type: "application/json") do
      attrs = %{source_id: source_id, kind: :docling, s3_key: key, sha256: sha256}

      actor
      |> Audit.transaction("sources.store_document", fn ->
        insert_document(attrs, Docling.document_items(doc))
      end)
      |> found_if_stored_meanwhile(source_id, sha256)
    end
  end

  defp decode_docling(json) do
    case Jason.decode(json) do
      {:ok, %{"schema_name" => "DoclingDocument"} = doc} -> {:ok, doc}
      {:ok, _other} -> {:error, :not_a_docling_document}
      {:error, _reason} -> {:error, :invalid_json}
    end
  end

  defp insert_document(attrs, items) do
    case %SourceDocument{} |> SourceDocument.changeset(attrs) |> Repo.insert() do
      {:ok, document} ->
        items
        |> Enum.map(&Map.put(&1, :source_document_id, document.id))
        |> Enum.chunk_every(@item_insert_chunk)
        |> Enum.each(&Repo.insert_all(DocumentItem, &1))

        document

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  # Another process may have stored the same document since we looked.
  defp found_if_stored_meanwhile({:error, %Ecto.Changeset{}} = error, source_id, sha256) do
    case get_docling_document(source_id, sha256) do
      %SourceDocument{} = existing -> {:ok, existing}
      nil -> error
    end
  end

  defp found_if_stored_meanwhile(result, _source_id, _sha256), do: result

  defp get_docling_document(source_id, sha256) do
    Repo.get_by(SourceDocument, source_id: source_id, sha256: sha256, kind: :docling)
  end
end
