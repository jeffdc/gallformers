// PhotoViewer hook (the photo_viewer component, design system matter bc0d).
//
// The server renders every photo's slide, full-size figure and details; this
// shows the current one. Moves wrap: arrows, thumbnails, arrow keys (while
// focus is in the viewer, its full-size view included) and a horizontal
// swipe. Each move pushes `gallery_index_changed` {index}. The full-size view
// loads a photo (`data-src`) when it is first shown. Escape closes an open
// dialog wherever focus is (some browsers leave focus outside a modal after
// a click on its photo, and then their own Escape does nothing); closing
// (Close, Escape) returns focus to what opened it.

const SWIPE = 40 // px

const PhotoViewer = {
  mounted() {
    this.index = 0
    this.count = parseInt(this.el.dataset.count || "0", 10)
    this.opener = null

    this.onClick = (e) => {
      const target = e.target.closest("[data-prev], [data-next], [data-go], [data-open], [data-open-details], [data-close]")
      if (!target || !this.el.contains(target)) return
      if (target.matches("[data-prev]")) this.go(this.index - 1)
      else if (target.matches("[data-next]")) this.go(this.index + 1)
      else if (target.matches("[data-go]")) this.go(parseInt(target.dataset.go, 10))
      else if (target.matches("[data-open]")) this.open("[data-lightbox]", target)
      else if (target.matches("[data-open-details]")) this.open("[data-details]", target)
      else if (target.matches("[data-close]")) target.closest("dialog")?.close()
    }

    this.onKey = (e) => {
      if (e.key === "ArrowLeft") this.go(this.index - 1)
      else if (e.key === "ArrowRight") this.go(this.index + 1)
    }

    this.onPointerDown = (e) => {
      if (e.target.closest("[data-stage]")) this.swipeFrom = e.clientX
    }

    this.onPointerUp = (e) => {
      if (this.swipeFrom == null) return
      const dx = e.clientX - this.swipeFrom
      this.swipeFrom = null
      if (Math.abs(dx) >= SWIPE) {
        this.swiped = true
        this.go(dx < 0 ? this.index + 1 : this.index - 1)
      }
    }

    // A swipe ends with a click on the photo; it must not also open it.
    this.onClickCapture = (e) => {
      if (this.swiped) {
        this.swiped = false
        e.stopPropagation()
        e.preventDefault()
      }
    }

    this.onEscape = (e) => {
      if (e.key !== "Escape") return
      const open = this.el.querySelector("dialog[open]")
      if (open) {
        e.preventDefault()
        open.close()
      }
    }

    this.onClose = () => {
      if (this.opener && document.contains(this.opener)) this.opener.focus()
      this.opener = null
    }

    this.el.addEventListener("click", this.onClickCapture, true)
    this.el.addEventListener("click", this.onClick)
    this.el.addEventListener("keydown", this.onKey)
    this.el.addEventListener("pointerdown", this.onPointerDown)
    this.el.addEventListener("pointerup", this.onPointerUp)
    window.addEventListener("keydown", this.onEscape)
    this.el.querySelectorAll("dialog").forEach(d => d.addEventListener("close", this.onClose))
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClickCapture, true)
    this.el.removeEventListener("click", this.onClick)
    this.el.removeEventListener("keydown", this.onKey)
    this.el.removeEventListener("pointerdown", this.onPointerDown)
    this.el.removeEventListener("pointerup", this.onPointerUp)
    window.removeEventListener("keydown", this.onEscape)
  },

  go(index) {
    if (this.count < 2) return
    this.index = (index + this.count) % this.count
    const i = String(this.index)

    for (const attr of ["data-slide", "data-full", "data-info"]) {
      this.el.querySelectorAll(`[${attr}]`).forEach(e => { e.hidden = e.getAttribute(attr) !== i })
    }

    this.el.querySelectorAll("[data-go]").forEach(b => {
      b.setAttribute("aria-current", String(b.dataset.go === i))
      if (b.dataset.go === i) b.scrollIntoView?.({ block: "nearest", inline: "nearest" })
    })

    this.el.querySelectorAll("[data-counter]").forEach(c => { c.textContent = `${this.index + 1} / ${this.count}` })

    if (this.el.querySelector("[data-lightbox]")?.open) this.loadFull()
    this.pushEvent("gallery_index_changed", { index: this.index })
  },

  // The full-size photo is loaded only when it is shown.
  loadFull() {
    const img = this.el.querySelector(`[data-full="${this.index}"] img[data-src]`)
    if (img && !img.getAttribute("src")) img.setAttribute("src", img.dataset.src)
  },

  open(selector, opener) {
    const dialog = this.el.querySelector(selector)
    if (!dialog) return
    this.opener = opener
    dialog.showModal()
    if (selector === "[data-lightbox]") this.loadFull()
  }
}

export default PhotoViewer
