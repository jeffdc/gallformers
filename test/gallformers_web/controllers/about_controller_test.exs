defmodule GallformersWeb.AboutControllerTest do
  @moduledoc """
  Controller tests for the public About page.
  """
  use GallformersWeb.ConnCase, async: false

  alias Gallformers.Accounts

  # Helper to generate unique auth0 IDs
  defp unique_auth0_id, do: "auth0|test-#{System.unique_integer([:positive])}"

  describe "About page - public access" do
    test "page loads successfully without authentication", %{conn: conn} do
      conn = get(conn, ~p"/about")

      assert html_response(conn, 200) =~ "About Us"
    end

    test "sets page metadata", %{conn: conn} do
      conn = get(conn, ~p"/about")

      assert conn.assigns.page_title == "About"
      assert conn.assigns.page_url == "/about"
    end

    test "displays co-founder information", %{conn: conn} do
      conn = get(conn, ~p"/about")
      html = html_response(conn, 200)

      assert html =~ "Adam Kranz"
      assert html =~ "Jeff Clark"
    end

    test "displays contact information", %{conn: conn} do
      conn = get(conn, ~p"/about")

      assert html_response(conn, 200) =~ "gallformers@gmail.com"
    end

    test "displays site statistics", %{conn: conn} do
      conn = get(conn, ~p"/about")
      html = html_response(conn, 200)

      assert html =~ "Stats" or html =~ "galls" or html =~ "hosts"
    end

    test "displays administrators section heading", %{conn: conn} do
      conn = get(conn, ~p"/about")

      assert html_response(conn, 200) =~ "Administrators"
    end
  end

  describe "About page - administrators list" do
    setup do
      {:ok, user_opted_in_with_links} =
        Accounts.create_user(%{
          auth0_id: unique_auth0_id(),
          display_name: "Admin With Links",
          nickname: "adminlinks",
          inaturalist_url: "https://www.inaturalist.org/people/adminlinks",
          social_url: "https://twitter.com/adminlinks",
          personal_url: "https://adminlinks.com",
          show_on_about: true
        })

      {:ok, user_opted_in_no_links} =
        Accounts.create_user(%{
          auth0_id: unique_auth0_id(),
          display_name: "Admin No Links",
          nickname: "adminnolinks",
          show_on_about: true
        })

      {:ok, user_opted_out} =
        Accounts.create_user(%{
          auth0_id: unique_auth0_id(),
          display_name: "Hidden Admin",
          nickname: "hiddenadmin",
          show_on_about: false
        })

      {:ok,
       user_opted_in_with_links: user_opted_in_with_links,
       user_opted_in_no_links: user_opted_in_no_links,
       user_opted_out: user_opted_out}
    end

    test "displays opted-in users", %{
      conn: conn,
      user_opted_in_with_links: user_with_links,
      user_opted_in_no_links: user_no_links
    } do
      conn = get(conn, ~p"/about")
      html = html_response(conn, 200)

      assert html =~ user_with_links.display_name
      assert html =~ user_no_links.display_name
    end

    test "does not show users with show_on_about=false", %{conn: conn, user_opted_out: user} do
      conn = get(conn, ~p"/about")

      refute html_response(conn, 200) =~ user.display_name
    end

    test "shows link to user profile when nickname is set", %{
      conn: conn,
      user_opted_in_with_links: user
    } do
      conn = get(conn, ~p"/about")

      assert html_response(conn, 200) =~ "/user/#{user.nickname}"
    end
  end

  describe "About page - nickname fallback" do
    setup do
      {:ok, user_with_nickname_only} =
        Accounts.create_user(%{
          auth0_id: unique_auth0_id(),
          display_name: nil,
          nickname: "OnlyNickname",
          show_on_about: true
        })

      {:ok, user_with_nickname_only: user_with_nickname_only}
    end

    test "shows nickname when display_name is nil", %{
      conn: conn,
      user_with_nickname_only: user
    } do
      conn = get(conn, ~p"/about")

      assert html_response(conn, 200) =~ user.nickname
    end
  end

  describe "About page - content sections" do
    test "displays GitHub link", %{conn: conn} do
      conn = get(conn, ~p"/about")
      html = html_response(conn, 200)

      assert html =~ "github.com" or html =~ "GitHub"
    end

    test "displays citation information", %{conn: conn} do
      conn = get(conn, ~p"/about")
      html = html_response(conn, 200)

      assert html =~ "Gallformers Contributors"
    end

    test "displays NSF funding information", %{conn: conn} do
      conn = get(conn, ~p"/about")
      html = html_response(conn, 200)

      assert html =~ "National Science Foundation"
    end

    test "displays version information", %{conn: conn} do
      conn = get(conn, ~p"/about")
      html = html_response(conn, 200)

      assert html =~ "App:"
      assert html =~ "API:"
    end

    test "includes easter egg markup", %{conn: conn} do
      conn = get(conn, ~p"/about")
      html = html_response(conn, 200)

      assert html =~ "Dare You Click?"
      assert html =~ "easter-egg"
    end
  end
end
