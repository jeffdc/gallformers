defmodule GallformersWeb.FamilyLiveTest do
  @moduledoc """
  Tests for the public family browse page with table layout.
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  describe "FamilyLive with name-based URLs" do
    test "renders family page with table of children", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/family/Cynipidae")

      assert html =~ "Family:"
      assert html =~ "Cynipidae"
      # Direct child intermediate should appear in table
      assert html =~ "Cynipinae"
    end

    test "shows children with species counts", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/family/Cynipidae")

      # Table should have species count column
      assert html =~ "Species"
      assert html =~ "Children"
    end

    test "child URLs use names not IDs", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/family/Cynipidae")

      # Intermediate URLs should use rank-based paths with names
      assert html =~ "/subfamily/Cynipinae"
      refute html =~ "/taxonomy/31"
    end

    test "returns error for nonexistent family name", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/family/Nonexistent")

      assert html =~ "not found" or html =~ "Not Found"
    end
  end
end
