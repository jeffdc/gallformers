// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

// Hooks
import AdminNav from "./hooks/admin_nav"
import ArticleImageUpload from "./hooks/article_image_upload"
import AutoDismiss from "./hooks/auto_dismiss"
import ContentImageUpload from "./hooks/content_image_upload"
import CopyToClipboard from "./hooks/copy_to_clipboard"
import DailyChart from "./hooks/daily_chart"
import ImageGallery from "./hooks/image_gallery"
import ImageUpload from "./hooks/image_upload"
import IndeterminateCheckbox from "./hooks/indeterminate_checkbox"
import InputEvent from "./hooks/input_event"
import RangeMap from "./hooks/range_map"
import RegionPrompt from "./hooks/region_prompt"
import RegionScope from "./hooks/region_scope"
import ScrollToCouplet from "./hooks/scroll_to_couplet"
import SortableImages from "./hooks/sortable_images"
import Tabs from "./hooks/tabs"
import Typeahead from "./hooks/typeahead"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: () => ({_csrf_token: csrfToken, continent: localStorage.getItem("gf_continent")}),
  hooks: {AdminNav, ArticleImageUpload, AutoDismiss, ContentImageUpload, CopyToClipboard, DailyChart, ImageGallery, ImageUpload, IndeterminateCheckbox, InputEvent, RangeMap, RegionPrompt, RegionScope, ScrollToCouplet, SortableImages, Tabs, Typeahead},
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

// Reconnect immediately when a backgrounded tab regains focus.
// Without this, a tab idle for 5-10 min has a dead socket and all
// phx-* bindings are inert until the next heartbeat cycle (~30s).
document.addEventListener("visibilitychange", () => {
  if (!document.hidden) liveSocket.connect()
})

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
