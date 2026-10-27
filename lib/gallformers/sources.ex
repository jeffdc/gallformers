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

  @doc "The Sources with IDs among `ids`, by ID (unknown IDs are left out)."
  @spec list_sources_by_id([integer()]) :: [Source.t()]
  def list_sources_by_id([]), do: []

  def list_sources_by_id(ids) when is_list(ids) do
    Repo.all(from(s in Source, where: s.id in ^ids, order_by: s.id))
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

  @doc """
  A page of the Sources, by title, for the Source editor's list: those whose
  title or author contains `:query` (ignoring case; all when blank). Options:
  `:query`, `:page` (from 1, default 1), `:page_size` (default 25). Returns
  the page's Sources and how many match.
  """
  @spec list_sources_page(keyword()) :: %{entries: [Source.t()], total: non_neg_integer()}
  def list_sources_page(opts \\ []) do
    page = max(Keyword.get(opts, :page, 1), 1)
    page_size = Keyword.get(opts, :page_size, 25)

    query =
      case String.trim(Keyword.get(opts, :query) || "") do
        "" ->
          Source

        text ->
          term = "%#{text}%"
          from(s in Source, where: ilike(s.title, ^term) or ilike(s.author, ^term))
      end

    %{
      entries:
        Repo.all(
          from(s in query,
            order_by: [s.title, s.id],
            limit: ^page_size,
            offset: ^((page - 1) * page_size)
          )
        ),
      total: Repo.aggregate(query, :count)
    }
  end

  # Admin functions

  @doc """
  The Source editor's changeset for `source` (`Gallformers.Sources.Source.changeset/2`).
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
  end

  @doc """
  Edits a Source's details as the Source editor does
  (`Gallformers.Sources.Source.changeset/2`): today's columns (`title`,
  `author`, `pubyear`, `link`, `citation`, `datacomplete`, `license`,
  `licenselink`) and the descriptive fields (`kind`, `authors`, `authored` —
  a partial date, `"1897"`, `"1897-05"` or `"1897-05-14"` —
  `authored_as_written`, `doi`, `url`, `isbn`, `license_as_written`), in a
  transaction audited as `actor`.

  The standings of the Source's Facts and the replay log are
  `Gallformers.Import.record_source_edit/2`'s, which calls this.
  """
  @spec update_source_details(Actor.t(), Source.t(), map()) ::
          {:ok, Source.t()} | {:error, Ecto.Changeset.t()}
  def update_source_details(%Actor{} = actor, %Source{} = source, attrs) when is_map(attrs) do
    audited_update(actor, "sources.update_source_details", Source.changeset(source, attrs))
  end

  @doc """
  Marks `source` as retracted by the retraction notice `notice` (another
  Source) on `retracted_on`, in a transaction audited as `actor`. A
  retraction cancels all of the Source's stances; the Source stays, marked.
  Recompute its Facts' standings afterwards
  (`Gallformers.Facts.recompute_for_source/2`).
  """
  @spec retract_source(Actor.t(), Source.t(), Source.t(), Date.t()) ::
          {:ok, Source.t()} | {:error, Ecto.Changeset.t()}
  def retract_source(
        %Actor{} = actor,
        %Source{} = source,
        %Source{} = notice,
        %Date{} = retracted_on
      ) do
    audited_update(
      actor,
      "sources.retract_source",
      Source.retract_changeset(source, notice, retracted_on)
    )
  end

  @doc """
  Undoes `source`'s retraction (a retraction entered by mistake), in a
  transaction audited as `actor`; a Source that is not retracted is an
  error. Recompute its Facts' standings afterwards.
  """
  @spec unretract_source(Actor.t(), Source.t()) ::
          {:ok, Source.t()} | {:error, Ecto.Changeset.t()}
  def unretract_source(%Actor{} = actor, %Source{} = source) do
    audited_update(actor, "sources.unretract_source", Source.unretract_changeset(source))
  end

  defp audited_update(actor, operation, changeset) do
    Audit.transaction(actor, operation, fn ->
      case Repo.update(changeset) do
        {:ok, source} -> source
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
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
  end

  @doc """
  The Source titled `attrs.title`, created from `attrs` if there is none
  (`Gallformers.Sources.Source.record_changeset/2`: today's columns, which
  may be empty, and the descriptive fields; no authored date needed). An
  existing Source is returned as it is.
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

  @doc """
  The IDs of the Galls with a note of Source `source_id` (Gallformers notes
  are the Gallformers Source's), by ID.
  """
  @spec list_noted_gall_ids(integer()) :: [integer()]
  def list_noted_gall_ids(source_id) when is_integer(source_id) do
    from(d in SourceDocument,
      where: d.kind == :note and d.source_id == ^source_id and not is_nil(d.gall_id),
      distinct: true,
      order_by: d.gall_id,
      select: d.gall_id
    )
    |> Repo.all()
  end

  @doc """
  The text of each Gall's newest note of Source `source_id` (newest as
  `list_gall_notes/1` orders them; its items joined by blank lines), by Gall
  ID, in two queries.
  """
  @spec newest_note_texts(integer()) :: %{integer() => String.t()}
  def newest_note_texts(source_id) when is_integer(source_id) do
    newest =
      from(d in SourceDocument,
        where: d.kind == :note and d.source_id == ^source_id and not is_nil(d.gall_id),
        distinct: d.gall_id,
        order_by: [d.gall_id, desc_nulls_last: d.version_date, desc: d.id],
        select: {d.id, d.gall_id}
      )
      |> Repo.all()
      |> Map.new()

    from(i in DocumentItem,
      where: i.source_document_id in ^Map.keys(newest),
      order_by: [i.source_document_id, i.position],
      select: {i.source_document_id, i.text}
    )
    |> Repo.all()
    |> Enum.group_by(&Map.fetch!(newest, elem(&1, 0)), &elem(&1, 1))
    |> Map.new(fn {gall_id, texts} -> {gall_id, Enum.join(texts, "\n\n")} end)
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
