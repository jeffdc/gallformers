defmodule Gallformers.ImportFixtures do
  @moduledoc """
  Import packages for tests (`Gallformers.Import`), ported from the contract
  validator's fixtures (`priv/import/tests/conftest.py`).

  A package is a map of file name to bytes (`"document.json"`,
  `"taxonomy.json"`, `"gall.json"`, `"review.json"`), the form
  `Gallformers.Import.Validator.validate/2` takes. `package/1` writes the
  `batch/0` gall batch (and optionally a taxonomy batch) beside
  `Gallformers.DoclingFixtures.document/0`, with the document's real sha256
  in each batch.
  """

  import Gallformers.DataCase, only: [test_actor: 0]

  alias Gallformers.DoclingFixtures
  alias Gallformers.Import
  alias Gallformers.Storage.Private

  @examples Path.expand("../../priv/import/examples", __DIR__)

  @doc """
  Delivers `files` to the private bucket under `import/<key>/`, then
  registers, validates and resolves the package, returning it
  (`:awaiting_review`). Options: `:key` (default unique), `:review`
  (default true; false for Gallformers' own batches).
  """
  def deliver!(files, opts \\ []) do
    key = Keyword.get_lazy(opts, :key, fn -> "pkg-#{System.unique_integer([:positive])}" end)
    for {name, bytes} <- files, do: :ok = Private.put("import/#{key}/#{name}", bytes)
    {:ok, package} = Import.register_package(test_actor(), key)

    {:ok, %{status: :validated} = package} =
      Import.validate_package(test_actor(), package, review: Keyword.get(opts, :review, true))

    {:ok, package} = Import.resolve_package(test_actor(), package)
    package
  end

  @doc "`batch` with a fresh unique producer `batch_id`."
  def unique_batch_id(batch),
    do: Map.put(batch, "batch_id", "batch-#{System.unique_integer([:positive])}-0000")

  @doc "Encodes decoded batches as package files (`{file, map}` pairs), no document."
  def batch_files(batches) do
    Map.new(batches, fn {name, content} -> {name, Jason.encode!(content)} end)
  end

  @doc "The contract's example packages directory."
  def examples_dir, do: @examples

  @doc "The example package names (`simple-paper`, `revision`, ...)."
  def example_names do
    @examples |> File.ls!() |> Enum.filter(&File.dir?(Path.join(@examples, &1))) |> Enum.sort()
  end

  @doc "An example batch decoded, safe to change (`example(\"simple-paper\")`)."
  def example(name, file \\ "gall.json") do
    @examples |> Path.join(name) |> Path.join(file) |> File.read!() |> Jason.decode!()
  end

  @doc "An example package as a map of file name to bytes."
  def example_package(name) do
    dir = Path.join(@examples, name)

    for file <- File.ls!(dir), Path.extname(file) == ".json", into: %{} do
      {file, File.read!(Path.join(dir, file))}
    end
  end

  @doc "The sha256 of `bytes`, lower-case hex."
  def sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  @doc "A gall batch whose evidence points into `DoclingFixtures.document/0`."
  def batch do
    %{
      "format" => "gallformers-import",
      "format_version" => 3,
      "vocabulary_version" => "2026-10-07",
      "batch_type" => "gall",
      "mode" => "replace",
      "batch_id" => "00000000-test-0001",
      "produced_at" => "2026-10-08T00:00:00Z",
      "producer" => %{"name" => "test", "version" => "0"},
      "source" => %{
        "kind" => "publication",
        "title" => "T",
        "authors" => ["A"],
        "authored" => %{"date" => "2024", "as_written" => "2024"},
        "citation" => "A. 2024. T.",
        "license" => %{"value" => "CC-BY", "as_written" => "CC BY 4.0"},
        "document" => %{"file" => "document.json", "sha256" => String.duplicate("0", 64)}
      },
      "taxa" => [
        %{
          "ref" => "t1",
          "name_as_written" => "Andricus quercuscalifornicus",
          "rank" => "species"
        },
        %{"ref" => "t2", "name_as_written" => "Q. lobata", "rank" => "species"},
        %{"ref" => "t3", "name_as_written" => "Torymus", "rank" => "genus"}
      ],
      "galls" => [
        %{
          "ref" => "g1",
          "name_as_written" => "the large stem galls",
          "identified_by" => %{
            "inducer" => "t1",
            "generation" => %{"value" => "agamic", "as_written" => "agamic generation"}
          }
        }
      ],
      "facts" => [
        %{
          "id" => "f1",
          "stance" => "confirm",
          "kind" => "relationship",
          "type" => "inducer_of",
          "subject" => "t1",
          "object" => "g1",
          "evidence" => [
            %{
              "item" => "#/texts/1",
              "quote" => "produced by the agamic generation of Andricus quercuscalifornicus"
            }
          ]
        },
        %{
          "id" => "f2",
          "stance" => "confirm",
          "kind" => "relationship",
          "type" => "host_of",
          "subject" => "t2",
          "object" => "g1",
          "evidence" => [
            %{"item" => "#/texts/2", "quote" => "Common on Q. lobata throughout the hills"}
          ]
        },
        %{
          "id" => "f3",
          "stance" => "confirm",
          "kind" => "relationship",
          "type" => "parasitoid_in",
          "subject" => "t3",
          "object" => "g1",
          "evidence" => [%{"item" => "#/tables/0", "quote" => "Torymus sp. | 14 | reared"}]
        },
        %{
          "id" => "f4",
          "stance" => "confirm",
          "kind" => "qualifier",
          "of" => "f3",
          "qualifier" => "parasitism_mode",
          "value" => %{"value" => "ecto", "as_written" => "external parasitoid"},
          "evidence" => [%{"item" => "#/texts/3", "whole_item" => true}]
        }
      ]
    }
  end

  @doc "A taxonomy batch (same Source as `batch/0`) pointing into the fixture document."
  def taxonomy_batch do
    batch()
    |> Map.drop(["taxa", "galls", "facts"])
    |> Map.merge(%{
      "batch_type" => "taxonomy",
      "batch_id" => "00000000-test-0002",
      "taxa" => [
        %{"ref" => "t1", "name_as_written" => "Andricus quercuscalifornicus", "rank" => "species"}
      ],
      "acts" => [
        %{
          "id" => "a1",
          "stance" => "confirm",
          "kind" => "name",
          "taxon" => "t1",
          "evidence" => [%{"item" => "#/texts/1", "quote" => "Andricus quercuscalifornicus"}]
        }
      ]
    })
  end

  @doc """
  A package: the fixture document plus batches, each batch's
  `source.document.sha256` set to the document's. Options:

    * `:doc` — the document map (default `DoclingFixtures.document/0`)
    * `:gall` — the gall batch (default `batch/0`; `nil` leaves it out)
    * `:taxonomy` — a taxonomy batch (default none)
  """
  def package(opts \\ []) do
    doc_bytes = DoclingFixtures.document_json(Keyword.get(opts, :doc, DoclingFixtures.document()))
    sha = sha256(doc_bytes)

    [{"gall.json", Keyword.get(opts, :gall, batch())}, {"taxonomy.json", opts[:taxonomy]}]
    |> Enum.reject(fn {_name, content} -> is_nil(content) end)
    |> Map.new(fn {name, content} ->
      {name, content |> put_in(["source", "document", "sha256"], sha) |> Jason.encode!()}
    end)
    |> Map.put("document.json", doc_bytes)
  end

  @doc """
  Adds a `review.json` to `package`: `reviewed` holds the batches' hashes;
  with `responded: true`, `responded.result` too. `override` replaces
  top-level keys.
  """
  def with_review(package, findings \\ [], opts \\ []) do
    hashes = batch_hashes(package)

    review =
      %{"format" => "gallformers-review", "reviewed" => hashes, "findings" => findings}
      |> then(fn r ->
        if opts[:responded], do: Map.put(r, "responded", %{"result" => hashes}), else: r
      end)
      |> Map.merge(Keyword.get(opts, :override, %{}))

    Map.put(package, "review.json", Jason.encode!(review))
  end

  @doc "The sha256 of each batch file in `package`."
  def batch_hashes(package) do
    for name <- ["taxonomy.json", "gall.json"], Map.has_key?(package, name), into: %{} do
      {name, sha256(package[name])}
    end
  end
end
