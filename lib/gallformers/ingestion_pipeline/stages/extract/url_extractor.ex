defmodule Gallformers.IngestionPipeline.Stages.Extract.URLExtractor do
  @moduledoc """
  Behaviour for extracting readable text from a submitted URL.
  """

  @callback extract_text(String.t()) :: {:ok, %{text: String.t()}} | {:error, term()}
end
