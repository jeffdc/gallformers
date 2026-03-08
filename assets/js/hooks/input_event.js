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

export default InputEvent
