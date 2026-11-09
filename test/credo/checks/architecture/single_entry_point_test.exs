Code.require_file(
  Path.expand("../../../../dev/credo/checks/architecture/single_entry_point.ex", __DIR__)
)

defmodule Gallformers.Credo.Checks.Architecture.SingleEntryPointTest do
  use Credo.Test.Case

  alias Gallformers.Credo.Checks.Architecture.SingleEntryPoint

  @capabilities [
    capabilities: [
      %{
        name: "WCVP name search",
        calls: [
          {Gallformers.Wcvp.Lookup, [:search, :search_contains]},
          {:wcvp_lookup, [:search, :search_contains]}
        ],
        scope: "lib/gallformers_web/",
        owners: [GallformersWeb.Choices],
        pending: [{GallformersWeb.Admin.TaxonomyLive.New, "b230"}]
      },
      %{
        name: "Host choices",
        calls: [{Gallformers.Taxa, [:host_choices]}],
        scope: "lib/gallformers_web/",
        owners: [GallformersWeb.Choices],
        pending: []
      }
    ]
  ]

  setup_all do
    Application.ensure_all_started(:credo)
    :ok
  end

  defp check(source, filename \\ "lib/gallformers_web/live/some_live.ex") do
    source |> to_source_file(filename) |> run_check(SingleEntryPoint, @capabilities)
  end

  describe "a call from a module other than the owner" do
    test "is flagged when the module is named in full" do
      """
      defmodule GallformersWeb.SomeLive do
        def search(q), do: Gallformers.Wcvp.Lookup.search(q, limit: 10)
      end
      """
      |> check()
      |> assert_issue(fn issue ->
        assert issue.message =~ "WCVP name search"
        assert issue.message =~ "GallformersWeb.Choices"
      end)
    end

    test "is flagged through a behaviour accessor, in a pipe" do
      """
      defmodule GallformersWeb.SomeLive do
        def search(q), do: q |> wcvp_lookup().search(limit: 10)
        defp wcvp_lookup, do: Application.get_env(:gallformers, :wcvp_lookup)
      end
      """
      |> check()
      |> assert_issue()
    end

    test "is flagged through an alias" do
      """
      defmodule GallformersWeb.SomeLive do
        alias Gallformers.Wcvp.Lookup
        def search(q), do: Lookup.search_contains(q, limit: 10)
      end
      """
      |> check()
      |> assert_issue()
    end

    test "is flagged through a multi-alias" do
      """
      defmodule GallformersWeb.SomeLive do
        alias Gallformers.{Import, Taxa}
        def hosts(q), do: Taxa.host_choices(q, 10)
      end
      """
      |> check()
      |> assert_issue(fn issue -> assert issue.message =~ "Host choices" end)
    end

    test "is flagged through an alias with :as" do
      """
      defmodule GallformersWeb.SomeLive do
        alias Gallformers.Taxa, as: T
        def hosts(q), do: T.host_choices(q, 10)
      end
      """
      |> check()
      |> assert_issue()
    end

    test "is flagged in a module nested in another" do
      """
      defmodule GallformersWeb.Choices do
        defmodule Inner do
          def hosts(q), do: Gallformers.Taxa.host_choices(q, 10)
        end
      end
      """
      |> check()
      |> assert_issue()
    end
  end

  describe "allowed" do
    test "the owner's own call" do
      """
      defmodule GallformersWeb.Choices do
        alias Gallformers.Taxa
        def hosts(q), do: Taxa.host_choices(q, 10)
        def plants(q), do: q |> wcvp_lookup().search(limit: 10)
      end
      """
      |> check()
      |> refute_issues()
    end

    test "a pending caller that still makes the call" do
      """
      defmodule GallformersWeb.Admin.TaxonomyLive.New do
        def search(q), do: q |> wcvp_lookup().search(limit: 10)
      end
      """
      |> check()
      |> refute_issues()
    end

    test "other functions of the same module" do
      """
      defmodule GallformersWeb.SomeLive do
        def pick(id), do: wcvp_lookup().get(id)
        def taxon(id), do: Gallformers.Taxa.get_taxon!(id)
      end
      """
      |> check()
      |> refute_issues()
    end

    test "a call outside the capability's scope" do
      """
      defmodule Gallformers.Import.InatTaxa do
        def names(q), do: q |> wcvp_lookup().search(limit: 10)
      end
      """
      |> check("lib/gallformers/import/inat_taxa.ex")
      |> refute_issues()
    end
  end

  test "a pending caller that no longer makes the call is reported, so the list only shrinks" do
    """
    defmodule GallformersWeb.Admin.TaxonomyLive.New do
      alias GallformersWeb.Choices
      def search(q), do: Choices.wcvp_plants(q, 10)
    end
    """
    |> check()
    |> assert_issue(fn issue ->
      assert issue.message =~ "no longer calls"
      assert issue.message =~ "pending"
    end)
  end
end
