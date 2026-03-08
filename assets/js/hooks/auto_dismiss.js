// AutoDismiss hook for flash messages
// Uses pushEvent instead of click() to avoid triggering phx-click-away on modals
const AutoDismiss = {
  mounted() {
    const delay = parseInt(this.el.dataset.dismissAfter) || 5000
    this.timer = setTimeout(() => {
      // Get the flash kind from the data attribute
      const kind = this.el.dataset.flashKind
      if (kind) {
        // Push the clear-flash event directly instead of using click()
        // This avoids triggering phx-click-away on any open modals
        this.pushEvent("lv:clear-flash", {key: kind})
        // Hide the element client-side (server will also remove it on next render)
        this.el.classList.add("hidden")
      } else {
        // Fallback to click if kind not available (shouldn't happen)
        this.el.click()
      }
    }, delay)
  },
  destroyed() {
    if (this.timer) clearTimeout(this.timer)
  }
}

export default AutoDismiss
