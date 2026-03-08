// RegionScope hook for the per-page region scope widget
const RegionScope = {
  mounted() {
    const toggle = this.el.querySelector("[data-region-toggle]")
    const dropdown = this.el.querySelector("[data-region-dropdown]")

    if (toggle && dropdown) {
      toggle.addEventListener("click", (e) => {
        e.stopPropagation()
        dropdown.classList.toggle("hidden")
      })

      // Close on click-away
      document.addEventListener("click", (e) => {
        if (!this.el.contains(e.target)) {
          dropdown.classList.add("hidden")
        }
      })
    }

    // Use event delegation for "Set as default" since the button is conditionally
    // rendered (only appears after an override) and won't exist at mount time
    this.el.addEventListener("click", (e) => {
      const saveBtn = e.target.closest("[data-region-save]")
      if (!saveBtn) return

      const active = this.el.querySelector("[data-region-code].font-bold")
      const currentCode = active ? active.dataset.regionCode : ""
      if (currentCode === "") {
        localStorage.removeItem("gf_continent")
      } else {
        localStorage.setItem("gf_continent", currentCode)
      }
      localStorage.setItem("gf_continent_dismissed", "true")
      // Reload to propagate the new default across the session
      window.location.reload()
    })
  }
}

export default RegionScope
