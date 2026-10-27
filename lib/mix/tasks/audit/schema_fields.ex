defmodule Mix.Tasks.Audit.SchemaFields do
  use Boundary, check: [in: false, out: false]

  @moduledoc """
  Audits database records for required field violations.

  Checks all schemas implementing the `Gallformers.SchemaFields` behavior
  and reports any records with NULL or empty values in required fields.

  ## Usage

      # Audit all schemas implementing SchemaFields
      mix audit.schema_fields

      # Audit a specific schema
      mix audit.schema_fields Source
      mix audit.schema_fields Gallformers.Sources.Source

      # Output as CSV
      mix audit.schema_fields --format=csv

      # Show only summary (no individual violations)
      mix audit.schema_fields --summary

  ## Options

    * `--format` - Output format: `text` (default) or `csv`
    * `--summary` - Show only summary counts, not individual violations

  """
  use Mix.Task

  @shortdoc "Audit database for required field violations"

  @schemas [
    Gallformers.Sources.Source
    # Add more schemas here as they implement SchemaFields
  ]

  @impl Mix.Task
  def run(args) do
    {opts, args, _} =
      OptionParser.parse(args,
        strict: [format: :string, summary: :boolean],
        aliases: [f: :format, s: :summary]
      )

    format = Keyword.get(opts, :format, "text")
    summary_only = Keyword.get(opts, :summary, false)

    Mix.Task.run("app.start")

    schemas = parse_schema_args(args)

    case format do
      "csv" -> audit_csv(schemas, summary_only)
      _ -> audit_text(schemas, summary_only)
    end
  end

  defp parse_schema_args([]), do: @schemas

  defp parse_schema_args(args) do
    Enum.map(args, &find_schema_module/1)
  end

  defp find_schema_module(arg) do
    candidates = [
      arg,
      "Gallformers.#{arg}",
      "Gallformers.Sources.#{arg}"
    ]

    case Enum.find_value(candidates, &valid_schema_module/1) do
      nil -> Mix.raise("Schema not found or doesn't implement SchemaFields: #{arg}")
      module -> module
    end
  end

  defp valid_schema_module(candidate) do
    module = Module.concat([candidate])

    if Code.ensure_loaded?(module) && function_exported?(module, :required_fields, 0) do
      module
    end
  end

  defp audit_text(schemas, summary_only) do
    results =
      Enum.map(schemas, fn schema ->
        {schema, audit_schema(schema)}
      end)

    total_violations =
      Enum.reduce(results, 0, fn {_schema, violations}, acc ->
        acc + length(violations)
      end)

    Enum.each(results, fn {schema, violations} ->
      print_schema_results_text(schema, violations, summary_only)
    end)

    IO.puts("")

    if total_violations == 0 do
      IO.puts(IO.ANSI.green() <> "All records comply with required fields." <> IO.ANSI.reset())
    else
      IO.puts(
        IO.ANSI.yellow() <>
          "Total: #{total_violations} violation(s) found." <> IO.ANSI.reset()
      )
    end
  end

  defp audit_csv(schemas, true = _summary_only) do
    IO.puts("schema,total_records,violations,compliant_pct")
    Enum.each(schemas, &print_csv_summary/1)
  end

  defp audit_csv(schemas, false = _summary_only) do
    IO.puts("schema,id,identifier,field,value")
    Enum.each(schemas, &print_csv_details/1)
  end

  defp print_csv_summary(schema) do
    violations = audit_schema(schema)
    total = count_records(schema)
    compliant_pct = if total > 0, do: Float.round((total - length(violations)) / total * 100, 1)
    schema_name = schema |> Module.split() |> List.last()
    IO.puts("#{schema_name},#{total},#{length(violations)},#{compliant_pct}")
  end

  defp print_csv_details(schema) do
    violations = audit_schema(schema)
    schema_name = schema |> Module.split() |> List.last()
    Enum.each(violations, &print_csv_violation(&1, schema_name))
  end

  defp print_csv_violation(v, schema_name) do
    identifier = escape_csv(v.identifier || "")
    value = escape_csv(inspect(v.value))
    IO.puts("#{schema_name},#{v.id},#{identifier},#{v.field},#{value}")
  end

  defp print_schema_results_text(schema, violations, summary_only) do
    schema_name = schema |> Module.split() |> List.last()
    required = Gallformers.SchemaFields.get_required_fields(schema)
    total = count_records(schema)

    IO.puts("")
    IO.puts(IO.ANSI.bright() <> "#{schema_name}" <> IO.ANSI.reset())
    IO.puts("  Required fields: #{Enum.join(required, ", ")}")
    IO.puts("  Total records: #{total}")

    print_violations_text(violations, summary_only)
  end

  defp print_violations_text([], _summary_only) do
    IO.puts(IO.ANSI.green() <> "  Status: All records compliant" <> IO.ANSI.reset())
  end

  defp print_violations_text(violations, summary_only) do
    by_field =
      violations
      |> Enum.group_by(& &1.field)
      |> Enum.sort_by(fn {_field, vs} -> -length(vs) end)

    IO.puts(IO.ANSI.yellow() <> "  Violations: #{length(violations)}" <> IO.ANSI.reset())

    Enum.each(by_field, fn {field, field_violations} ->
      IO.puts("    #{field}: #{length(field_violations)} record(s)")
    end)

    unless summary_only, do: print_violation_details(violations)
  end

  defp print_violation_details(violations) do
    IO.puts("")
    IO.puts("  Details:")
    Enum.each(Enum.sort_by(violations, & &1.id), &print_violation_line/1)
  end

  defp print_violation_line(v) do
    identifier = if v.identifier, do: " (#{truncate(v.identifier, 50)})", else: ""
    IO.puts("    ##{v.id}#{identifier} - missing: #{v.field}")
  end

  defp audit_schema(schema) do
    import Ecto.Query

    required_fields = Gallformers.SchemaFields.get_required_fields(schema)
    identifier_field = get_identifier_field(schema)

    Enum.flat_map(required_fields, fn field ->
      query =
        from(r in schema,
          where: is_nil(field(r, ^field)) or field(r, ^field) == "",
          select: %{
            id: r.id,
            identifier: field(r, ^identifier_field),
            value: field(r, ^field)
          }
        )

      Gallformers.Repo.all(query)
      |> Enum.map(&Map.put(&1, :field, field))
    end)
  end

  defp count_records(schema) do
    import Ecto.Query
    Gallformers.Repo.aggregate(from(r in schema), :count)
  end

  # Determine a human-readable identifier field for each schema
  defp get_identifier_field(schema) do
    cond do
      has_field?(schema, :title) -> :title
      has_field?(schema, :name) -> :name
      has_field?(schema, :word) -> :word
      true -> :id
    end
  end

  defp has_field?(schema, field) do
    field in schema.__schema__(:fields)
  end

  defp truncate(string, max) when is_binary(string) do
    if String.length(string) > max do
      String.slice(string, 0, max - 3) <> "..."
    else
      string
    end
  end

  defp truncate(other, _max), do: inspect(other)

  defp escape_csv(string) when is_binary(string) do
    if String.contains?(string, [",", "\"", "\n"]) do
      "\"#{String.replace(string, "\"", "\"\"")}\""
    else
      string
    end
  end

  defp escape_csv(other), do: inspect(other)
end
