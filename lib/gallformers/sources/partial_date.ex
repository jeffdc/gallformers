defmodule Gallformers.Sources.PartialDate do
  @moduledoc """
  A date known to a year, a month or a day, as Sources give them (`"1897"`,
  `"1897-05"`, `"1897-05-14"`, the contract's `date_partial`).

  It is stored as the first day of the period it names plus its precision,
  so `"1897"` is `{~D[1897-01-01], :year}`.
  """

  @type precision :: :year | :month | :day

  @doc """
  Parses `YYYY`, `YYYY-MM` or `YYYY-MM-DD` into its first day and precision.
  """
  @spec parse(String.t()) :: {:ok, {Date.t(), precision()}} | :error
  def parse(<<y::binary-size(4)>>), do: build([y, "01", "01"], :year)
  def parse(<<y::binary-size(4), ?-, m::binary-size(2)>>), do: build([y, m, "01"], :month)

  def parse(<<y::binary-size(4), ?-, m::binary-size(2), ?-, d::binary-size(2)>>),
    do: build([y, m, d], :day)

  def parse(_), do: :error

  @doc "Formats a stored date at its precision, the inverse of `parse/1`."
  @spec format(Date.t(), precision()) :: String.t()
  def format(%Date{} = date, :year), do: pad(date.year, 4)
  def format(%Date{} = date, :month), do: "#{pad(date.year, 4)}-#{pad(date.month, 2)}"
  def format(%Date{} = date, :day), do: Date.to_iso8601(date)

  defp build(parts, precision) do
    with [year, month, day] when is_integer(year) and is_integer(month) and is_integer(day) <-
           Enum.map(parts, &digits/1),
         {:ok, date} <- Date.new(year, month, day) do
      {:ok, {date, precision}}
    else
      _ -> :error
    end
  end

  defp digits(string) do
    if string =~ ~r/\A[0-9]+\z/, do: String.to_integer(string)
  end

  defp pad(number, width), do: number |> Integer.to_string() |> String.pad_leading(width, "0")
end
