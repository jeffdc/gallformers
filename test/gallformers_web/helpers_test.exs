defmodule GallformersWeb.HelpersTest do
  use ExUnit.Case, async: true

  import GallformersWeb.Helpers, only: [format_number: 1, list_separator: 2, time_ago: 2]

  doctest GallformersWeb.Helpers, only: [format_number: 1, list_separator: 2, time_ago: 2]
end
