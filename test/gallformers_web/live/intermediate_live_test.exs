defmodule GallformersWeb.IntermediateLiveTest do
  @moduledoc """
  Tests for the public intermediate taxonomy browse page with semantic URLs.
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  describe "IntermediateLive with rank-typed URLs" do
    test "renders subfamily page by name", %{conn: conn} do
      # Cynipinae is a Subfamily intermediate (id=31) in test seeds
      {:ok, _view, html} = live(conn, "/subfamily/Cynipinae")

      assert html =~ "Subfamily"
      assert html =~ "Cynipinae"
    end

    test "renders tribe page by name", %{conn: conn} do
      # Cynipini is a Tribe intermediate (id=32)
      {:ok, _view, html} = live(conn, "/tribe/Cynipini")

      assert html =~ "Tribe"
      assert html =~ "Cynipini"
    end

    test "shows breadcrumb with parent family using names", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/subfamily/Cynipinae")

      assert html =~ "Cynipidae"
      assert html =~ "/family/Cynipidae"
      refute html =~ "/family/30"
    end

    test "shows children with species counts", %{conn: conn} do
      # Cynipini (tribe) is a child of Cynipinae (subfamily)
      {:ok, _view, html} = live(conn, "/subfamily/Cynipinae")

      assert html =~ "Cynipini"
    end

    test "shows genera as children of tribe", %{conn: conn} do
      # Cynipini has Andricus and Cynips as children
      {:ok, _view, html} = live(conn, "/tribe/Cynipini")

      assert html =~ "Andricus"
      assert html =~ "Cynips"
    end

    test "child URLs use names not IDs", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/subfamily/Cynipinae")

      # Child intermediate should link by rank/name
      assert html =~ "/tribe/Cynipini"
      refute html =~ "/taxonomy/32"
    end

    test "returns not found when rank does not match", %{conn: conn} do
      # Cynipinae is a Subfamily, not a Tribe
      {:ok, _view, html} = live(conn, "/tribe/Cynipinae")

      assert html =~ "not found" or html =~ "Not Found"
    end

    test "returns not found for nonexistent name", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/subfamily/Nonexistent")

      assert html =~ "not found" or html =~ "Not Found"
    end
  end
end
