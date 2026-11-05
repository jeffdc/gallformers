defmodule GallformersWeb.Admin.ReviewLive.Document do
  @moduledoc """
  The Source in context on a step page (matter `d213`, Task 22): each
  package's `document.json`, read once when the page mounts
  (`Gallformers.Import.ReviewContext.document/1`), for every quote's
  passage (`Gallformers.Import.Passages.passage/2`, behind "Show the
  passage") and the reader panel ("Read the Source": the whole text,
  `Gallformers.Import.Passages.blocks/1`, the question's quotes marked, with
  a find box).

  A package whose document can't be read has neither: its quotes show no
  passage control and its questions no "Read the Source".

  The step page (`GallformersWeb.Admin.ReviewLive.Step`) calls `mount/1`,
  hands its `reader_*` events to `handle_event/3`, gives each row its
  package's document (`for_item/2`) and renders the panel
  (`GallformersWeb.ReviewComponents.review_reader/1`) from `reader`.
  """
  import Phoenix.Component, only: [assign: 2]

  alias Gallformers.Import.Passages
  alias Gallformers.Import.ReviewContext

  @doc "Reads the page's packages' documents into `documents`; no reader open."
  @spec mount(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def mount(socket) do
    assign(socket, documents: load(socket.assigns.packages), reader: nil)
  end

  @doc "The packages' documents that can be read, by package ID."
  @spec load([%{package: Gallformers.Import.Package.t()}]) :: %{integer() => map()}
  def load(packages) do
    for %{package: package} <- packages,
        {:ok, doc} <- [ReviewContext.document(package)],
        into: %{},
        do: {package.id, doc}
  end

  @doc "The document of the package `item` is from, or nil."
  @spec for_item(%{integer() => map()}, map()) :: map() | nil
  def for_item(documents, %{package_id: id}), do: Map.get(documents, id)

  @doc """
  The passage a quote (`%{item: ref}`) sits in, its block marked; `[]` when
  the quote has no item or the document doesn't hold it.
  """
  @spec passage(map(), map()) :: [Passages.passage_block()]
  def passage(doc, %{item: ref}) when is_map(doc) and is_binary(ref),
    do: Passages.passage(doc, [ref])

  def passage(_doc, _quote), do: []

  @doc """
  The document items an entry's quotes are from, in order, each once: its
  own quotes', then those of the Galls a Trait term covers.
  """
  @spec refs(map()) :: [String.t()]
  def refs(entry) do
    galls = Map.get(entry.question, :galls) || []

    (entry.quotes ++ Enum.flat_map(galls, & &1.quotes))
    |> Enum.map(&Map.get(&1, :item))
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  @doc """
  The reader's events: `reader_open` (`phx-value-item`, the item's ID)
  opens it on that question, `reader_find` (`find`) changes what it marks,
  `reader_close` shuts it.
  """
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          Phoenix.LiveView.Socket.t()
  def handle_event("reader_open", %{"item" => id}, socket) do
    entry = Enum.find(socket.assigns.entries, &(to_string(&1.item.id) == to_string(id)))
    doc = entry && for_item(socket.assigns.documents, entry.item)

    if doc do
      assign(socket,
        reader: %{
          item_id: entry.item.id,
          question: entry.question.question,
          blocks: Passages.blocks(doc),
          cited: refs(entry),
          find: ""
        }
      )
    else
      socket
    end
  end

  def handle_event("reader_find", %{"find" => find}, %{assigns: %{reader: %{} = r}} = socket)
      when is_binary(find),
      do: assign(socket, reader: %{r | find: find})

  def handle_event("reader_close", _params, socket), do: assign(socket, reader: nil)

  def handle_event(_event, _params, socket), do: socket
end
