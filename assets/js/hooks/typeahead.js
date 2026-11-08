// Typeahead hook for keyboard navigation in search dropdowns
const Typeahead = {
  mounted() {
    this.highlightedIndex = -1
    this.pendingFocus = false
    // Escape closes the results without changing anything (`closeResults`);
    // they stay closed through page updates until the user types or arrows.
    this.closed = false
    this.inputHandler = (e) => this.handleInputKeydown(e)
    this.selectedHandler = (e) => this.handleSelectedKeydown(e)

    this.attachListeners()
  },

  updated() {
    // Re-query elements and re-attach listeners after DOM updates
    this.attachListeners()
    if (this.closed && this.resultsContainer) this.resultsContainer.hidden = true

    // Focus input if we just cleared and are waiting for focus
    if (this.pendingFocus && this.input) {
      this.pendingFocus = false
      this.input.focus()
    }

    // Clear input when the server-side query was reset (e.g., after selection/clear).
    // LiveView won't update a focused input's value, so we force-sync here.
    const hasServerQuery = this.el.hasAttribute("data-query")
    const serverQuery = this.el.dataset.query || ''
    if (this.input && hasServerQuery && serverQuery === '' && this.input.value !== '') {
      this.input.value = ''
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
        this.openResults()
        const searchEvent = this.el.dataset.searchEvent
        if (searchEvent) {
          const payload = {value: this.input.value}
          if (this.el.dataset.searchType) {
            payload.type = this.el.dataset.searchType
          }
          this.pushTargetedEvent(searchEvent, payload)
        }
      })
    }

    // Attach selected container listener if not already attached
    if (this.selectedContainer && !this.selectedContainer._typeaheadListener) {
      this.selectedContainer._typeaheadListener = true
      this.selectedContainer.addEventListener("keydown", this.selectedHandler)
    }
  },

  // Close the results list, keeping the text and telling the server nothing.
  closeResults() {
    this.closed = true
    if (this.resultsContainer) this.resultsContainer.hidden = true
  },

  openResults() {
    this.closed = false
    if (this.resultsContainer) this.resultsContainer.hidden = false
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
        this.openResults()
        if (results.length > 0) {
          this.highlightedIndex = Math.min(this.highlightedIndex + 1, results.length - 1)
          this.updateHighlight()
          this.scrollToHighlighted()
        }
        break

      case "ArrowUp":
        e.preventDefault()
        this.openResults()
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
        this.closeResults()
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
