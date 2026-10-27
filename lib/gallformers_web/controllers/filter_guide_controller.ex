defmodule GallformersWeb.FilterGuideController do
  use GallformersWeb, :controller

  alias Gallformers.Catalog

  # The Traits the guide explains, as its sections name them.
  @traits %{
    "alignment" => :alignment,
    "cells" => :cells,
    "detachable" => :detachable,
    "form" => :form,
    "plant_part" => :plant_part,
    "season" => :season,
    "shape" => :shape,
    "texture" => :texture,
    "walls" => :walls
  }

  def show(conn, _params) do
    # Each Trait's values with their definitions, from the contract
    # vocabulary; a value without a definition ("unknown") is no filter term.
    empty = Map.new(Map.values(@traits), &{&1, []})

    filter_fields =
      Catalog.list_trait_values()
      |> Enum.filter(&(Map.has_key?(@traits, &1.trait) and &1.definition != nil))
      |> Enum.group_by(
        &Map.fetch!(@traits, &1.trait),
        &%{field: &1.value, description: &1.definition}
      )
      |> then(&Map.merge(empty, &1))

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
