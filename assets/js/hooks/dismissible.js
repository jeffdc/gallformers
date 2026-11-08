// Dismissible hook: something a reader can dismiss once, remembered by this
// browser (localStorage, under the element's data-key). The server renders
// it hidden, so it never flashes before the hook has checked; the hook
// shows it unless it was dismissed. Its [data-dismiss] button dismisses it.
// Storage that refuses (private browsing) only means it is shown again
// next time.
const DISMISSED = "dismissed"

function read(key) {
  try { return localStorage.getItem(key) } catch (_e) { return null }
}

function write(key) {
  try { localStorage.setItem(key, DISMISSED) } catch (_e) { /* not remembered */ }
}

const Dismissible = {
  mounted() {
    this.dismissed = read(this.el.dataset.key) === DISMISSED
    this.el.addEventListener("click", (e) => {
      if (e.target.closest("[data-dismiss]")) {
        this.dismissed = true
        write(this.el.dataset.key)
        this.apply()
      }
    })
    this.apply()
  },
  // A re-render puts the server's hidden back.
  updated() { this.apply() },
  apply() { this.el.hidden = this.dismissed }
}

export default Dismissible
