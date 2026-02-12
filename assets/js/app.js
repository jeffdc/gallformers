// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

// Import external hooks
import RangeMap from "./hooks/range_map"
import ImageUpload from "./hooks/image_upload"
import SortableImages from "./hooks/sortable_images"
import ArticleImageUpload from "./hooks/article_image_upload"
import DailyChart from "./hooks/daily_chart"

// Custom hooks for UI components
const Tabs = {
  mounted() {
    const defaultTab = this.el.dataset.defaultTab
    this.activateTab(defaultTab)

    // Handle tab clicks
    this.el.querySelectorAll("[data-tab-id]").forEach(button => {
      button.addEventListener("click", (e) => {
        this.activateTab(e.currentTarget.dataset.tabId)
      })
    })

    // Handle keyboard navigation
    this.el.querySelectorAll("[data-tab-id]").forEach(button => {
      button.addEventListener("keydown", (e) => {
        const tabs = Array.from(this.el.querySelectorAll("[data-tab-id]"))
        const currentIndex = tabs.indexOf(e.currentTarget)
        let newIndex = currentIndex

        if (e.key === "ArrowLeft") {
          newIndex = currentIndex > 0 ? currentIndex - 1 : tabs.length - 1
        } else if (e.key === "ArrowRight") {
          newIndex = currentIndex < tabs.length - 1 ? currentIndex + 1 : 0
        } else if (e.key === "Home") {
          newIndex = 0
        } else if (e.key === "End") {
          newIndex = tabs.length - 1
        } else {
          return
        }

        e.preventDefault()
        const newTab = tabs[newIndex]
        newTab.focus()
        this.activateTab(newTab.dataset.tabId)
      })
    })
  },
  activateTab(tabId) {
    // Update tab buttons
    this.el.querySelectorAll("[data-tab-id]").forEach(button => {
      if (button.dataset.tabId === tabId) {
        button.setAttribute("data-active", "")
        button.setAttribute("aria-selected", "true")
      } else {
        button.removeAttribute("data-active")
        button.setAttribute("aria-selected", "false")
      }
    })

    // Update tab panels
    this.el.querySelectorAll("[data-tab-panel]").forEach(panel => {
      if (panel.dataset.tabPanel === tabId) {
        panel.setAttribute("data-active", "")
      } else {
        panel.removeAttribute("data-active")
      }
    })
  }
}

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

