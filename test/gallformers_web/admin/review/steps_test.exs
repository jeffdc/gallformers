defmodule GallformersWeb.Admin.Review.StepsTest do
  @moduledoc """
  The five steps of a Source's review (matter `d213`, Task 15): which
  sections each holds, and what is left, recommended and holding approval
  in each.
  """
  use ExUnit.Case, async: true

  alias GallformersWeb.Admin.Review.Steps

  # An entry as `GallformersWeb.Admin.ReviewLive.Loader.entries/2` shapes it,
  # with only what the steps read.
  defp entry(section, opts \\ []) do
    status = Keyword.get(opts, :status, :open)

    %{
      item: %{status: status},
      question: %{
        section: %{id: section},
        proposal: Keyword.get(opts, :proposal)
      },
      holds: status == :open and Keyword.get(opts, :holds, false),
      rejected: Keyword.get(opts, :rejected, false)
    }
  end

  @proposal %{label: "Quercus lobata", why: nil, firm: true, decision: %{}, pending: false}

  test "five steps in order, each with its question and whether it holds approval" do
    assert Enum.map(Steps.all(), & &1.slug) == ~w(names galls disputes traits hedges)
    assert Enum.map(Steps.all(), & &1.n) == [1, 2, 3, 4, 5]
    assert Enum.map(Steps.all(), & &1.holds_approval) == [true, true, true, false, false]

    assert %{title: "Names", question: "Which organisms does the Source mean?"} =
             Steps.get("names")

    assert Steps.get("overview") == nil
  end

  test "each section belongs to one step; the Source's own question to none" do
    assert Steps.get("names").sections == [:hosts, :which_taxon, :differ]

    assert Steps.get("galls").sections == [
             :named_galls,
             :undescribed_galls,
             :generation_outside,
             :gall_rename
           ]

    assert Steps.step_of(:hosts) == :names
    assert Steps.step_of(:which_taxon) == :names
    assert Steps.step_of(:differ) == :names
    assert Steps.step_of(:named_galls) == :galls
    assert Steps.step_of(:undescribed_galls) == :galls
    assert Steps.step_of(:gall_rename) == :galls
    assert Steps.step_of(:same_date) == :disputes
    assert Steps.step_of(:trait_terms) == :traits

    # Hedges are grouped by what each is about (d213, Task 21).
    assert Steps.get("hedges").sections == [
             :hedge_names,
             :hedge_inducer,
             :hedge_host,
             :hedge_range,
             :hedge_gall,
             :hedge_other
           ]

    for s <- Steps.get("hedges").sections, do: assert(Steps.step_of(s) == :hedges)
    assert Steps.step_of(:source) == nil
    assert Steps.step_of(:something_new) == nil
  end

  test "what is left, recommended and holding approval in each step" do
    entries = [
      entry(:hosts, holds: true, proposal: @proposal),
      entry(:which_taxon, holds: true),
      entry(:differ, status: :decided),
      entry(:hosts, holds: true, proposal: @proposal, rejected: true),
      entry(:trait_terms, proposal: @proposal),
      entry(:source, holds: true)
    ]

    [names, galls, _disputes, traits, _hedges] = Steps.summarize(entries)

    assert %{step: %{id: :names}, total: 4, left: 3, recommended: 1, holding: 3} = names
    assert %{total: 0, left: 0, recommended: 0, holding: 0} = galls
    assert %{total: 1, left: 1, recommended: 1, holding: 0} = traits
  end

  test "the first step with work left, and the steps that hold approval" do
    summaries = Steps.summarize([entry(:disputes, holds: true), entry(:trait_terms)])

    assert %{id: :disputes} = Steps.first_open(summaries)
    assert [%{id: :disputes}] = Steps.holding(summaries)

    assert Steps.first_open(Steps.summarize([entry(:hosts, status: :decided)])) == nil
  end

  test "the entries of a step, and those in no step" do
    entries = [entry(:hosts), entry(:source), entry(:trait_terms), entry(:something_new)]

    assert [%{question: %{section: %{id: :hosts}}}] = Steps.entries(entries, Steps.get("names"))

    assert [
             %{question: %{section: %{id: :source}}},
             %{question: %{section: %{id: :something_new}}}
           ] =
             Steps.unplaced(entries)
  end
end
