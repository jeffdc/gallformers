defmodule Gallformers.Import.Validator do
  @moduledoc """
  Validates an import package (phase 4 of the contract) and, with
  `review: true`, the readiness gate (phases 5 and 6): the same checks, with
  comparable messages, as the contract's validator `priv/import/validate.py`.
  Keep the two in step (`priv/import/tests/` and
  `test/gallformers/import/validator_test.exs` hold the same cases).

  A package is a map of file name to bytes: `"document.json"`,
  `"taxonomy.json"`, `"gall.json"` and `"review.json"`, each optional.

  ## Phase 4

    * the schemas (`Gallformers.Import.Schemas`): shape and controlled
      values;
    * the package: `document.json` present and matching its sha256, every
      quote found in its document item (`Gallformers.Sources.QuoteLocator`,
      which matches quotes as the validator does), references declared, ids
      unique, qualifier targets, one Inducer per Gall, new Galls have Facts,
      at most one description per Gall, no synonymy or split above family. A
      taxon or Gall declared but never used is a warning.

  ## The readiness gate

  `review.json` exists and is well formed; with no findings it covers the
  batches as they stand; with findings, each has a phase 6 response and the
  batches are the ones phase 6 left. Disputed findings are warnings, for
  human review at intake.

  ## Differences from `validate.py`

    * Format assertion covers `date`, `date-time` and `uri` (JSV's format
      validators). `validate.py`'s format checker checks only the formats
      whose optional Python packages are installed, which under `uv run` is
      `date`, so a malformed URL passes there and fails here.
    * Schema error messages are JSV's, not Python `jsonschema`'s, but each
      names the same location (`facts/5/value/value: ...`).
    * A package with no batch file is one error filed under `"package"`.
  """

  alias Gallformers.Import.Schemas
  alias Gallformers.Import.Validator.Checks

  defmodule Problem do
    @moduledoc "One problem found in a package: its level, the file it is in, and what is wrong."
    @enforce_keys [:level, :file, :message]
    defstruct [:level, :file, :message]

    @type t :: %__MODULE__{level: :error | :warning, file: String.t(), message: String.t()}
  end

  @type package :: %{optional(String.t()) => binary()}

  @batch_files ["taxonomy.json", "gall.json"]

  @doc "The batch files a package may hold, in the order they are applied."
  @spec batch_files() :: [String.t()]
  def batch_files, do: @batch_files

  @doc """
  Every problem in `package`: phase 4 for each batch file present, and with
  `review: true` the readiness gate (filed under `"review.json"`).
  """
  @spec validate(package(), keyword()) :: [Problem.t()]
  def validate(package, opts \\ []) when is_map(package) do
    batches =
      case Enum.filter(@batch_files, &Map.has_key?(package, &1)) do
        [] ->
          [%Problem{level: :error, file: "package", message: "no taxonomy.json or gall.json"}]

        names ->
          Enum.flat_map(names, fn name ->
            for {level, message} <- batch_problems(package[name], package),
                do: %Problem{level: level, file: name, message: message}
          end)
      end

    gate =
      if Keyword.get(opts, :review, false) do
        for {level, message} <- review_problems(package),
            do: %Problem{level: level, file: "review.json", message: message}
      else
        []
      end

    batches ++ gate
  end

  @doc "Whether `problems` include an error (warnings are allowed)."
  @spec errors?([Problem.t()]) :: boolean()
  def errors?(problems), do: Enum.any?(problems, &(&1.level == :error))

  # -- the schemas -------------------------------------------------------------

  @doc """
  A decoded batch's schema errors, as `"path: message"` strings sorted by
  path (`validate.py`'s `schema_errors`).
  """
  @spec schema_errors(term()) :: [String.t()]
  def schema_errors(%{"format" => "gallformers-import"} = batch) do
    case batch["batch_type"] do
      "taxonomy" -> errors_against(Schemas.root(:taxonomy), batch)
      "gall" -> errors_against(Schemas.root(:gall), batch)
      other -> [~s{batch_type must be "taxonomy" or "gall", got #{inspect(other)}}]
    end
  end

  def schema_errors(_batch),
    do: [~s{not a Gallformers import batch (expected "format": "gallformers-import")}]

  defp errors_against(root, data) do
    case JSV.validate(data, root, cast: false) do
      {:ok, _} ->
        []

      {:error, error} ->
        error
        |> JSV.normalize_error(min_error_level: JSV.ErrorFormatter.level_cause())
        |> Map.fetch!(:details)
        |> Enum.flat_map(&leaf_errors/1)
        |> Enum.uniq()
        |> drop_cascades()
        |> Enum.sort()
        |> Enum.map(fn {segments, message, _unexpected} -> "#{path(segments)}: #{message}" end)
    end
  end

  # The errors that say why the data was rejected: the innermost ones, as
  # `{location segments, message, unexpected?}`. Errors of a failed `if`
  # (JSV reports them beside the `else` branch's) are not problems. A
  # property rejected by `unevaluatedProperties: false` is reported on its
  # object, as validate.py does.
  defp leaf_errors(%{instanceLocation: location, evaluationPath: eval_path, errors: errors}) do
    if failed_if?(eval_path) do
      []
    else
      segments = segments(location)

      Enum.flat_map(errors, fn
        %{details: [_ | _] = details} ->
          Enum.flat_map(details, &leaf_errors/1)

        %{kind: :boolean_schema} when segments != [] ->
          {parent, [name]} = Enum.split(segments, -1)
          [{parent, "property '#{name}' is not allowed", true}]

        %{message: message} ->
          [{segments, message, false}]
      end)
    end
  end

  defp leaf_errors(_unit), do: []

  defp failed_if?(eval_path), do: eval_path |> String.split("/") |> Enum.member?("if")

  # A property that failed its own schema is not "evaluated", so
  # `unevaluatedProperties` rejects it too, as it does the other properties
  # of an object whose `allOf` part failed: echoes of the real error in that
  # object. An unexpected property is reported only when nothing else is
  # wrong in or under its object (it shows once that is fixed).
  defp drop_cascades(errors) do
    Enum.reject(errors, fn
      {object, _message, true} ->
        Enum.any?(errors, fn
          {^object, _message, true} -> false
          {other, _message, _unexpected} -> List.starts_with?(other, object)
        end)

      _real ->
        false
    end)
  end

  defp segments("#"), do: []
  defp segments("#/" <> path), do: String.split(path, "/")

  defp path([]), do: "(root)"
  defp path(segments), do: Enum.join(segments, "/")

  # -- one batch ---------------------------------------------------------------

  defp batch_problems(bytes, package) do
    case Jason.decode(bytes) do
      {:ok, batch} when is_map(batch) ->
        for(e <- schema_errors(batch), do: {:error, e}) ++ document_problems(batch, package)

      {:ok, batch} ->
        for e <- schema_errors(batch), do: {:error, e}

      {:error, error} ->
        [{:error, "not valid JSON: #{Exception.message(error)}"}]
    end
  end

  defp document_problems(batch, package) do
    named = dig(batch, ["source", "document", "file"])

    missing =
      if is_binary(named) and not Map.has_key?(package, named),
        do: [{:error, "#{named} is missing beside this batch"}],
        else: []

    {doc, sha, unreadable} = document_for(batch, package)
    missing ++ unreadable ++ Checks.run(batch, doc, sha)
  end

  # The document and its sha256 when the batch names a document.json beside it.
  defp document_for(batch, package) do
    with "document.json" <- dig(batch, ["source", "document", "file"]),
         bytes when is_binary(bytes) <- package["document.json"] do
      case Jason.decode(bytes) do
        {:ok, doc} when is_map(doc) -> {doc, sha256(bytes), []}
        _ -> {nil, nil, [{:error, "document.json is not a JSON object"}]}
      end
    else
      _ -> {nil, nil, []}
    end
  end

  @doc "The sha256 of `bytes`, lower-case hex."
  @spec sha256(binary()) :: String.t()
  def sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  @doc "The value at `keys` in nested maps, or nil where a level is missing or not a map."
  @spec dig(term(), [String.t()]) :: term()
  def dig(value, []), do: value
  def dig(map, [key | rest]) when is_map(map), do: dig(Map.get(map, key), rest)
  def dig(_value, _keys), do: nil

  # -- the readiness gate ------------------------------------------------------

  defp review_problems(%{"review.json" => bytes} = package) do
    case Jason.decode(bytes) do
      {:ok, review} ->
        case errors_against(Schemas.root(:review), review) do
          [] -> gate(review, package)
          errors -> for e <- errors, do: {:error, e}
        end

      {:error, error} ->
        [{:error, "not valid JSON: #{Exception.message(error)}"}]
    end
  end

  defp review_problems(_package), do: [{:error, "no review.json: run phase 5"}]

  defp gate(review, package) do
    current =
      for name <- @batch_files, Map.has_key?(package, name), do: {name, sha256(package[name])}

    statements = Map.new(current, fn {name, _digest} -> {name, statement_ids(package[name])} end)
    responded = review["responded"]

    stale =
      if responded do
        for {name, digest} <- current,
            responded["result"][name] != digest,
            do: {:error, "#{name} changed after phase 6: re-run phase 4, then phases 5 and 6"}
      else
        for {name, digest} <- current,
            review["reviewed"][name] != digest,
            do: {:error, "review is stale for #{name}: re-run phase 4, then phase 5"}
      end

    stale ++ Enum.flat_map(review["findings"], &finding_problems(&1, statements, responded))
  end

  defp finding_problems(finding, statements, responded) do
    %{"batch" => name, "id" => id} = finding
    label = "#{name} #{id} (#{finding["problem"]})"
    response = finding["response"]

    cond do
      # Fixed in phase 6; the fix may have removed the statement.
      response && response["decision"] == "agree" ->
        []

      not MapSet.member?(Map.get(statements, name, MapSet.new()), id) ->
        [{:error, "finding #{id} is not in #{name}"}]

      response ->
        [
          {:warning,
           "disputed, for human review at intake: #{label}: reviewer: #{finding["reason"]} " <>
             "| producer: #{response["reason"]}"}
        ]

      responded ->
        [{:error, "finding #{label} has no phase 6 response"}]

      true ->
        [{:error, "phase 5 finding awaits phase 6: #{label}: #{finding["reason"]}"}]
    end
  end

  # The ids of a batch's acts and Facts and the refs of its taxa and Galls.
  defp statement_ids(bytes) do
    case Jason.decode(bytes) do
      {:ok, %{} = batch} ->
        ids = for key <- ["acts", "facts"], %{} = x <- List.wrap(batch[key]), do: x["id"]
        refs = for key <- ["taxa", "galls"], %{} = x <- List.wrap(batch[key]), do: x["ref"]
        MapSet.new(ids ++ refs)

      _ ->
        MapSet.new()
    end
  end
end