// ImageGallery hook for keyboard navigation, lightbox, and attribution updates
const ImageGallery = {
  mounted() {
    this.currentIndex = 0
    this.images = JSON.parse(this.el.dataset.images || "[]")
    this.lightboxOpen = false
    this.infoOpen = false

    // Keyboard navigation
    this.keyHandler = (e) => {
      if (e.key === "ArrowLeft") {
        this.prevImage()
      } else if (e.key === "ArrowRight") {
        this.nextImage()
      } else if (e.key === "Escape") {
        if (this.lightboxOpen) this.closeLightbox()
        if (this.infoOpen) this.closeInfo()
      }
    }

    this.el.addEventListener("keydown", this.keyHandler)

    // Navigation button handlers
    this.el.querySelectorAll("[data-prev]").forEach(btn => {
      btn.addEventListener("click", () => this.prevImage())
    })
    this.el.querySelectorAll("[data-next]").forEach(btn => {
      btn.addEventListener("click", () => this.nextImage())
    })

    // Lightbox handlers
    this.el.querySelectorAll("[data-open-lightbox]").forEach(btn => {
      btn.addEventListener("click", () => this.openLightbox())
    })
    this.el.querySelectorAll("[data-close-lightbox]").forEach(btn => {
      btn.addEventListener("click", () => this.closeLightbox())
    })

    // Info dialog handlers
    this.el.querySelectorAll("[data-open-info]").forEach(btn => {
      btn.addEventListener("click", () => this.openInfo())
    })
    this.el.querySelectorAll("[data-close-info]").forEach(btn => {
      btn.addEventListener("click", () => this.closeInfo())
    })
  },
  destroyed() {
    this.el.removeEventListener("keydown", this.keyHandler)
  },
  prevImage() {
    this.currentIndex = this.currentIndex > 0 ? this.currentIndex - 1 : this.images.length - 1
    this.updateDisplay()
  },
  nextImage() {
    this.currentIndex = this.currentIndex < this.images.length - 1 ? this.currentIndex + 1 : 0
    this.updateDisplay()
  },
  updateDisplay() {
    const img = this.images[this.currentIndex]
    if (!img) return

    // Update main image
    const mainImg = this.el.querySelector("[data-main-image]")
    if (mainImg) {
      mainImg.src = img.src
      mainImg.alt = img.alt || ""
    }

    // Update lightbox image
    const lightboxImg = this.el.querySelector("[data-lightbox-image]")
    if (lightboxImg) {
      lightboxImg.src = img.src
      lightboxImg.alt = img.alt || ""
    }

    // Update counter
    this.el.querySelectorAll("[data-counter]").forEach(counter => {
      counter.textContent = `${this.currentIndex + 1} / ${this.images.length}`
    })

    // Update caption
    const caption = this.el.querySelector("[data-caption]")
    if (caption) {
      caption.textContent = img.caption || ""
      caption.classList.toggle("hidden", !img.caption)
    }

    // Update attribution elements
    const sourceLink = this.el.querySelector("[data-source-link]")
    if (sourceLink) {
      sourceLink.href = img.sourcelink || "#"
      sourceLink.parentElement.classList.toggle("hidden", !img.sourcelink)
    }

    const creator = this.el.querySelector("[data-creator]")
    if (creator) creator.textContent = img.creator || ""

    const license = this.el.querySelector("[data-license]")
    if (license) license.textContent = img.license || ""

    const licenseLink = this.el.querySelector("[data-license-link]")
    if (licenseLink) licenseLink.href = img.licenselink || "#"

    const licenseTooltip = this.el.querySelector("[data-license-tooltip]")
    if (licenseTooltip) licenseTooltip.textContent = img.license || "No license"

    // Update info dialog elements
    const infoImage = this.el.querySelector("[data-info-image]")
    if (infoImage) infoImage.src = img.src

    const infoSource = this.el.querySelector("[data-info-source]")
    if (infoSource) {
      infoSource.href = img.sourcelink || "#"
      infoSource.textContent = img.source_title || img.sourcelink || ""
    }

    const infoLicense = this.el.querySelector("[data-info-license]")
    if (infoLicense) {
      infoLicense.href = img.licenselink || "#"
      infoLicense.textContent = img.license || ""
    }

    const infoAttribution = this.el.querySelector("[data-info-attribution]")
    if (infoAttribution) infoAttribution.textContent = img.attribution || ""

    const infoCreator = this.el.querySelector("[data-info-creator]")
    if (infoCreator) infoCreator.textContent = img.creator || ""

    const infoUploader = this.el.querySelector("[data-info-uploader]")
    if (infoUploader) infoUploader.textContent = img.uploader || ""

    const infoLastchangedby = this.el.querySelector("[data-info-lastchangedby]")
    if (infoLastchangedby) infoLastchangedby.textContent = img.lastchangedby || ""

    const infoCaption = this.el.querySelector("[data-info-caption]")
    if (infoCaption) infoCaption.textContent = img.caption || ""

    // Update lightbox attribution elements
    const lightboxSourceLink = this.el.querySelector("[data-lightbox-source-link]")
    if (lightboxSourceLink) lightboxSourceLink.href = img.sourcelink || "#"

    const lightboxCreator = this.el.querySelector("[data-lightbox-creator]")
    if (lightboxCreator) lightboxCreator.textContent = img.creator || ""

    const lightboxLicense = this.el.querySelector("[data-lightbox-license]")
    if (lightboxLicense) lightboxLicense.textContent = img.license || ""

    const lightboxLicenseLink = this.el.querySelector("[data-lightbox-license-link]")
    if (lightboxLicenseLink) lightboxLicenseLink.href = img.licenselink || "#"

    // Push event to server if needed
    this.pushEvent("gallery_index_changed", {index: this.currentIndex})
  },
  openLightbox() {
    this.lightboxOpen = true
    const lightbox = this.el.querySelector("[data-lightbox]")
    if (lightbox) lightbox.showModal()
  },
  closeLightbox() {
    this.lightboxOpen = false
    const lightbox = this.el.querySelector("[data-lightbox]")
    if (lightbox) lightbox.close()
  },
  openInfo() {
    this.infoOpen = true
    const info = this.el.querySelector("[data-info-dialog]")
    if (info) info.showModal()
  },
  closeInfo() {
    this.infoOpen = false
    const info = this.el.querySelector("[data-info-dialog]")
    if (info) info.close()
  }
}

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

