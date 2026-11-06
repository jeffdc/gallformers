defmodule GallformersWeb.RankPageComponentsTest do
  @moduledoc """
  The rank pages' Galls list (`rank_galls`): its admin edit links.
  """
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Phoenix.Component, only: [sigil_H: 2]
  import GallformersWeb.RankPageComponents

  alias GallformersWeb.RankGalls

  defp list(view) do
    [
      %{
        id: 7,
        name: "Andricus fixturi",
        common_name: nil,
        count: 2,
        undescribed: false,
        image_url: nil,
        traits: %{},
        host_genera: []
      }
    ]
    |> RankGalls.new()
    |> RankGalls.view(view)
    |> RankGalls.compute("", %{field: :name, dir: :asc})
  end

  defp edit_links(html),
    do:
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("a[href='/admin/galls/7#range-exclusions']")
      |> Enum.count()

  test "with edit_path, each Gall has an edit link, in photos and in the table" do
    for view <- ["photos", "table"] do
      assigns = %{list: list(view)}

      html =
        rendered_to_string(~H"""
        <.rank_galls
          id="galls"
          list={@list}
          sort={%{field: :name, dir: :asc}}
          narrowed={false}
          edit_path={&"/admin/galls/#{&1.id}#range-exclusions"}
        />
        """)

      assert edit_links(html) == 1, "no edit link in #{view}"
    end
  end

  test "without edit_path (a visitor), no edit links" do
    for view <- ["photos", "table"] do
      assigns = %{list: list(view)}

      html =
        rendered_to_string(~H"""
        <.rank_galls id="galls" list={@list} sort={%{field: :name, dir: :asc}} narrowed={false} />
        """)

      assert edit_links(html) == 0
    end
  end

  test "the Photos/Table switch shows only when the list offers both" do
    one = %{
      id: 7,
      name: "Andricus fixturi",
      common_name: nil,
      count: 2,
      undescribed: false,
      image_url: nil,
      traits: %{},
      host_genera: []
    }

    for {views, switch?} <- [{[:photos, :table], true}, {[:photos], false}] do
      assigns = %{
        list:
          [one]
          |> RankGalls.new(views: views)
          |> RankGalls.compute("", %{field: :name, dir: :asc})
      }

      html =
        rendered_to_string(~H"""
        <.rank_galls id="galls" list={@list} sort={%{field: :name, dir: :asc}} narrowed={false} />
        """)

      switch_count =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("[phx-click=galls_view]")
        |> Enum.count()

      assert switch_count == if(switch?, do: 2, else: 0)
    end
  end
end
