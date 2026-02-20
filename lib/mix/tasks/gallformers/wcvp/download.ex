defmodule Mix.Tasks.Gallformers.Wcvp.Download do
  @moduledoc """
  Downloads the WCVP (World Checklist of Vascular Plants) data from Kew.

  ## Usage

      mix gallformers.wcvp.download

  Downloads wcvp.zip from Kew's SFTP server and extracts CSV files to
  priv/repo/data/wcvp/. Existing files are overwritten.
  """

  use Mix.Task

  @shortdoc "Download WCVP plant taxonomy data from Kew"

  @wcvp_url "https://sftp.kew.org/pub/data-repositories/WCVP/wcvp.zip"
  @data_dir "priv/repo/data/wcvp"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    File.mkdir_p!(@data_dir)
    zip_path = Path.join(@data_dir, "wcvp.zip")

    IO.puts("Downloading WCVP data from Kew...")
    IO.puts("URL: #{@wcvp_url}")
    IO.puts("This file is ~85MB — download may take a minute.")

    case System.cmd("curl", ["-L", "-o", zip_path, @wcvp_url],
           stderr_to_stdout: true,
           into: IO.stream()
         ) do
      {_, 0} ->
        IO.puts("\nDownload complete. Extracting...")
        extract_zip(zip_path)
        verify_files()

      {output, code} ->
        Mix.raise("Download failed (exit code #{code}): #{output}")
    end
  end

  defp extract_zip(zip_path) do
    case System.cmd("unzip", ["-o", zip_path, "-d", @data_dir], stderr_to_stdout: true) do
      {_, 0} ->
        IO.puts("Extracted to #{@data_dir}/")
        File.rm(zip_path)
        IO.puts("Removed zip file.")

      {output, code} ->
        Mix.raise("Extraction failed (exit code #{code}): #{output}")
    end
  end

  defp verify_files do
    names_path = Path.join(@data_dir, "wcvp_names.csv")
    dist_path = Path.join(@data_dir, "wcvp_distribution.csv")

    cond do
      not File.exists?(names_path) ->
        check_nested_files()

      not File.exists?(dist_path) ->
        check_nested_files()

      true ->
        names_size = File.stat!(names_path).size |> format_size()
        dist_size = File.stat!(dist_path).size |> format_size()
        IO.puts("\nReady:")
        IO.puts("  #{names_path} (#{names_size})")
        IO.puts("  #{dist_path} (#{dist_size})")
    end
  end

  defp check_nested_files do
    # WCVP zip may extract into a subdirectory
    case File.ls!(@data_dir) |> Enum.filter(&File.dir?(Path.join(@data_dir, &1))) do
      [subdir | _] ->
        nested = Path.join(@data_dir, subdir)
        IO.puts("Found nested directory: #{nested}")
        IO.puts("Moving files up...")

        nested
        |> File.ls!()
        |> Enum.each(fn file ->
          File.rename!(Path.join(nested, file), Path.join(@data_dir, file))
        end)

        File.rmdir(nested)
        verify_files()

      [] ->
        IO.puts("\nWarning: Expected CSV files not found. Contents of #{@data_dir}:")

        @data_dir
        |> File.ls!()
        |> Enum.each(fn f -> IO.puts("  #{f}") end)
    end
  end

  defp format_size(bytes) when bytes > 1_000_000, do: "#{Float.round(bytes / 1_000_000, 1)} MB"
  defp format_size(bytes) when bytes > 1_000, do: "#{Float.round(bytes / 1_000, 1)} KB"
  defp format_size(bytes), do: "#{bytes} B"
end
