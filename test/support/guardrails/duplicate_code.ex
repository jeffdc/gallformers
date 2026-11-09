defmodule Gallformers.Guardrails.DuplicateCode do
  @moduledoc """
  Copied code (matter `c800`): Credo's `DuplicatedCode` check, run with the
  `duplicates` config in `.credo.exs`, against a baseline of what it found
  when the check was turned on, `test/support/duplicate_code_baseline.json`.

  The baseline can only shrink. Its test fails when a set of files has more
  copied code than the baseline allows, and when the baseline allows more
  than is left, so a cleanup is locked in (`mix gallformers.guardrails.baseline`).

  A finding is keyed by the files that share the copied block, not its
  lines, so the baseline holds when code moves within a file. Credo reports
  one finding per file in the set, so a pair copied once counts 2.

  It lives in `test/support` because Credo is a dev and test dependency.
  """

  @baseline_path "test/support/duplicate_code_baseline.json"
  @config_name "duplicates"

  @doc """
  How many copied-code findings each set of files has, keyed by `key/1`.

  With `only: dir`, reads just `dir`, with the same check settings as the
  `duplicates` config.
  """
  @spec counts(keyword()) :: %{String.t() => pos_integer()}
  def counts(opts \\ []) do
    opts
    |> issues()
    |> Enum.frequencies_by(&key([&1.filename | files_in(&1.message)]))
  end

  @doc "The baseline key for a set of files: sorted, unique, joined with \" + \"."
  @spec key([String.t()]) :: String.t()
  def key(files), do: files |> Enum.uniq() |> Enum.sort() |> Enum.join(" + ")

  @doc "The baseline: the findings each set of files is allowed."
  @spec read_baseline(Path.t()) :: %{String.t() => pos_integer()}
  def read_baseline(root \\ File.cwd!()) do
    path = Path.join(root, @baseline_path)
    if File.exists?(path), do: path |> File.read!() |> Jason.decode!(), else: %{}
  end

  @doc "Writes today's findings as the baseline, and returns its path."
  @spec write_baseline(Path.t()) :: Path.t()
  def write_baseline(root \\ File.cwd!()) do
    path = Path.join(root, @baseline_path)
    counts = File.cd!(root, fn -> counts() end)

    File.write!(
      path,
      Jason.encode_to_iodata!(Jason.OrderedObject.new(Enum.sort(counts)), pretty: true)
    )

    path
  end

  @doc "The failure message for files with more copied code than the baseline allows."
  @spec explain([{String.t(), pos_integer(), non_neg_integer()}]) :: String.t()
  def explain(worse) do
    lines = for {files, count, allowed} <- worse, do: "  #{files}: #{count} (baseline #{allowed})"

    """
    New copied code. Call the existing code instead of copying it, or move the
    shared part into one function both call:

    #{Enum.join(lines, "\n")}

    See each block with: mix credo --config-name #{@config_name}
    Never write the baseline to make new copied code pass.
    """
  end

  defp issues(opts) do
    start_credo()
    argv = ["--mute-exit-status" | config_args(opts[:only])]

    Credo.CLI.Output.Shell.suppress_output(fn -> send(self(), {:credo, Credo.run(argv)}) end)

    receive do
      {:credo, exec} -> Credo.Execution.get_issues(exec)
    end
  end

  # Credo's services. Under `mix precommit`, `credo --strict` has already
  # started them in this VM without starting the application, so starting
  # the application finds its supervisor running.
  defp start_credo do
    case Application.ensure_all_started(:credo) do
      {:ok, _apps} -> :ok
      {:error, {:credo, {{:already_started, _pid}, _mfa}}} -> :ok
    end
  end

  defp config_args(nil), do: ["--config-name", @config_name]

  defp config_args(dir) do
    checks = %{enabled: [{Credo.Check.Design.DuplicatedCode, check_params()}]}
    config = %{configs: [%{name: @config_name, files: %{included: [dir]}, checks: checks}]}
    path = Path.join(dir, ".credo.exs")
    File.write!(path, inspect(config, limit: :infinity))
    ["--config-file", path, "--config-name", @config_name]
  end

  # The check's settings in the `duplicates` config of `.credo.exs`.
  defp check_params do
    {%{configs: configs}, _} = Code.eval_file(".credo.exs")
    %{checks: %{enabled: checks}} = Enum.find(configs, &(&1.name == @config_name))

    {Credo.Check.Design.DuplicatedCode, params} =
      List.keyfind(checks, Credo.Check.Design.DuplicatedCode, 0)

    params
  end

  # The other files a finding names: "Duplicate code found in lib/a.ex:12, lib/b.ex:40 (mass: 45)."
  defp files_in(message), do: Regex.scan(~r/[\w\/.\-]+\.exs?\b/, message) |> List.flatten()
end
