defmodule GallformersWeb.Live.ContinentScope do
  @moduledoc """
  LiveView on_mount hook that reads the user's continent preference from
  connect params (delivered via localStorage → LiveSocket params) and assigns
  `continent_code` and `continent_name` to the socket.

  During static render (before WebSocket connects), `get_connect_params/1`
  returns nil, so assigns will be nil initially and set once the socket connects.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [get_connect_params: 1]

  @continent_names %{
    "XF" => "Africa",
    "XA" => "Asia",
    "XB" => "Caribbean",
    "XC" => "Central America",
    "XE" => "Europe",
    "XN" => "North America",
    "XO" => "Oceania",
    "XS" => "South America"
  }

  @valid_continent_codes Map.keys(@continent_names)

  @doc "Returns the continent code → name map."
  def continent_names, do: @continent_names

  @doc "Returns continents as a sorted list of `{code, name}` tuples for use in dropdowns."
  def continents_list do
    @continent_names |> Enum.sort_by(fn {_code, name} -> name end)
  end

  def on_mount(:default, _params, _session, socket) do
    continent_code =
      case get_connect_params(socket) do
        nil -> nil
        %{"continent" => code} when code in @valid_continent_codes -> code
        _ -> nil
      end

    continent_name =
      if continent_code, do: Map.get(@continent_names, continent_code), else: nil

    {:cont,
     assign(socket,
       continent_code: continent_code,
       continent_name: continent_name
     )}
  end
end
