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
  def text({:outranked, message}), do: message
  def text({:still_held, message}), do: message
  def text({:rejected, _listener, {:tree, _taxon_id, _validation, message}}), do: message
  def text({:rejected, _listener, reason}), do: "rejected: #{inspect(reason)}"

  def text(:undated_source),
    do:
      "that Source has no date: give it one in the Source editor, as a change competes by its Source's date"

  def text(:retracted_source), do: "that Source is retracted"

  def text(:own_source),
    do: "pick the paper it follows, or No Source for Gallformers' own position"

  def text(:reason_required), do: "give the reason for Gallformers' own position"
  def text(:plant), do: "a plant is edited directly, not credited to a Source"
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
