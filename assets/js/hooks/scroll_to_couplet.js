// ScrollToCouplet hook for dichotomous key navigation
const ScrollToCouplet = {
  mounted() {
    this.handleEvent("scroll_to_couplet", ({id}) => {
      requestAnimationFrame(() => {
        const el = document.getElementById(id)
        if (el) {
          // Clear whatever sticky chrome sits on top (the site header, the
          // path tracker), measured, plus a little breathing room.
          const chrome = [...document.querySelectorAll("[data-sticky-chrome]")]
            .reduce((sum, bar) => sum + bar.offsetHeight, 0)
          const offset = chrome + 8
          const top = el.getBoundingClientRect().top + window.scrollY - offset
          window.scrollTo({ top, behavior: "smooth" })
        }
      })
    })

    this.handleEvent("copy_to_clipboard", ({text, url_path}) => {
      const origin = window.location.origin
      let finalText = text
      if (url_path) {
        finalText = finalText.replace("{{KEY_URL}}", origin + url_path)
      }
      finalText = finalText.replaceAll("{{KEY_URL_ORIGIN}}", origin)
      navigator.clipboard.writeText(finalText).then(() => {
        this.pushEvent("clipboard_copy_success", {})
      }).catch(() => {
        this.pushEvent("clipboard_copy_error", {})
      })
    })
  }
}

export default ScrollToCouplet
