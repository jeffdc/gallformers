defmodule GallformersWeb.LegacyAdminHTML do
  @moduledoc """
  The page shown in place of a disabled old-domain admin screen
  (`GallformersWeb.Plugs.RequireLegacyAdmin`, matter `a856`).
  """
  use GallformersWeb, :html

  embed_templates "legacy_admin_html/*"
end
