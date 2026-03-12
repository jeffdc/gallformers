defmodule GallformersWeb.GenusLiveTest do
  @moduledoc """
  Tests for the public genus browse page with semantic URLs.
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  describe "GenusLive with name-based URLs" do
    test "renders genus page by name", %{conn: conn} do
      # Andricus (id=33) is a genus under Cynipini tribe
      {:ok, _view, html} = live(conn, "/genus/Andricus")

      assert html =~ "Andricus"
    end

    test "shows breadcrumb with family name link", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/genus/Andricus")

      assert html =~ "Cynipidae"
      assert html =~ "/family/Cynipidae"
      refute html =~ "/family/30"
    end

    test "shows breadcrumb with intermediate name links", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/genus/Andricus")

      # Should show intermediate breadcrumbs with rank-typed URLs
      assert html =~ "Cynipinae"
      assert html =~ "/subfamily/Cynipinae"
      refute html =~ "/taxonomy/31"
    end

    test "shows species for the genus", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/genus/Andricus")

      # Andricus crystallinus (id=200) is linked to genus Andricus (id=33)
      assert html =~ "Andricus crystallinus"
    end

    test "returns error for nonexistent genus name", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/genus/Nonexistent")

      assert html =~ "not found" or html =~ "Not Found"
    end
  end
end
