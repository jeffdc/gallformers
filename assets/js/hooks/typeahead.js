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
    // Only return selectable items — skip group headers (role="presentation")
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

export default Typeahead
