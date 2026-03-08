// CopyToClipboard hook for copying text to clipboard
// Set data-copy-url to make it prepend window.location.origin (for path-only values)
const CopyToClipboard = {
  mounted() {
    this.el.addEventListener("click", () => {
      let text = this.el.dataset.copyText
      if (text) {
        if (this.el.dataset.copyUrl !== undefined) {
          text = window.location.origin + text
        }
        navigator.clipboard.writeText(text).then(() => {
          this.pushEvent("clipboard_copy_success", {})
        }).catch(() => {
          this.pushEvent("clipboard_copy_error", {})
        })
      }
    })
  }
}

export default CopyToClipboard
