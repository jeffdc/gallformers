defmodule Gallformers.Facts.Evidence do
  @moduledoc """
  One piece of evidence for an attribution (`9449` §2): a quote from the
  Source, or a whole document item.

    * With a stored document, a quote names its `document_item_id`, and
      Gallformers locates it there (`Gallformers.Sources.QuoteLocator`),
      storing `span_start` and `span_length` in codepoints of the item's
      text. A quote that is not in its item is rejected.
    * `whole_item: true` takes the whole item as the evidence: an item, no
      quote, no span.
    * A quote from a Source with no stored document (a website, say) has no
      item and no span.

  `page` is the page as printed in the Source; `url` deep-links into it;
  `cites_as_written` is the work the Source cites for the statement.
  Gallformers statements carry their text on the attribution and need no
  evidence row.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Gallformers.Facts.Attribution
  alias Gallformers.Sources.DocumentItem
  alias Gallformers.Sources.QuoteLocator

  @typedoc "Locates a quote in a document item, as `Gallformers.Sources.locate_quote/2` does."
  @type locator ::
          (integer(), String.t() ->
             {:ok, QuoteLocator.span()} | {:error, :item_not_found | :quote_not_found})

  @type t :: %__MODULE__{
          id: integer() | nil,
          attribution_id: integer() | nil,
          document_item_id: integer() | nil,
          quote: String.t() | nil,
          span_start: non_neg_integer() | nil,
          span_length: pos_integer() | nil,
          page: String.t() | nil,
          url: String.t() | nil,
          whole_item: boolean(),
          cites_as_written: String.t() | nil
        }

  @content_fields [
    :document_item_id,
    :quote,
    :span_start,
    :span_length,
    :page,
    :url,
    :whole_item,
    :cites_as_written
  ]

  schema "attribution_evidence" do
    field :quote, :string
    field :span_start, :integer
    field :span_length, :integer
    field :page, :string
    field :url, :string
    field :whole_item, :boolean, default: false
    field :cites_as_written, :string

    belongs_to :attribution, Attribution
    belongs_to :document_item, DocumentItem
  end

  @doc "The fields that make two pieces of evidence the same."
  @spec content_fields() :: [atom()]
  def content_fields, do: @content_fields

  @doc """
  Creates a changeset for a piece of evidence, locating its quote with
  `locate` when it names a document item.
  """
  @spec changeset(t(), map(), locator()) :: Ecto.Changeset.t()
  def changeset(evidence, attrs, locate) when is_function(locate, 2) do
    evidence
    |> cast(attrs, [:document_item_id, :quote, :page, :url, :whole_item, :cites_as_written])
    |> validate_quote_or_whole_item()
    |> put_span(locate)
    |> foreign_key_constraint(:document_item_id)
    |> check_constraint(:quote, name: :attribution_evidence_quote_or_whole_item)
    |> check_constraint(:quote, name: :attribution_evidence_span)
  end

  defp validate_quote_or_whole_item(changeset) do
    if get_field(changeset, :whole_item) do
      changeset
      |> validate_required([:document_item_id])
      |> validate_blank(:quote, "must be blank for a whole item")
    else
      validate_required(changeset, [:quote])
    end
  end

  defp validate_blank(changeset, field, message) do
    if is_nil(get_field(changeset, field)),
      do: changeset,
      else: add_error(changeset, field, message)
  end

  defp put_span(%Ecto.Changeset{valid?: false} = changeset, _locate), do: changeset

  defp put_span(changeset, locate) do
    item_id = get_field(changeset, :document_item_id)
    quote = get_field(changeset, :quote)

    if is_integer(item_id) and is_binary(quote) do
      case locate.(item_id, quote) do
        {:ok, {start, length}} ->
          change(changeset, span_start: start, span_length: length)

        {:error, :quote_not_found} ->
          add_error(changeset, :quote, "is not in its document item")

        {:error, :item_not_found} ->
          add_error(changeset, :document_item_id, "does not exist")
      end
    else
      change(changeset, span_start: nil, span_length: nil)
    end
  end
end
