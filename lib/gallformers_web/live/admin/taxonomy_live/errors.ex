defmodule GallformersWeb.Admin.TaxonomyLive.Errors do
  @moduledoc """
  The taxonomy admin's write errors as sentences for a flash: a changeset's
  errors, a refused move, a referenced taxon.
  """

  @doc "A write's error as a sentence for a flash."
  @spec text(term()) :: String.t()
  def text(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&message/1)
    |> Enum.map_join("; ", fn {field, messages} ->
      "#{Phoenix.Naming.humanize(field)} #{Enum.join(messages, ", ")}"
    end)
  end

  def text({:referenced, _references}), do: "something still refers to it"
  def text({:rejected, _listener, reason}), do: "rejected: #{inspect(reason)}"
  def text(:accepted_name), do: "that is the accepted name; rename the taxon instead"
  def text(:not_found), do: "it no longer exists"
  def text(reason) when is_binary(reason), do: reason
  def text(reason), do: inspect(reason)

  # A changeset error's message with its options filled in.
  defp message({message, opts}),
    do: Enum.reduce(opts, message, fn {key, value}, acc -> fill(acc, key, value) end)

  defp fill(message, key, value),
    do: String.replace(message, "%{#{key}}", fn _ -> option_text(value) end)

  defp option_text(value) when is_binary(value) or is_atom(value) or is_number(value),
    do: to_string(value)

  defp option_text(value), do: inspect(value)
end