// Typeahead hook for keyboard navigation in search dropdowns
const Typeahead = {
  mounted() {
    this.highlightedIndex = -1
    this.pendingFocus = false
    this.inputHandler = (e) => this.handleInputKeydown(e)
    this.selectedHandler = (e) => this.handleSelectedKeydown(e)

    this.attachListeners()
  },

  updated() {
    // Re-query elements and re-attach listeners after DOM updates
    this.attachListeners()

    // Focus input if we just cleared and are waiting for focus
    if (this.pendingFocus && this.input) {
      this.pendingFocus = false
      this.input.focus()
    }

    // Reset highlight when results change
    const results = this.getResults()
    if (results.length === 0) {
      this.highlightedIndex = -1
    } else if (this.highlightedIndex >= results.length) {
      this.highlightedIndex = results.length - 1
    }
    this.updateHighlight()
  },

  attachListeners() {
    // Re-query elements
    this.input = this.el.querySelector("[data-typeahead-input]")
    this.resultsContainer = this.el.querySelector("[data-typeahead-results]")
    this.selectedContainer = this.el.querySelector("[data-typeahead-selected]")

    // Attach input listener if not already attached
    if (this.input && !this.input._typeaheadListener) {
      this.input._typeaheadListener = true
      this.input.addEventListener("keydown", this.inputHandler)
      // Listen for paste/autofill via the input event (phx-keyup misses these)
      this.input.addEventListener("input", () => {
        const searchEvent = this.el.dataset.searchEvent
        if (searchEvent) {
          this.pushTargetedEvent(searchEvent, {value: this.input.value})
        }
      })
    }

    // Attach selected container listener if not already attached
    if (this.selectedContainer && !this.selectedContainer._typeaheadListener) {
      this.selectedContainer._typeaheadListener = true
      this.selectedContainer.addEventListener("keydown", this.selectedHandler)
    }
  },

  // Push event to the correct target (LiveComponent or LiveView)
  pushTargetedEvent(event, payload) {
    const target = this.el.dataset.target
    if (target) {
      this.pushEventTo(`[data-phx-component="${target}"]`, event, payload)
    } else {
      this.pushEvent(event, payload)
    }
  },

  getResults() {
    if (!this.resultsContainer) return []
    return Array.from(this.resultsContainer.querySelectorAll("[data-typeahead-option]"))
  },

  handleInputKeydown(e) {
    const results = this.getResults()

    switch (e.key) {
      case "ArrowDown":
        e.preventDefault()
        if (results.length > 0) {
          this.highlightedIndex = Math.min(this.highlightedIndex + 1, results.length - 1)
          this.updateHighlight()
          this.scrollToHighlighted()
        }
        break

      case "ArrowUp":
        e.preventDefault()
        if (results.length > 0) {
          this.highlightedIndex = Math.max(this.highlightedIndex - 1, 0)
          this.updateHighlight()
          this.scrollToHighlighted()
        }
        break

      case "Enter":
        e.preventDefault()
        if (this.highlightedIndex >= 0 && results[this.highlightedIndex]) {
          results[this.highlightedIndex].click()
          this.highlightedIndex = -1
        } else if (this.input && this.input.value.trim() !== "") {
          // No result highlighted but there's text - trigger close to add as new item
          const closeEvent = this.el.dataset.closeEvent
          if (closeEvent) {
            this.pushTargetedEvent(closeEvent, {})
            this.input.value = "" // Clear input immediately (LiveView won't update focused inputs)
          }
        }
        break

      case "Escape":
        e.preventDefault()
        this.highlightedIndex = -1
        this.updateHighlight()
        break
    }
  },

  handleSelectedKeydown(e) {
    const clearEvent = this.el.dataset.clearEvent
    const searchEvent = this.el.dataset.searchEvent

    if (e.key === "Escape" || e.key === "Backspace" || e.key === "Delete") {
      e.preventDefault()
      if (clearEvent) {
        // Set flag to focus input after DOM updates
        this.pendingFocus = true
        this.pushTargetedEvent(clearEvent, {})
      }
    } else if (e.key.length === 1) {
      // Printable character - clear and start searching
      e.preventDefault()
      if (clearEvent && searchEvent) {
        // Set flag to focus input after DOM updates
        this.pendingFocus = true
        this.pushTargetedEvent(clearEvent, {})
        this.pushTargetedEvent(searchEvent, {value: e.key})
      }
    }
  },

  updateHighlight() {
    const results = this.getResults()
    results.forEach((item, index) => {
      if (index === this.highlightedIndex) {
        item.setAttribute("data-highlighted", "")
        item.setAttribute("aria-selected", "true")
      } else {
        item.removeAttribute("data-highlighted")
        item.setAttribute("aria-selected", "false")
      }
    })
  },

  scrollToHighlighted() {
    const results = this.getResults()
    if (this.highlightedIndex >= 0 && results[this.highlightedIndex]) {
      results[this.highlightedIndex].scrollIntoView({ block: "nearest" })
    }
  }
}

