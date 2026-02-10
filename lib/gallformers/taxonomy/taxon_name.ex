defmodule Gallformers.Taxonomy.TaxonName do
  @moduledoc """
  Pure-logic module for parsing, formatting, and reasoning about taxonomic names.

  No database access — all functions operate on strings and structs.
  Centralizes the scattered name-parsing regexes and italic-logic that were
  previously duplicated across 20+ files.

  ## Struct

  `parse/1` returns a `%TaxonName{}` with pre-split fields so callers don't
  need to re-discover the Unknown pattern:

      iex> parse("Unknown (Cynipidae) foobarrus agamic")
      %TaxonName{
        raw: "Unknown (Cynipidae) foobarrus agamic",
        genus: "Unknown (Cynipidae)",
        family: "Cynipidae",
        epithet: "foobarrus",
        qualifier: "agamic",
        full_epithet: "foobarrus agamic",
        unknown?: true
      }

  The `family` field is only populated for Unknown genera — it extracts the
  name inside the parentheses (e.g., `"Unknown (Cynipidae)"` → `family: "Cynipidae"`).
  For known genera, `family` is always `nil`. Use `unknown?` to distinguish the two cases.
  """

  @unknown_genus_re ~r/^Unknown \(([^)]+)\)/

  defstruct [:raw, :genus, :family, :epithet, :qualifier, :full_epithet, unknown?: false]

  @type t :: %__MODULE__{
          raw: String.t(),
          genus: String.t(),
          family: String.t() | nil,
          epithet: String.t() | nil,
          qualifier: String.t() | nil,
          full_epithet: String.t() | nil,
          unknown?: boolean()
        }

  @doc """
  Parses a species name string into a `%TaxonName{}` struct.

  Correctly handles the "Unknown (Family) epithet qualifier" pattern that
  breaks naive `String.split(name, " ", parts: 2)` approaches.

  ## Examples

      iex> parse("Andricus quercuslanigera")
      %TaxonName{raw: "Andricus quercuslanigera", genus: "Andricus",
        epithet: "quercuslanigera", qualifier: nil, full_epithet: "quercuslanigera",
        unknown?: false}

      iex> parse("Unknown (Cynipidae)")
      %TaxonName{raw: "Unknown (Cynipidae)", genus: "Unknown (Cynipidae)",
        family: "Cynipidae", epithet: nil, qualifier: nil, full_epithet: nil,
        unknown?: true}

      iex> parse("")
      %TaxonName{raw: "", genus: "", epithet: nil, qualifier: nil,
        full_epithet: nil, unknown?: false}
  """
  @spec parse(String.t()) :: t()
  def parse(name) when is_binary(name) do
    case Regex.run(@unknown_genus_re, name) do
      [genus_display, family] ->
        rest = String.trim_leading(name, genus_display) |> String.trim_leading()
        build_struct(name, genus_display, family, rest, true)

      nil ->
        case String.split(name, " ", parts: 2) do
          [genus, rest] -> build_struct(name, genus, nil, rest, false)
          _ -> build_struct(name, name, nil, "", false)
        end
    end
  end

  defp build_struct(raw, genus, family, "", unknown?) do
    %__MODULE__{
      raw: raw,
      genus: genus,
      family: family,
      epithet: nil,
      qualifier: nil,
      full_epithet: nil,
      unknown?: unknown?
    }
  end

  defp build_struct(raw, genus, family, rest, unknown?) do
    parts = String.split(rest, " ", parts: 2)
    epithet = hd(parts)

    qualifier =
      case parts do
        [_, q] -> q
        _ -> nil
      end

    %__MODULE__{
      raw: raw,
      genus: genus,
      family: family,
      epithet: epithet,
      qualifier: qualifier,
      full_epithet: rest,
      unknown?: unknown?
    }
  end

  @doc """
  Extracts the genus display portion from a species name.

  For "Unknown (Family) epithet" returns "Unknown (Family)".
  For "Genus epithet" returns "Genus".

  ## Examples

      iex> genus_display("Andricus quercuslanigera")
      "Andricus"

      iex> genus_display("Unknown (Cynipidae) oak-apple")
      "Unknown (Cynipidae)"

      iex> genus_display("Andricus")
      "Andricus"
  """
  @spec genus_display(String.t()) :: String.t()
  def genus_display(name) when is_binary(name) do
    parse(name).genus
  end

  @doc """
  Extracts the epithet (everything after the genus portion) from a species name.

  Handles "Unknown (Family) epithet" and "Genus epithet" formats.
  Returns the full_epithet (including qualifier) for backward compatibility.

  ## Examples

      iex> epithet("Andricus quercuslanigera")
      "quercuslanigera"

      iex> epithet("Unknown (Cynipidae) oak-apple")
      "oak-apple"

      iex> epithet("Andricus")
      ""
  """
  @spec epithet(String.t()) :: String.t()
  def epithet(name) when is_binary(name) do
    parse(name).full_epithet || ""
  end

  @doc """
  Replaces the genus portion of a species name with a new genus.

  Handles both "Genus epithet" and "Unknown (Family) epithet" formats.

  ## Examples

      iex> replace_genus("Andricus quercuslanigera", "Andricus", "Callirhytis")
      "Callirhytis quercuslanigera"

      iex> replace_genus("Unknown (Cynipidae) oak-apple", "Unknown (Cynipidae)", "Andricus")
      "Andricus oak-apple"

      iex> replace_genus("Andricus", "Andricus", "Callirhytis")
      "Callirhytis"
  """
  @spec replace_genus(String.t(), String.t(), String.t()) :: String.t()
  def replace_genus(species_name, old_genus, new_genus) do
    if String.starts_with?(species_name, old_genus) do
      rest = String.trim_leading(species_name, old_genus) |> String.trim_leading()

      case rest do
        "" -> new_genus
        ep -> "#{new_genus} #{ep}"
      end
    else
      # Old genus doesn't match prefix — fall back to replacing first word
      case String.split(species_name, " ", parts: 2) do
        [_genus, ep] -> "#{new_genus} #{ep}"
        _ -> species_name
      end
    end
  end

  @doc """
  Combines a genus display name and an epithet into a full species name.

  ## Examples

      iex> build("Andricus", "quercuslanigera")
      "Andricus quercuslanigera"

      iex> build("Unknown (Cynipidae)", "")
      "Unknown (Cynipidae)"
  """
  @spec build(String.t(), String.t()) :: String.t()
  def build(genus_display, ""), do: genus_display
  def build(genus_display, epithet), do: "#{genus_display} #{epithet}"

  @doc """
  Returns true if the given genus name represents a placeholder (Unknown) genus.

  ## Examples

      iex> unknown_genus?("Unknown (Cynipidae)")
      true

      iex> unknown_genus?("Unknown")
      true

      iex> unknown_genus?("Andricus")
      false

      iex> unknown_genus?(nil)
      false
  """
  @spec unknown_genus?(String.t() | nil) :: boolean()
  def unknown_genus?(nil), do: false
  def unknown_genus?("Unknown"), do: true
  def unknown_genus?("Unknown " <> _), do: true
  def unknown_genus?(_), do: false

  @doc """
  Returns true if the given taxonomic rank should be italicized per biological convention.

  Species, genus, section, and subgenus names are italicized.
  Family (-idae), subfamily (-inae), superfamily (-oidea), tribe (-ini/-ina),
  and higher ranks are NOT italicized.

  ## Examples

      iex> italicize_rank?("genus")
      true

      iex> italicize_rank?("species")
      true

      iex> italicize_rank?("section")
      true

      iex> italicize_rank?("family")
      false
  """
  @spec italicize_rank?(String.t()) :: boolean()
  def italicize_rank?(rank) when is_binary(rank) do
    rank in ["species", "genus", "section"]
  end

  @doc """
  Heuristic: should a taxon name be italicized based on its suffix?

  Genus and species names are italicized; family (-idae), subfamily (-inae),
  superfamily (-oidea), and tribe (-ini/-ina) names are not.

  Used when only the name is available (no rank metadata), e.g. in ID keys.

  ## Examples

      iex> italicize_name?("Andricus")
      true

      iex> italicize_name?("Cynipidae")
      false

      iex> italicize_name?("Ichneumonoidea")
      false

      iex> italicize_name?("Eurytominae")
      false
  """
  @spec italicize_name?(String.t()) :: boolean()
  def italicize_name?(name) when is_binary(name) do
    first_word = name |> String.split(~r/[\s(]/, parts: 2) |> hd()

    not String.match?(first_word, ~r/(oidea|idae|inae|ini|ina)$/i)
  end
end
