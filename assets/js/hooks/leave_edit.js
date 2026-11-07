// LeaveEdit hook: on the curator's tray (GallformersWeb.TrayLive, a
// LiveView of its own in the root layout). When the tray has applied
// changes it pushes "leave-edit"; the page in Edit mode (`?edit`) is then
// patched to its URL without `edit` (and `photos`, which only Edit mode
// opens), so its own LiveView leaves Edit mode. A page not in Edit mode is
// left alone.
const LeaveEdit = {
  mounted() {
    this.handleEvent("leave-edit", () => {
      const href = withoutEdit(window.location.href)
      if (href) this.js().patch(href)
    })
  }
}

// The path, query and fragment of `href` without the Edit mode parameters,
// or null when it has none.
export function withoutEdit(href) {
  const url = new URL(href)
  if (!url.searchParams.has("edit")) return null

  url.searchParams.delete("edit")
  url.searchParams.delete("photos")
  const query = url.searchParams.toString()

  return url.pathname + (query ? `?${query}` : "") + url.hash
}

export default LeaveEdit
