defmodule Gallformers.Import.Schemas do
  @moduledoc """
  The import contract's JSON Schemas (draft 2020-12), resolved by their
  `$id` the way `priv/import/validate.py` registers them (`load_registry`):
  every `priv/import/schema/*.json` and `priv/import/vocab/*.schema.json`.
  Relative `$ref`s between them (`"common.schema.json#/$defs/envelope"`,
  `"../vocab/traits.schema.json#/$defs/plant_part"`) resolve against each
  file's `$id`.

  The schemas are read at compile time (the module recompiles when they
  change), so a release needs no access to `priv/import` to validate.
  Validation uses JSV (`jsv`), which passes the official JSON Schema test
  suite for 2020-12, including `unevaluatedProperties` and `if`/`then`.
  """

  @contract Path.expand("../../../priv/import", __DIR__)
  @sources Enum.sort(Path.wildcard(Path.join(@contract, "schema/*.json"))) ++
             Enum.sort(Path.wildcard(Path.join(@contract, "vocab/*.schema.json")))

  use JSV.Resolver.Local, source: @sources

  @base "https://gallformers.org/schemas/import/v3/schema/"

  @typedoc "The schemas a document is validated against."
  @type name :: :taxonomy | :gall | :review

  @doc """
  The validation root for a batch type or the review, built once and kept
  in `:persistent_term`.

  Format assertion is on (`date`, `date-time`, `uri`), as `validate.py`
  turns on its format checker for batches.
  """
  @spec root(name()) :: JSV.Root.t()
  def root(name) when name in [:taxonomy, :gall, :review] do
    key = {__MODULE__, name}

    case :persistent_term.get(key, nil) do
      nil ->
        root =
          JSV.build!(%{"$ref" => @base <> "#{name}.schema.json"},
            resolver: __MODULE__,
            formats: true
          )

        :persistent_term.put(key, root)
        root

      root ->
        root
    end
  end
end