// Generic hook that pushes an event on the DOM "input" event (catches paste, autofill, etc.)
// Usage: <input phx-hook="InputEvent" data-event="update_rename_value" />
// Optional: data-target="CID" to push to a specific LiveComponent
const InputEvent = {
  mounted() {
    this.el.addEventListener("input", () => {
      const event = this.el.dataset.event
      if (event) {
        const target = this.el.dataset.target
        if (target) {
          this.pushEventTo(`[data-phx-component="${target}"]`, event, {value: this.el.value})
        } else {
          this.pushEvent(event, {value: this.el.value})
        }
      }
    })
  }
}

// ScrollToCouplet hook for dichotomous key navigation
const ScrollToCouplet = {
  mounted() {
    this.handleEvent("scroll_to_couplet", ({id}) => {
      requestAnimationFrame(() => {
        const el = document.getElementById(id)
        if (el) {
          // Account for sticky header (~78px) and path tracker (~40px)
          const offset = 130
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

// AdminNav hook - highlights the active nav link based on the current URL path
const AdminNav = {
  mounted() { this.highlight() },
  updated() { this.highlight() },
  highlight() {
    const path = window.location.pathname
    this.el.querySelectorAll("[data-nav-href]").forEach(link => {
      const href = link.dataset.navHref
      const active = href === "/admin" ? path === "/admin" : path.startsWith(href)
      link.classList.toggle("opacity-50", !active)
      link.classList.toggle("underline", active)
      link.classList.toggle("underline-offset-4", active)
      link.classList.toggle("decoration-2", active)
    })
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {Tabs, ImageGallery, RangeMap, ImageUpload, SortableImages, AutoDismiss, Typeahead, ArticleImageUpload, CopyToClipboard, DailyChart, InputEvent, ScrollToCouplet, AdminNav},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Focus input handler for typeahead accessibility
window.addEventListener("phx:focus_input", (e) => {
  const { id } = e.detail
  // Use requestAnimationFrame to ensure DOM has updated after LiveView patch
  requestAnimationFrame(() => {
    const input = document.getElementById(id)
    if (input) {
      input.focus()
      // Move cursor to end of input value
      const len = input.value.length
      input.setSelectionRange(len, len)
    }
  })
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

