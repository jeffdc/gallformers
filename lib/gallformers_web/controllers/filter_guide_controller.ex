defmodule GallformersWeb.FilterGuideController do
  use GallformersWeb, :controller

  alias Gallformers.FilterFields

  def show(conn, _params) do
    filter_fields =
      for type <- [:alignment, :cells, :form, :plant_part, :shape, :texture, :walls],
          into: %{} do
        field_name = FilterFields.field_name_for(type)

        items =
          FilterFields.list_all(type)
          |> Enum.map(&%{field: Map.get(&1, field_name), description: &1.description})

        {type, items}
      end

    conn
    |> assign(:page_title, "Filter Guide")
    |> assign(
      :page_description,
      "Guide to the filter terms used in the Gallformers gall identification tool - explanations of alignment, cells, forms, plant part, shape, texture, and walls."
    )
    |> assign(:page_url, "/filterguide")
    |> assign(:filter_fields, filter_fields)
    |> render(:show)
  end
end
