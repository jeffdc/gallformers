defmodule Gallformers.Wcvp.LookupBehaviour do
  @moduledoc """
  Behaviour for WCVP lookup functions.

  Allows swapping the real Postgres-backed implementation for a test stub.
  The bulk lookups `get_names/1` and `find_names/1` (plant names'
  authorship, `Gallformers.Ranges.WcvpAuthorship`) are optional: a lookup
  made for one screen's tests need not give them.
  """

  alias Gallformers.Wcvp.WcvpName

  @callback available?() :: boolean()
  @callback built_at() :: DateTime.t() | nil
  @callback search(String.t(), keyword()) :: [WcvpName.t()]
  @callback search_contains(String.t(), keyword()) :: [WcvpName.t()]
  @callback match_by_name(String.t(), keyword()) :: WcvpName.t() | nil
  @callback get(String.t()) :: WcvpName.t() | nil
  @callback get_accepted_name(String.t()) :: WcvpName.t() | nil
  @callback get_names([String.t()]) :: [WcvpName.t()]
  @callback find_names([String.t()]) :: [WcvpName.t()]

  @optional_callbacks get_names: 1, find_names: 1
end
