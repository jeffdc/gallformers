// Client-side tab switching with keyboard navigation (ArrowLeft/Right, Home, End)
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

export default Tabs
