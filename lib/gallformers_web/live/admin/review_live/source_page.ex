defmodule GallformersWeb.Admin.ReviewLive.SourcePage do
  @moduledoc """
  What a Source's overview (`GallformersWeb.Admin.ReviewLive.Source`) and
  its step pages (`GallformersWeb.Admin.ReviewLive.Step`) share (matter
  `d213`, Task 15): which Source or package the page is of, loading its
  packages and questions with what is left in each step
  (`GallformersWeb.Admin.Review.Steps`), what Approve waits for, and
  approving from the step bar.

  A page is of a Source (`/admin/review/sources/:id`, its packages under
  review together) or of one package (`/admin/review/packages/:id`, one not
  matched to a Source yet, or one Gallformers note); its steps are at
  `<base>/<step>`.
  """
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Gallformers.Catalog
  alias Gallformers.Import
  alias GallformersWeb.Admin.Review.Questions
  alias GallformersWeb.Admin.Review.Steps
  alias GallformersWeb.Admin.ReviewLive.Loader

  @typedoc "Whose page it is."
  @type mode :: {:source, integer()} | {:package, integer()}

  @typedoc "What the step bar shows for Approve (`GallformersWeb.ReviewComponents.review_step_bar/1`)."
  @type approval ::
          :approved | :resolving | :none | {:waiting, [String.t()]} | {:ready, [String.t()]}

  @doc "Whose page the route's params name."
  @spec mode(map()) :: mode()
  def mode(%{"package_id" => id}), do: {:package, String.to_integer(id)}
  def mode(%{"id" => id}), do: {:source, String.to_integer(id)}

  @doc "The overview's path; a step's is `<base>/<slug>`."
  @spec base_path(mode()) :: String.t()
  def base_path({:source, id}), do: "/admin/review/sources/#{id}"
  def base_path({:package, id}), do: "/admin/review/packages/#{id}"

  @doc """
  Loads the page's packages and questions into `socket` (on a step's page,
  with what that step's answers show besides, and with every step's given
  `context: :all`: `Loader.entries/3`): `summary`,
  `name` (the Source's short name, else its title), `packages`, `entries`,
  `summaries` (per step), `approval`, `stats` and `definitions`. Raises
  `Ecto.NoResultsError` when there is no such Source or package.
  """
  @spec load(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def load(socket) do
    data =
      case socket.assigns.mode do
        {:source, id} -> Loader.source_page(id, socket.assigns.keep)
        {:package, id} -> Loader.package_page(id)
      end

    if data == nil, do: raise(Ecto.NoResultsError, queryable: Gallformers.Import.Package)

    summary = data.summary
    step = socket.assigns[:context] || (socket.assigns[:step] && socket.assigns.step.id)
    entries = Loader.entries(data.packages, summary.who, step: step)
    summaries = Steps.summarize(entries)

    assign(socket,
      page_title: name(summary),
      source: data.source,
      summary: summary,
      name: name(summary),
      packages: data.packages,
      keep: Enum.map(data.packages, & &1.package.id),
      entries: entries,
      summaries: summaries,
      approval: approval(data.packages, entries, summaries),
      stats: Loader.stats(data.packages),
      definitions: Catalog.trait_definitions()
    )
  end

  @doc "What the pages call the Source: its short name, else its title."
  @spec name(map()) :: String.t()
  def name(%{kind: "Gallformers notes", title: title}), do: title
  def name(%{who: who}) when is_binary(who), do: who
  def name(%{title: title}), do: title

  @doc """
  What Approve waits for: `:approved` once every package is; `:resolving`
  while one still is; `{:waiting, titles}` while an open question holds
  approval (the steps holding it, and the overview's own questions);
  `{:ready, later}` once nothing does, `later` naming what stays open
  ("3 trait terms", "1 hedge"); `:none` with nothing awaiting review.
  """
  @spec approval([map()], [map()], [Steps.summary()]) :: approval()
  def approval(packages, entries, summaries) do
    statuses = Enum.map(packages, & &1.package.status)
    waiting = Enum.map(Steps.holding(summaries), & &1.title) ++ unplaced_holding(entries)

    cond do
      statuses != [] and Enum.all?(statuses, &(&1 == :approved)) -> :approved
      Enum.any?(statuses, &(&1 in [:validated, :resolving])) -> :resolving
      waiting != [] -> {:waiting, waiting}
      :awaiting_review in statuses -> {:ready, later(summaries)}
      true -> :none
    end
  end

  defp unplaced_holding(entries) do
    entries
    |> Steps.unplaced()
    |> Enum.filter(&(&1.item.status == :open and &1.holds))
    |> Enum.map(& &1.question.section.title)
    |> Enum.uniq()
  end

  defp later(summaries) do
    for %{left: left, step: step} <- summaries, left > 0, do: later_text(step.id, left, step)
  end

  defp later_text(:traits, 1, _step), do: "1 trait term"
  defp later_text(:traits, n, _step), do: "#{n} trait terms"
  defp later_text(:hedges, 1, _step), do: "1 hedge"
  defp later_text(:hedges, n, _step), do: "#{n} hedges"
  defp later_text(_id, 1, step), do: "1 #{step.title} question"
  defp later_text(_id, n, step), do: "#{n} #{step.title} questions"

  @doc "A line on what approval waits for, for the overview."
  @spec approval_text(approval()) :: String.t() | nil
  def approval_text(:approved), do: "Approved."
  def approval_text(:resolving), do: "The Source is still resolving; Approve waits for it."

  def approval_text({:waiting, titles}),
    do:
      "Approve appears once #{and_list(titles)} #{if length(titles) == 1, do: "is", else: "are"} settled."

  def approval_text({:ready, _later}), do: "Nothing holds approval. Approve is in the bar above."
  def approval_text(:none), do: nil

  defp and_list([one]), do: one
  defp and_list(list), do: Enum.join(Enum.drop(list, -1), ", ") <> " and " <> List.last(list)

  @doc """
  Approves the page's packages awaiting review
  (`Gallformers.Import.approve_package/2`), with a flash saying how it
  went. The caller loads the page again.
  """
  @spec approve(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def approve(socket) do
    %{actor: actor, packages: packages} = socket.assigns
    awaiting = for p <- packages, p.package.status == :awaiting_review, do: p.package

    results = Enum.map(awaiting, &Import.approve_package(actor, &1))

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil when awaiting != [] ->
        put_flash(
          socket,
          :info,
          "The Source was approved; its statements are applied by the import worker."
        )

      nil ->
        put_flash(socket, :error, "Nothing here is awaiting review.")

      {:error, {:open_items, _items}} ->
        put_flash(socket, :error, "Approval is held: questions that hold it are still open.")

      {:error, {:blocked, _batches}} ->
        put_flash(socket, :error, "Approval is held: Host names are still unsettled.")

      {:error, :not_approvable} ->
        put_flash(socket, :error, "Only a Source awaiting review can be approved.")

      {:error, reason} ->
        put_flash(socket, :error, "The Source could not be approved: #{inspect(reason)}")
    end
  end

  @doc """
  The sections of `entries` among `section_ids`, in that order, each with
  its rows (decided ones too), its open ones and how many have a proposal
  to accept together.
  """
  @spec sections([map()], [atom()], String.t() | nil) :: [map()]
  def sections(entries, section_ids, who) do
    by_section = Enum.group_by(entries, & &1.question.section.id)

    for id <- section_ids, rows = Map.get(by_section, id, []), rows != [] do
      open = Enum.filter(rows, &(&1.item.status == :open))

      %{
        section: Questions.section(id, who),
        rows: rows,
        open: open,
        proposable: Enum.count(open, & &1.proposable)
      }
    end
  end
end
