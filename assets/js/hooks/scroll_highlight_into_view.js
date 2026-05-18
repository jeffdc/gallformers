// ScrollHighlightIntoView hook
//
// Used by the ingestion-review description workspace's "view in context"
// modal. When the modal mounts, scroll the inner <mark> element into view,
// centered, so the highlighted chunk is immediately visible without forcing
// the curator to hunt for it.
const ScrollHighlightIntoView = {
  mounted() {
    const mark = this.el.querySelector("mark")
    if (mark) {
      mark.scrollIntoView({ block: "center", behavior: "instant" })
    }
  }
}

export default ScrollHighlightIntoView
